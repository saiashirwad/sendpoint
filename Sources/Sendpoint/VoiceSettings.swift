import Foundation
import Observation

@Observable
final class VoiceSettings {
    private enum Key {
        static let voiceMode = "voiceMode"
        static let inputDeviceUID = "inputDeviceUID"
        static let inputDeviceName = "inputDeviceName"
    }

    private let defaults: UserDefaults
    private(set) var voiceMode: VoiceRecordingMode
    private(set) var inputDeviceUID: String?
    private(set) var inputDeviceName: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        voiceMode = defaults.string(forKey: Key.voiceMode).flatMap(VoiceRecordingMode.init(rawValue:)) ?? .hold
        let storedUID = defaults.string(forKey: Key.inputDeviceUID)
        inputDeviceUID = storedUID
        inputDeviceName = storedUID == nil ? nil : defaults.string(forKey: Key.inputDeviceName)
    }

    func setVoiceMode(_ mode: VoiceRecordingMode) {
        guard mode != voiceMode else { return }
        voiceMode = mode
        defaults.set(mode.rawValue, forKey: Key.voiceMode)
    }

    func setInputDevice(uid: String?, name: String?) {
        inputDeviceUID = uid
        inputDeviceName = uid == nil ? nil : name
        defaults.set(inputDeviceUID, forKey: Key.inputDeviceUID)
        defaults.set(inputDeviceName, forKey: Key.inputDeviceName)
    }
}
