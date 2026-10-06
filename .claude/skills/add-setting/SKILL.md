---
name: add-setting
description: How to add a Sendpoint preference: general (AppSettings), voice/preview (VoiceSettings), or template field. Use before adding or changing any setting.
---

# Adding a setting

Three stores. Extend the one that already owns the value. Do not write the value from the view.

- `AppSettings` and `AppSettingsEvent` are the general preferences: paste versus copy, launch at login, and restore focus. The pane calls `settings.send(...)`. See `SettingsPastingPane` and `SettingsSystemPane`.
- `VoiceSettings` and `VoiceSettingsEvent` are the voice mode, the microphone order, and the transcript preview.
- `TemplateSettings` owns a `TemplateWorkspace`: the committed collection and an optional editing session. It receives `TemplateWorkspaceEvent`.

Paste versus copy, as it exists:

- The event is `AppSettingsEvent.exportMode(StackExportMode)`.
- The stored property is `pasteDirectly`. The UserDefaults key is `"pasteDirectly"` (`AppSettings.Key.pasteDirectly`).
- `setPasteDirectly` returns when the Bool is unchanged, then assigns it and writes the key.
- `send` calls `setPasteDirectly(mode == .paste)`.
- `SettingsPastingPane` sends `.exportMode` from the chip binding. It does not assign `pasteDirectly`.
- `SettingsIntentTests.testAppSettingsEventsPersistAcrossInstances` sends the event and reloads `AppSettings` from the same defaults.

`restoreFocusAfterSave` is the same shape: event `.restoreFocusAfterSave`, key `"restoreFocusAfterSave"`, `setRestoreFocusAfterSave`, and `settings.send` from `SettingsPastingPane`. `launchAtLogin` also goes through `settings.send` from `SettingsSystemPane`, and `setLaunchAtLogin` returns when the value is unchanged. It is not a UserDefaults key. It calls the injected login-item closures. `hasCompletedSetup` is not an event. `completeSetup()` writes it.

A new general preference copies `restoreFocusAfterSave`:

1. Add an `AppSettingsEvent` case.
2. Add a key on `AppSettings.Key`, a `private(set)` property, and the read in `init`.
3. Add a private setter that returns when the value is unchanged, then writes `defaults`.
4. Handle the case in `send`.
5. Call `settings.send` from the pane. Do not assign the property or touch UserDefaults in the view.
6. Add a test beside `testAppSettingsEventsPersistAcrossInstances` in `Tests/SendpointTests/SettingsIntentTests.swift`.

A new voice or preview value copies `transcriptionPreview`:

1. Add a `VoiceSettingsEvent` case.
2. Add a key on `VoiceSettings.Key`, a `private(set)` property, and the read in `init`.
3. Add a private setter that returns when the value is unchanged, then writes `defaults`. The line, font-size, and opacity setters clamp before that check.
4. Handle the case in `send`.
5. Do not assign the property from the view. `SettingsPreviewPane` sends directly to `VoiceSettings`; preview step events also belong there. `SettingsCapturePane` calls `CaptureController.setVoiceMode` because it changes the capture machine. `updateMicrophones` also pushes the order to the recorder.
6. Add a test beside `testVoiceSettingsEventsPersistAndClamp` in `SettingsIntentTests.swift`.

A new template field is not an `AppSettingsEvent`. Add the property on `Template`, add a `TemplateWorkspaceEvent`, and handle it in `TemplateWorkspace.update`. `SettingsTemplatesPane` sends the field edits through `TemplateSettings.send`. Edits affect only the session draft. `.save` and `.saveAsNew(name:id:)` commit through `TemplateCollection`; failed validation preserves the draft and pending destination. `TemplateSettings.send` persists only committed collection changes to `"templates"` and `"activeTemplateID"`. Template switching and closing share `.request(TemplateDestination)` and `.resolve(TemplateDirtyDecision)`. Add field-intent coverage in `SettingsIntentTests.swift`, transition coverage in `TemplateWorkspaceTests.swift`, and persistence coverage in `TemplateSettingsTests.swift`.
