import SwiftUI

struct SettingsPreviewPane: View {
    @Bindable var voiceSettings: VoiceSettings

    var body: some View {
        SettingsPage {
            SettingsSection("Card") {
                SettingsToggleRow(
                    "Show while recording",
                    detail: cardFootnote,
                    isOn: Binding(
                        get: { voiceSettings.transcriptionPreview },
                        set: { voiceSettings.send(.transcriptionPreview($0)) }
                    )
                )
                if voiceSettings.transcriptionPreview {
                    SettingsDivider()
                    SettingsStepperRow(
                        "Lines",
                        valueText: "\(voiceSettings.transcriptionPreviewLines)",
                        canDecrement: voiceSettings.transcriptionPreviewLines > VoiceSettings.previewLinesMin,
                        canIncrement: voiceSettings.transcriptionPreviewLines < VoiceSettings.previewLinesMax,
                        decrement: {
                            voiceSettings.send(.stepPreviewLines(-1))
                        },
                        increment: {
                            voiceSettings.send(.stepPreviewLines(1))
                        }
                    )
                    SettingsDivider()
                    SettingsStepperRow(
                        "Font size",
                        valueText: "\(voiceSettings.transcriptionPreviewFontSize)",
                        canDecrement: voiceSettings.transcriptionPreviewFontSize > VoiceSettings.previewFontSizeMin,
                        canIncrement: voiceSettings.transcriptionPreviewFontSize < VoiceSettings.previewFontSizeMax,
                        decrement: {
                            voiceSettings.send(.stepPreviewFontSize(-1))
                        },
                        increment: {
                            voiceSettings.send(.stepPreviewFontSize(1))
                        }
                    )
                }
            }
            SettingsSection("Look") {
                SettingsStepperRow(
                    "Opacity",
                    valueText: "\(voiceSettings.transcriptionPreviewOpacity)%",
                    canDecrement: voiceSettings.transcriptionPreviewOpacity > VoiceSettings.previewOpacityMin,
                    canIncrement: voiceSettings.transcriptionPreviewOpacity < VoiceSettings.previewOpacityMax,
                    decrement: {
                        voiceSettings.send(.stepPreviewOpacity(-1))
                    },
                    increment: {
                        voiceSettings.send(.stepPreviewOpacity(1))
                    }
                )
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
