import Foundation
import Observation

enum VoiceSettingsEvent: Equatable {
    case voiceMode(VoiceRecordingMode)
    case inputDevice(uid: String?, name: String?)
    case transcriptionPreview(Bool)
    case transcriptionPreviewLines(Int)
    case transcriptionPreviewFontSize(Int)
    case transcriptionPreviewOpacity(Int)
}

@Observable
final class VoiceSettings {
    private enum Key {
        static let voiceMode = "voiceMode"
        static let inputDeviceUID = "inputDeviceUID"
        static let inputDeviceName = "inputDeviceName"
        static let transcriptionPreview = "transcriptionPreview"
        static let transcriptionPreviewLines = "transcriptionPreviewLines"
        static let transcriptionPreviewFontSize = "transcriptionPreviewFontSize"
        static let transcriptionPreviewOpacity = "transcriptionPreviewOpacity"
    }

    static let previewLinesMin = 2
    static let previewLinesMax = 5
    static let defaultPreviewLines = 4
    static let previewFontSizeMin = 11
    static let previewFontSizeMax = 16
    static let defaultPreviewFontSize = 13
    static let previewOpacityMin = 50
    static let previewOpacityMax = 100
    static let previewOpacityStep = 10
    static let defaultPreviewOpacity = 80

    private let defaults: UserDefaults
    private(set) var voiceMode: VoiceRecordingMode
    private(set) var inputDeviceUID: String?
    private(set) var inputDeviceName: String?
    private(set) var transcriptionPreview: Bool
    private(set) var transcriptionPreviewLines: Int
    private(set) var transcriptionPreviewFontSize: Int
    private(set) var transcriptionPreviewOpacity: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        voiceMode = defaults.string(forKey: Key.voiceMode).flatMap(VoiceRecordingMode.init(rawValue:)) ?? .hold
        let storedUID = defaults.string(forKey: Key.inputDeviceUID)
        inputDeviceUID = storedUID
        inputDeviceName = storedUID == nil ? nil : defaults.string(forKey: Key.inputDeviceName)
        transcriptionPreview = defaults.object(forKey: Key.transcriptionPreview) as? Bool ?? true
        transcriptionPreviewLines = Self.clampedPreviewLines(
            defaults.object(forKey: Key.transcriptionPreviewLines) as? Int
        )
        transcriptionPreviewFontSize = Self.clampedPreviewFontSize(
            defaults.object(forKey: Key.transcriptionPreviewFontSize) as? Int
        )
        transcriptionPreviewOpacity = Self.clampedPreviewOpacity(
            defaults.object(forKey: Key.transcriptionPreviewOpacity) as? Int
        )
    }

    func setVoiceMode(_ mode: VoiceRecordingMode) {
        guard mode != voiceMode else { return }
        voiceMode = mode
        defaults.set(mode.rawValue, forKey: Key.voiceMode)
    }

    func setTranscriptionPreview(_ on: Bool) {
        guard on != transcriptionPreview else { return }
        transcriptionPreview = on
        defaults.set(on, forKey: Key.transcriptionPreview)
    }

    func setTranscriptionPreviewLines(_ lines: Int) {
        let lines = Self.clampedPreviewLines(lines)
        guard lines != transcriptionPreviewLines else { return }
        transcriptionPreviewLines = lines
        defaults.set(lines, forKey: Key.transcriptionPreviewLines)
    }

    func setTranscriptionPreviewFontSize(_ size: Int) {
        let size = Self.clampedPreviewFontSize(size)
        guard size != transcriptionPreviewFontSize else { return }
        transcriptionPreviewFontSize = size
        defaults.set(size, forKey: Key.transcriptionPreviewFontSize)
    }

    func setTranscriptionPreviewOpacity(_ percent: Int) {
        let percent = Self.clampedPreviewOpacity(percent)
        guard percent != transcriptionPreviewOpacity else { return }
        transcriptionPreviewOpacity = percent
        defaults.set(percent, forKey: Key.transcriptionPreviewOpacity)
    }

    static func clampedPreviewLines(_ lines: Int?) -> Int {
        let lines = lines ?? defaultPreviewLines
        return min(max(lines, previewLinesMin), previewLinesMax)
    }

    static func clampedPreviewFontSize(_ size: Int?) -> Int {
        let size = size ?? defaultPreviewFontSize
        return min(max(size, previewFontSizeMin), previewFontSizeMax)
    }

    static func clampedPreviewOpacity(_ percent: Int?) -> Int {
        let percent = percent ?? defaultPreviewOpacity
        let stepped = Int((Double(percent) / Double(previewOpacityStep)).rounded()) * previewOpacityStep
        return min(max(stepped, previewOpacityMin), previewOpacityMax)
    }

    func setInputDevice(uid: String?, name: String?) {
        inputDeviceUID = uid
        inputDeviceName = uid == nil ? nil : name
        defaults.set(inputDeviceUID, forKey: Key.inputDeviceUID)
        defaults.set(inputDeviceName, forKey: Key.inputDeviceName)
    }

    func send(_ event: VoiceSettingsEvent) {
        switch event {
        case .voiceMode(let mode): setVoiceMode(mode)
        case .inputDevice(let uid, let name): setInputDevice(uid: uid, name: name)
        case .transcriptionPreview(let on): setTranscriptionPreview(on)
        case .transcriptionPreviewLines(let lines): setTranscriptionPreviewLines(lines)
        case .transcriptionPreviewFontSize(let size): setTranscriptionPreviewFontSize(size)
        case .transcriptionPreviewOpacity(let percent): setTranscriptionPreviewOpacity(percent)
        }
    }
}
