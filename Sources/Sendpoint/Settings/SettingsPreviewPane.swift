import SwiftUI

struct SettingsPreviewPane: View {
    @Bindable var voiceSettings: VoiceSettings
    let captureController: CaptureController

    var body: some View {
        SettingsPage {
            SettingsSection("Card") {
                SettingsToggleRow(
                    "Show while recording",
                    detail: cardFootnote,
                    isOn: Binding(
                        get: { voiceSettings.transcriptionPreview },
                        set: { captureController.setTranscriptionPreview($0) }
                    )
                )
            }
            if voiceSettings.transcriptionPreview {
                SettingsSection("Look") {
                    SettingsStepperRow(
                        "Lines",
                        valueText: "\(voiceSettings.transcriptionPreviewLines)",
                        canDecrement: voiceSettings.transcriptionPreviewLines > VoiceSettings.previewLinesMin,
                        canIncrement: voiceSettings.transcriptionPreviewLines < VoiceSettings.previewLinesMax,
                        decrement: {
                            captureController.stepTranscriptionPreviewLines(bySteps: -1)
                        },
                        increment: {
                            captureController.stepTranscriptionPreviewLines(bySteps: 1)
                        }
                    )
                    SettingsDivider()
                    SettingsStepperRow(
                        "Font size",
                        valueText: "\(voiceSettings.transcriptionPreviewFontSize)",
                        canDecrement: voiceSettings.transcriptionPreviewFontSize > VoiceSettings.previewFontSizeMin,
                        canIncrement: voiceSettings.transcriptionPreviewFontSize < VoiceSettings.previewFontSizeMax,
                        decrement: {
                            captureController.stepTranscriptionPreviewFontSize(bySteps: -1)
                        },
                        increment: {
                            captureController.stepTranscriptionPreviewFontSize(bySteps: 1)
                        }
                    )
                    SettingsDivider()
                    SettingsStepperRow(
                        "Opacity",
                        valueText: "\(voiceSettings.transcriptionPreviewOpacity)%",
                        canDecrement: voiceSettings.transcriptionPreviewOpacity > VoiceSettings.previewOpacityMin,
                        canIncrement: voiceSettings.transcriptionPreviewOpacity < VoiceSettings.previewOpacityMax,
                        decrement: {
                            captureController.stepTranscriptionPreviewOpacity(bySteps: -1)
                        },
                        increment: {
                            captureController.stepTranscriptionPreviewOpacity(bySteps: 1)
                        }
                    )
                }
            }
        }
    }

    private var cardFootnote: String {
        if voiceSettings.transcriptionPreview {
            return "Replaces the capsule with a card that shows your words as you speak."
        }
        return "A small capsule shows instead. The note still saves either way."
    }
}
