# Engineering rules

- Use Swift Observation for app-owned state. Do not add `ObservableObject`, `@Published`, or TCA.
- Model finite workflows with closed enums, one event transition function, and one idempotent teardown path.
- Keep data transformations pure and outside views.
- Give each lifecycle task one owner. Retain and cancel its handle; do not use `Task.detached` for lifecycle work.
- Check cancellation around external calls. Apply a result only when its full context still matches the current state.
- Inject small system boundaries for deterministic tests. Test behavior, including cancellation, stale results, invalid transitions, and teardown.
- Make clean cutovers. Delete obsolete callers, state, settings, imports, and files.
- Finish every requested change by running `./build.sh` then `./install.sh`, so the installed Sendpoint always reflects the latest work. Do this before reporting the change as done.
- Publish only with `./release.sh X.Y.Z --ad-hoc --publish`.

# Folder map

`./check.sh` is the quick verify: it builds and runs the tests. It does not assemble or install. `./build.sh` then `./install.sh` is still how a change reaches the installed app.

**Sources/SendpointDomain.** Pure types. No AppKit. Every file imports Foundation. `StackStore.swift` also imports Observation. `CaptureState.swift` also imports CoreGraphics. `Models.swift` holds `Subject`, `Note`, `Stack`, `ClearedBatch`, and `StackDocument`. `NoteCreation.swift` builds a note from a selection and a body. `NoteListing.swift` filters notes with a query. `TextNormalization.swift` is the shared blank-and-match helpers. `StackDocumentMutations.swift` validates a document and applies one `StackDocumentMutation`. `StackStore.swift` is the observable queue: it loads, mutates, commits, and tears down. `StorePersistence.swift` loads and commits `store.json`. `Template.swift` and `TemplateCollection.swift` are the template value and the collection rules. `PromptComposer.swift` renders a stack, or one note, as Markdown. The pure machines and the action catalog live here: `CaptureState`, `VoiceMachine`, `StackSelectMachine`, `PaletteWorkflow`, `PaletteActions`, and the stack facts they render (`StackUIFacts.swift`).

**Sources/Sendpoint/App.** Process lifecycle. `Main.swift` starts the accessory app and refuses a second instance. `AppDelegate.swift` owns launch, reopen, and termination. `AppDelegate+Actions.swift` performs status-menu actions and registers hotkeys. `AppDelegate+Surfaces.swift` presents the palette, setup, and settings. `AppDelegate+Store.swift` bootstraps `StackStore`, then builds the palette, the latest-note editor, and the stack switcher. `AppEnvironment.swift` constructs the long-lived objects, including `CaptureController`. `StatusItemController`, `StatusMenuModel`, and `MenuBarIcon` are the menu bar. `SurfaceCoordinator` tracks which surfaces are visible and sets the activation policy. `UpdateController` checks for updates through Sparkle. `LaunchPresentation` chooses setup, settings, or nothing.

**Sources/Sendpoint/Capture.** The capture workflow. The capture machine, `CaptureState`, lives in SendpointDomain. `CaptureController` owns it. `CaptureWindows` shows the editor and the voice panel. `SelectionCapture` reads the selection and pastes or inserts text. `AutomaticSelectionMonitor` watches the global mouse so a recent selection can be reused. `LatestNoteEditor` edits the newest note in the current stack. `LatestNoteEditorWindow` hosts it. The SwiftUI is `CaptureView`, `CaptureDestinationPanel`, `NoteEditor`, and `LatestNoteEditorView`.

**Sources/Sendpoint/Input.** Global shortcuts. `ShortcutSettings` stores one `KeyCombo` per `ShortcutSlot`. `HotKeyRegistrar` binds those slots to actions. `HotKeyCenter` registers them. `KeyRecorder` is the settings control that records a combo.

**Sources/Sendpoint/Palette.** The stack palette. `PaletteWorkflow` and the action catalog `PaletteActions` (`PaletteActionCatalog`, not the workflow state) live in SendpointDomain. `StackPaletteController` owns the workflow and runs `PaletteEffect`. `StackPaletteWindow` hosts `StackPaletteView`. Switching stacks from inside the palette stays in this workflow.

**Sources/Sendpoint/StackSwitcher.** The separate app-wide stack switcher. `StackSelectMachine` lives in SendpointDomain and decides. `StackSelector` performs the switch and the readout timer. `StackReadout` shows the number. This is not the palette's own stack switching. `AppDelegate.selectStack` calls `stackSelector.select`.

**Sources/Sendpoint/Platform.** `ExportController` copies or pastes Markdown and can clear the exported notes. `PermissionState` and `PermissionCheck` cover accessibility, the microphone, and the local voice model. `LatestValuePump` keeps the newest progress value.

**Sources/Sendpoint/Settings.** The settings window (`SettingsWindowController`, `SettingsView`, and the panes), first-run setup (`SetupWindowController`, `SetupView`, `SetupTour`), and templates (`TemplateSettings`, `TemplateEditorState`, `SettingsTemplatesPane`). `AppSettings` holds the general preferences.

