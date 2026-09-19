import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import Observation

nonisolated struct AudioInputDevice: Identifiable, Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

nonisolated enum InputDeviceChoice {
    static func resolve(
        preferredUID: String?, available: @autoclosure () -> [AudioInputDevice]
    ) -> AudioInputDevice? {
        guard let preferredUID else { return nil }
        return available().first { $0.uid == preferredUID }
    }
}

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

@Observable
final class AudioInputDeviceList {
    private(set) var devices: [AudioInputDevice] = []
    private(set) var systemDefault: AudioInputDevice?

    @ObservationIgnored nonisolated(unsafe) private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init() {
        refresh()
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioInputDeviceQuery.globalAddress(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh() }
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
