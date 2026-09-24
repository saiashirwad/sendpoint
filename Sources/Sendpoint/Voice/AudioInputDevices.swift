import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import Observation

nonisolated enum AudioInputTransport: Equatable, Sendable {
    case builtIn
    case bluetooth
    case other
}

nonisolated struct AudioInputDevice: Identifiable, Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: AudioInputTransport
}

nonisolated struct RankedMicrophone: Codable, Equatable, Sendable {
    let uid: String
    var name: String
    var isEnabled = true
}

nonisolated struct MicrophoneOrder: Codable, Equatable, Sendable {
    private(set) var entries: [RankedMicrophone] = []

    mutating func absorb(_ devices: [AudioInputDevice], systemDefault: AudioInputDevice?) {
        for device in devices {
            guard let index = entries.firstIndex(where: { $0.uid == device.uid }) else { continue }
            entries[index].name = device.name
        }
        let seedsFromDefault = entries.isEmpty
        let fresh = devices.filter { device in !entries.contains { $0.uid == device.uid } }
        func rank(_ device: AudioInputDevice) -> Int {
            switch device.transport {
            case .bluetooth: 3
            case _ where seedsFromDefault && device == systemDefault: 0
            case .builtIn: 1
            case .other: 2
            }
        }
        let ranked = fresh.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
        entries.insert(
            contentsOf: ranked.map { RankedMicrophone(uid: $0.element.uid, name: $0.element.name) },
            at: enabledCount
        )
    }

    mutating func move(uid: String, toIndex index: Int) {
        guard let from = entries.firstIndex(where: { $0.uid == uid && $0.isEnabled }) else { return }
        let entry = entries.remove(at: from)
        entries.insert(entry, at: min(max(index, 0), enabledCount))
    }

    mutating func setEnabled(_ isEnabled: Bool, uid: String) {
        guard let index = entries.firstIndex(where: { $0.uid == uid && $0.isEnabled != isEnabled }) else { return }
        var entry = entries.remove(at: index)
        entry.isEnabled = isEnabled
        entries.insert(entry, at: enabledCount)
    }

    private var enabledCount: Int {
        entries.prefix(while: \.isEnabled).count
    }

    mutating func forget(uid: String) {
        entries.removeAll { $0.uid == uid }
    }

    func active(among available: [AudioInputDevice], systemDefault: AudioInputDevice?) -> AudioInputDevice? {
        var order = self
        order.absorb(available, systemDefault: systemDefault)
        for entry in order.entries where entry.isEnabled {
            if let device = available.first(where: { $0.uid == entry.uid }) { return device }
        }
        return nil
    }
}

nonisolated struct MicrophoneListFacts: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let name: String
        let isEnabled: Bool
        let isConnected: Bool
        let isActive: Bool

        var status: String? {
            if isActive { return "In use" }
            return isConnected ? nil : "Not connected"
        }
    }

    static let nothingUsable = "No connected microphone is switched on, so nothing can be recorded."

    let rows: [Row]
    let tucked: [Row]
    let footnote: String?

    init(order: MicrophoneOrder, devices: [AudioInputDevice], systemDefault: AudioInputDevice?) {
        var order = order
        order.absorb(devices, systemDefault: systemDefault)
        let active = order.active(among: devices, systemDefault: systemDefault)
        let all = order.entries.map { entry in
            Row(
                id: entry.uid,
                name: entry.name,
                isEnabled: entry.isEnabled,
                isConnected: devices.contains { $0.uid == entry.uid },
                isActive: entry.uid == active?.uid
            )
        }
        rows = all.filter(\.isEnabled)
        tucked = all.filter { !$0.isEnabled }
        footnote = active == nil ? Self.nothingUsable : nil
    }

    static func tuckedLabel(count: Int) -> String {
        "\(count) switched off"
    }

    static func dropIndex(from origin: Int, translation: CGFloat, rowHeight: CGFloat, count: Int) -> Int {
        guard rowHeight > 0, count > 0 else { return origin }
        let shift = Int((translation / rowHeight).rounded())
        return min(max(origin + shift, 0), count - 1)
    }
}

nonisolated enum AudioInputDeviceQuery {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    static func allInputs() -> [AudioInputDevice] {
        deviceIDs().compactMap { id in
            guard inputChannelCount(of: id) > 0, !isPrivateAggregate(id),
                  let uid = string(kAudioDevicePropertyDeviceUID, of: id),
                  let name = string(kAudioObjectPropertyName, of: id)
            else { return nil }
            return AudioInputDevice(id: id, uid: uid, name: name, transport: transport(of: id))
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
        return AudioInputDevice(id: id, uid: uid, name: name, transport: transport(of: id))
    }

    static func bind(_ order: MicrophoneOrder, to input: AVAudioInputNode) -> Bool {
        guard let device = preferred(order) else { return false }
        return bind(device, to: input)
    }

    static func preferred(_ order: MicrophoneOrder) -> AudioInputDevice? {
        order.active(among: allInputs(), systemDefault: defaultInput())
    }

    static func bind(_ device: AudioInputDevice, to input: AVAudioInputNode) -> Bool {
        guard select(device, on: input) else { return false }
        Diag.log("input device: \(device.name)")
        return true
    }

    static func matchRate(of device: AudioInputDevice, on input: AVAudioInputNode) {
        guard let unit = input.audioUnit else { return }
        matchOutputRateToHardware(of: unit, deviceName: device.name)
    }

    private static func select(_ device: AudioInputDevice, on input: AVAudioInputNode) -> Bool {
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

    private static func isPrivateAggregate(_ id: AudioDeviceID) -> Bool {
        var address = globalAddress(kAudioAggregateDevicePropertyComposition)
        var size = UInt32(MemoryLayout<CFDictionary?>.size)
        var value: Unmanaged<CFDictionary>?
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let composition = value?.takeRetainedValue() as? [String: Any] else { return false }
        return composition[kAudioAggregateDeviceIsPrivateKey] as? Int == 1
    }

    private static func transport(of id: AudioDeviceID) -> AudioInputTransport {
        var address = globalAddress(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return .other }
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        default: return .other
        }
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