**Sources/Sendpoint/SharedUI.** Theme and controls. `Theme.swift` is type and color. `Controls.swift` is the shared SwiftUI controls. `ScrollBridge.swift` scrolls note lists. `PreviewSupport.swift` is preview copy.

**Sources/Sendpoint/Voice.** Recording and transcription. `VoiceMachine` lives in SendpointDomain and is the phase machine. `VoiceNoteService` owns that machine, the microphone, and the transcriber. `VoiceSettings` stores the voice mode, the microphone order, and the transcript preview. `VoiceTranscriber` and `VoiceAudio` are the model and the audio path. `VoiceCaptureView` is the overlay.

**Tests/SendpointDomainTests.** Tests the SendpointDomain target, including pure machine transitions.

**Tests/SendpointTests.** Tests the Sendpoint target. The target also depends on SendpointDomain. Controller tests stay here.

# The shape to copy

Copy `CaptureState` and `CaptureController`. There is no shared generic runtime. The machines differ, so copy this shape instead of adding a base type. The pure machines and the action catalog live in SendpointDomain. Controllers stay in the app folders.

The vocabulary is Event, `update`, Effect, and an XController.

`CaptureEvent` comes in. `CaptureEffect` goes out. `CaptureState` is a value. Its lifecycle is `idle`, `active`, or `tornDown`. `update(_ event:) -> [CaptureEffect]` is the only transition. Teardown is idempotent: `.teardown` sets `tornDown` and returns `[.close]`; once `tornDown`, `update` returns no effects.

`CaptureController` owns the state, a pending event queue, and the task handles. `send` appends and drains. `run` performs effects. Async work is a `Task` stored on the controller. `launch` checks cancellation around the call and applies the event only when `state.session?.context` still matches. `teardown()` returns if the state is already torn down. Otherwise it sends `.teardown`, then drops the surfaces, the store, and `onAccessibilityRequired`.

`VoiceMachine` (driven by `VoiceNoteService`), `StackSelectMachine` (driven by `StackSelector`), and `ExportController` (`ExportState` in the same file) already follow this shape. `PaletteWorkflow` is the palette's own machine. Its transition is `PaletteUpdate.update`, which returns `Bool` and appends `PaletteEffect`. Copy Capture for a new machine.

These files do not follow this shape. Do not copy them:

- `PermissionState`. Several state enums (`AccessibilityPermissionState`, `MicrophonePermissionState`, `LocalVoiceModelState`), an `isTornDown` flag, and methods that both change state and start `Task`s (`requestMicrophone`, `downloadModel`, `startWatchingVoiceModel`).
- `LatestNoteEditor`. `send` reads the store and calls `store.mutate` while deciding.
- `TemplateEditorState`. `TemplateEditorEvent` covers field edits. Unsaved-changes prompts and switching templates go through throwing methods (`requestSelection`, `resolvePendingSelection`, `resolveClose`, `save`, `delete`).
- `SurfaceCoordinator`.
- `AutomaticSelectionMonitor`.

# Guides

## Adding a setting

Three stores. Extend the one that already owns the value. Do not write the value from the view.

- `AppSettings` and `AppSettingsEvent` are the general preferences: paste versus copy, launch at login, and restore focus. The pane calls `settings.send(...)`. See `SettingsPastingPane` and `SettingsSystemPane`.
- `VoiceSettings` and `VoiceSettingsEvent` are the voice mode, the microphone order, and the transcript preview.
- `TemplateSettings` is the template collection. It has no event enum.

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
5. Do not assign the property from the view. `SettingsCapturePane` and `SettingsPreviewPane` call `CaptureController`. `setVoiceMode`, `setTranscriptionPreview`, `stepTranscriptionPreviewLines`, `stepTranscriptionPreviewFontSize`, `stepTranscriptionPreviewOpacity`, and `updateMicrophones` are the methods that send. `updateMicrophones` also pushes the order to the recorder.
6. Add a test beside `testVoiceSettingsEventsPersistAndClamp` in `SettingsIntentTests.swift`.

A new template field is not an `AppSettingsEvent`. Add the property on `Template`, add a `TemplateEditorEvent`, and handle it in `TemplateEditorState.send`. `SettingsTemplatesPane` already sends `.editName`, `.editPreamble`, and the include and clear flags. Save still goes through `editor.save()`, which calls `settings.updateTemplate`. `TemplateSettings.change` returns when the collection is unchanged, then writes the `"templates"` data and, if needed, `"activeTemplateID"`. Switching templates and the unsaved-changes prompt stay on `requestSelection`, `resolvePendingSelection`, and `resolveClose`. Add a test beside `testTemplateEditorEventsUpdateOnlyTheirField` in `SettingsIntentTests.swift`. Persistence of the collection is already covered by `TemplateSettingsTests`.

## Adding a shortcut

