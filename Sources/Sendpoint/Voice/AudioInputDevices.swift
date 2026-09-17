import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import Observation

/// One microphone the system knows about. The UID survives reboots and
/// unplugging; the numeric ID does not, so only the UID is ever stored.
nonisolated struct AudioInputDevice: Identifiable, Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

/// Which microphone to record from, given what the user asked for and what
/// is plugged in right now. Kept free of CoreAudio so it can be tested.
nonisolated enum InputDeviceChoice {
    /// `nil` means "leave the engine on the system default".
    /// `available` is only enumerated when there is a preference to match.
    static func resolve(
        preferredUID: String?, available: @autoclosure () -> [AudioInputDevice]
    ) -> AudioInputDevice? {
        guard let preferredUID else { return nil }
        return available().first { $0.uid == preferredUID }
    }
}

/// CoreAudio lookups for input devices. Every call is synchronous and cheap.
enum AudioInputDeviceQuery {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    static func allInputs() -> [AudioInputDevice] {
        deviceIDs().compactMap { id in
            guard inputChannelCount(of: id) > 0,
                  let uid = string(kAudioDevicePropertyDeviceUID, of: id),
                  let name = string(kAudioObjectPropertyName, of: id)
            else { return nil }
            return AudioInputDevice(id: id, uid: uid, name: name)
        }
    }

    static func defaultInput() -> AudioInputDevice? {
        var address = globalAddress(kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &id) == noErr, id != 0,
              let uid = string(kAudioDevicePropertyDeviceUID, of: id),
              let name = string(kAudioObjectPropertyName, of: id)
        else { return nil }
        return AudioInputDevice(id: id, uid: uid, name: name)
    }

    /// Points an engine's input unit at `device`. Must run before anything
    /// reads the node's format, and before the engine starts.
    ///
    /// The engine fixes the unit's output format when its input node is
    /// first touched. Switching the device underneath it leaves that format
    /// at the old sample rate; when the new device runs at another rate the
    /// unit renders nothing at all and a recording ends up empty. Copying
    /// the new hardware rate into the output format keeps them in step.
    @discardableResult
    static func select(_ device: AudioInputDevice, on input: AVAudioInputNode) -> Bool {
        guard let unit = input.audioUnit else { return false }
        var id = device.id
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            Diag.log("input device selection failed (\(status)) for \(device.name)")
            return false
        }
        matchOutputRateToHardware(of: unit, deviceName: device.name)
        return true
    }

    private static let inputElement: AudioUnitElement = 1

    private static func matchOutputRateToHardware(of unit: AudioUnit, deviceName: String) {
        guard let hardware = streamFormat(of: unit, scope: kAudioUnitScope_Input),
              var output = streamFormat(of: unit, scope: kAudioUnitScope_Output),
              hardware.mSampleRate > 0, output.mSampleRate != hardware.mSampleRate
        else { return }
        output.mSampleRate = hardware.mSampleRate
        let status = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            inputElement,
            &output,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        if status == noErr {
            Diag.log("input unit resampled to \(Int(hardware.mSampleRate))Hz for \(deviceName)")
        } else {
            Diag.log("input unit rate update failed (\(status)) for \(deviceName)")
        }
    }

    private static func streamFormat(of unit: AudioUnit, scope: AudioUnitScope) -> AudioStreamBasicDescription? {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioUnitGetProperty(
            unit, kAudioUnitProperty_StreamFormat, scope, inputElement, &format, &size
        )
        return status == noErr ? format : nil
    }

    // MARK: - Plumbing

    static func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = globalAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func inputChannelCount(of id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ selector: AudioObjectPropertySelector, of id: AudioDeviceID) -> String? {
        var address = globalAddress(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        let string = value.takeRetainedValue() as String
        return string.isEmpty ? nil : string
    }
}

/// The live list of microphones, refreshed whenever one is plugged in,
/// removed, or made the system default.
@Observable
final class AudioInputDeviceList {
    private(set) var devices: [AudioInputDevice] = []
    private(set) var systemDefault: AudioInputDevice?

    /// Removed in deinit, which is nonisolated. The array is written only
    /// during init and read only after the last reference goes away, so no
    /// concurrent access is possible, and CoreAudio's removal call is safe
    /// from any thread.
    @ObservationIgnored nonisolated(unsafe) private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init() {
        refresh()
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioInputDeviceQuery.globalAddress(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block
            )
            listeners.append((address, block))
        }
    }

    deinit {
        for (address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block
            )
        }
    }

    func refresh() {
        devices = AudioInputDeviceQuery.allInputs()
        systemDefault = AudioInputDeviceQuery.defaultInput()
    }
}
