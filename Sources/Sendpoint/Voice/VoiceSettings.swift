import Foundation
import Observation

enum VoiceSettingsEvent: Equatable {
    case voiceMode(VoiceRecordingMode)
    case microphonesSeen([AudioInputDevice], systemDefault: AudioInputDevice?)
    case moveMicrophone(uid: String, toIndex: Int)
    case microphoneEnabled(uid: String, Bool)
    case forgetMicrophone(uid: String)
    case transcriptionPreview(Bool)
    case transcriptionPreviewLines(Int)
    case transcriptionPreviewFontSize(Int)
    case transcriptionPreviewOpacity(Int)
}

@Observable
final class VoiceSettings {
    private enum Key {
        static let voiceMode = "voiceMode"
        static let microphones = "microphones"
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
    private(set) var microphones: MicrophoneOrder
    private(set) var transcriptionPreview: Bool
    private(set) var transcriptionPreviewLines: Int
    private(set) var transcriptionPreviewFontSize: Int
    private(set) var transcriptionPreviewOpacity: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        voiceMode = defaults.string(forKey: Key.voiceMode).flatMap(VoiceRecordingMode.init(rawValue:)) ?? .hold
        microphones = defaults.data(forKey: Key.microphones)
            .flatMap { try? JSONDecoder().decode(MicrophoneOrder.self, from: $0) } ?? MicrophoneOrder()
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

    private func setVoiceMode(_ mode: VoiceRecordingMode) {
        guard mode != voiceMode else { return }
        voiceMode = mode
        defaults.set(mode.rawValue, forKey: Key.voiceMode)
    }

    private func setTranscriptionPreview(_ on: Bool) {
        guard on != transcriptionPreview else { return }
        transcriptionPreview = on
        defaults.set(on, forKey: Key.transcriptionPreview)
    }

    private func setTranscriptionPreviewLines(_ lines: Int) {
        let lines = Self.clampedPreviewLines(lines)
        guard lines != transcriptionPreviewLines else { return }
        transcriptionPreviewLines = lines
        defaults.set(lines, forKey: Key.transcriptionPreviewLines)
    }

    private func setTranscriptionPreviewFontSize(_ size: Int) {
        let size = Self.clampedPreviewFontSize(size)
        guard size != transcriptionPreviewFontSize else { return }
        transcriptionPreviewFontSize = size
        defaults.set(size, forKey: Key.transcriptionPreviewFontSize)
    }

    private func setTranscriptionPreviewOpacity(_ percent: Int) {
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

    private func setMicrophones(_ order: MicrophoneOrder) {
        guard order != microphones else { return }
        microphones = order
        defaults.set(try? JSONEncoder().encode(order), forKey: Key.microphones)
    }

    private func updateMicrophones(_ change: (inout MicrophoneOrder) -> Void) {
        var order = microphones
        change(&order)
        setMicrophones(order)
    }

    func send(_ event: VoiceSettingsEvent) {
        switch event {
        case .voiceMode(let mode): setVoiceMode(mode)
        case .microphonesSeen(let devices, let systemDefault):
            updateMicrophones { $0.absorb(devices, systemDefault: systemDefault) }
        case .moveMicrophone(let uid, let index):
            updateMicrophones { $0.move(uid: uid, toIndex: index) }
        case .microphoneEnabled(let uid, let on):
            updateMicrophones { $0.setEnabled(on, uid: uid) }
        case .forgetMicrophone(let uid):
            updateMicrophones { $0.forget(uid: uid) }
        case .transcriptionPreview(let on): setTranscriptionPreview(on)
        case .transcriptionPreviewLines(let lines): setTranscriptionPreviewLines(lines)
        case .transcriptionPreviewFontSize(let size): setTranscriptionPreviewFontSize(size)
        case .transcriptionPreviewOpacity(let percent): setTranscriptionPreviewOpacity(percent)
        }
    }
}