`ShortcutSlot` lives in `Sources/Sendpoint/Input/ShortcutSettings.swift`. Add a slot in this order:

1. Add the case. Put it in `allCases` (`selectStack` is generated as `selectStackCases`). Add `rawValue`, `title`, and `isOptional`. `.dictate`, `.selectStack`, and `.editLatest` are optional and may have no combo. `clearShortcut` returns immediately unless the slot is optional.
2. Give a required slot a default in `fixedDefaultCombos`. Give an optional slot a default in `optionalDefaultCombos` only when the combo should appear if it is free (select stack, edit latest). Dictate is optional, but its default is in `fixedDefaultCombos`: it starts bound, and clearing it stores the empty unbound marker. An optional slot with no default goes in neither map. The defaults key is `slot.rawValue + "Combo"`.
3. Add a closure on `HotKeyRegistrar.Actions`. Handle the case in the `switch slot` inside `HotKeyRegistrar.register`. `HotKeyName.slot` already wraps every `ShortcutSlot`. Do not add a `HotKeyName` case.
4. Pass that closure from `AppDelegate.registerHotKeys` in `Sources/Sendpoint/App/AppDelegate+Actions.swift`. That closure is the behavior. Edit latest calls `latestNoteEditor?.model.send(.open)`.
5. Show a `ShortcutSpec` in the pane that already lists that group. `SettingsCapturePane` lists `.voiceCapture`, `.capture`, and `.dictate`. `SettingsStacksPane` lists `ShortcutSlot.selectStackCases`, then `.stack`, `.editLatest`, and `.clear`. `SettingsPastingPane` lists `.copy`. `ShortcutRows` writes the combo through `hotKeyRegistrar.updateShortcut`. The recorder is clearable when `slot.isOptional`. Do not call `setShortcut` from the view.
6. `StatusMenuModel.items` shows a combo for voice note, typed note, dictate (only when `dictateCombo` is set), show stack, each stack, copy, and clear. It does not show edit latest. Add a row only if this shortcut belongs in the status menu: a `StatusMenuAction` case, an entry in `items`, and a case in `AppDelegate.perform`. `MainMenu.build` is Close Window and the Edit menu. It does not list `ShortcutSlot`s. Do not add one there.
7. Add a test beside the suite for that group: `VoiceShortcutSettingsTests`, `StackShortcutSettingsTests`, `HotKeyRegistrarTests`, or `StatusMenuModelTests` when the menu shows the combo.

## Adding a new state machine

Copy Capture. Do not add a base type. Put the Event / Effect / State / `update` file in SendpointDomain. Mark the types public. Keep AppKit and SwiftUI out of that file. Put the XController in the app. Put transition tests in SendpointDomainTests.

1. Add the machine file in `Sources/SendpointDomain`. Import Foundation, and CoreGraphics only when a value needs it. No AppKit. Add a closed event enum, a closed effect enum, and a state value whose lifecycle includes `tornDown`. `CaptureState.Lifecycle` is `idle`, `active`, or `tornDown`. One `mutating func update(_ event:) -> [Effect]` is the only transition. Once `tornDown`, `update` returns no effects. Mark the types `public`. Mark properties, methods, and initializers `public` when the app or the tests call them. Write a public init when another module constructs the value.
2. Add an XController in the app folder that owns the workflow. It owns the state, a pending event queue, and the task handles. `send` appends and drains, as `CaptureController.send` does. One method performs the effects. Store each async `Task` on the controller and cancel it from that owner. Check cancellation around the external call. Apply the result only when its full context still matches, as `CaptureController.launch` requires `state.session?.context == context` after the await. `teardown()` sends `.teardown`, then drops surfaces, the store, and callbacks. A second call returns without sending.
3. Inject the system boundary as a small struct of closures, the way `CaptureController` takes `VoiceRecorder` and `CaptureSurfaces`. Tests pass fakes and do not open AppKit windows.
4. Test the controller in `Tests/SendpointTests`, using `CaptureControllerTests` as the model. Cover cancellation (`testModeChangeMidCaptureCancelsIt`), a stale result (`testDismissBeforeTheSelectionArrivesRejectsTheLateResult`), an invalid transition (`testRejectedDestinationChoicesDoNotChangeTheCurrentStack`: the wrong context or an unknown stack does nothing), and teardown (`testTeardownClosesDiscardsAndIgnoresEverythingAfter`: a second teardown is a no-op and later events do nothing). Put transition tests that only drive `update` in `Tests/SendpointDomainTests`. `CaptureSaveLifecycleTests` drives `CaptureState.update` directly for ignored events (`testStaleOutcomesAreIgnored`; a second `.selection` returns `[]`).
5. Construct a controller that does not need the store in `AppEnvironment.init`, where `captureController` is created. Read it from `AppDelegate` the way `captureController` is read. A controller that needs `StackStore` cannot be built there. `AppDelegate.bootstrapStore` creates `StackSelector` only after the store has loaded. Follow that call site.
