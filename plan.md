# Sendpoint cleanup plan

Status: implemented through Phase 5 on `main`. Phase 6 was intentionally skipped. Automated verification is complete; the Phase 2 through 5 manual dogfood checklist is still pending.

## Purpose

Turn Sendpoint into the cleanest version of itself without changing what it does. The app has one user and no compatibility obligations, so every decision below optimizes for a reader learning the shape of a small, well-built Swift app: five concepts they can hold at once, and nothing that exists only to route between them.

The expensive parts of this app are platform behaviors, not structure. The plan ports those verbatim and rebuilds the shell around them.

## Ground rules

1. Same app. No feature changes. Phase 0 fixes one real bug. Everything else is behavior-preserving.
2. Tests where behavior is subtle, and only there. A test earns its place by pinning a transition, a rejection, a cancellation, or a teardown. Tests of getters, constants, synthesized `Codable`, or menu layout do not.
3. Clean cutovers. Delete obsolete callers, fields, keys, and files in the same batch.
4. Port platform code verbatim. Keep call order byte for byte when moving it.
5. One instance of each service, built in one composition root and injected. `HotKeyCenter` stays process-wide because Carbon hotkeys are process-wide, but it is still passed in, not reached for.
6. One commit per batch. `swift test` and `./build.sh debug` pass with zero warnings before the commit.
7. The bundle ID `app.sendpoint`, the app name, and `~/Library/Application Support/Sendpoint` do not change. They are tied to TCC grants and the release pipeline.
8. No backwards compatibility for internal data. Storage keys and defaults keys follow the code. The one user deletes `store.json` once.
9. No new type for a two-branch conditional. Extract a named policy only when the logic is more than a few lines.

## Already landed

- Permission observer delivery fixed, login item rollback, app delegate retained in a static, named key constants, dead catch removed.
- Typed `HotKeyName` enum, `AppIconStore`, shared `StackRow`, `SettingsCard` renamed to `SettingsRowGroup`.
- `StatusMenuModel` plus `StatusItemController`.
- `HotKeyRegistrar`.
- Strict concurrency enabled on all targets, zero warnings.
- Test suite pruned from 224 to 184: removed tests of synthesized `Codable`, constants, getters, defaults-are-defaults, menu layout snapshots, legacy JSON shapes, and duplicates of mutation rules already pinned at the domain layer. Deleted the obsolete defaults-key cleanup loop with its test. `RuntimeCutoverTests` split into `ExportControllerTests` and `CapturePanelTests`; `ModelsAndPromptComposerTests` became `PromptComposerTests`.
- Phase 4a, `6f9ce88`: centralized window ordering in `SurfaceCoordinator`, kept the palette warm, extracted the settings window controller and main menu, and added surface, menu, and panel invariant tests.
- Phase 4b, `16c8391`: reduced `AppDelegate` to the application adapter and moved its feature actions and store bootstrap into focused extensions.
- Phase 5a, `c396d7e`: split the settings stores, built one `AppEnvironment`, removed service singletons and settings callbacks, and injected lifecycle dependencies.
- Phase 5b, `c219b7f`: split `SettingsView` into General, Shortcuts, Templates, and Permissions pane files.
- Final automated gate: 207 XCTest tests pass, the debug app builds and signs, and a forced rebuild of the touched Swift files emits zero warnings.

`AppDelegate` is 95 lines, down from 677 before the cleanup.

## Current state

- SendpointDomain holds values, pure mutations, the store, and prompt composition. Sendpoint holds the app and platform code.
- Pure state transitions with effect owners cover capture, palette, export, and stack switching. The voice gesture is part of the capture lifecycle.
- `SurfaceCoordinator` owns applied window visibility and ordering. Feature controllers request surface transitions without closing one another's windows.
- `AppEnvironment` is the composition root. App-owned settings use typed `@Observable` stores with injected `UserDefaults`; the only app singleton reach is the documented Carbon callback in `HotKeyCenter`.
- Settings content is split into four pane files, with the root view limited to navigation, layout, and dependency routing.
- 207 XCTest tests pass. The debug app builds and signs with zero warnings.
- Manual dogfood for the Phase 2 through 5 build remains pending. Phase 1 voice and typed capture were verified before the later cutovers.

## Target shape

Read top down:

1. `Main` configures `NSApplication` and hands off.
2. `AppDelegate` is an AppKit adapter. It owns the main menu, termination, and nothing else.
3. One composition root builds the environment: settings stores, the store, the feature controllers, and the surface coordinator. It is the only place a concrete service is instantiated.
4. Each feature is a pure state type plus one controller that runs effects through injected closures. Features do not reach into each other.
5. `SurfaceCoordinator` is the only code that orders windows and holds applied visibility.

That is five concepts. Anything that would add a sixth is cut.

### Ownership

| Owner | Owns | Never owns |
|---|---|---|
| `AppDelegate` | Main menu, termination, delegate callbacks | Feature state, window ordering |
| Composition root | Building and wiring concrete instances | Behavior |
| Feature controllers | One lifecycle each, with state plus effects | Other features, window ordering |
| `SurfaceCoordinator` | Applied surface state and all window ordering | Feature state, business rules |
| `StackStore` | The committed document and its serialized queue | UI, windows, permissions |

## Non-goals

- No command enum or coordinator layer between adapters and features. Hotkeys and menu items call feature controllers directly through the closures they already carry.
- No single root reducer. Features stay peer reducers.
- No protocols for every boundary. The closure struct seam is kept.
- No extra SwiftPM modules. Tests already import the executable target.
- No self-check CLI. Invariants live in tests; bundle-dependent facts are logged by `Diag` at launch.
- No rewriting platform code. AX behaviors, panel recipes, focus timing, the input unit pin, and Carbon hotkeys are ported.
- No actor store. The document is tiny and MainActor keeps views simple.
- No SwiftUI `App` lifecycle or `MenuBarExtra`. The app needs nonactivating panels, variable status titles, Carbon key release detection, and the main menu for text editing.
- No migration or quarantine code for the old store or old defaults keys.
- No release until the phases stabilize.

## Phase 0: Stop losing data on quit

One user-facing bug plus one guard. One batch.

### 0.1 Drain pending store writes before termination

Today `applicationWillTerminate` calls `store.teardown()`, which cancels the processing task and drops queued mutations. The processing task starts on the next run loop turn, so a save queued right before ⌘Q vanishes.

Work:

- Add `drain(timeout:)` to the store: returns when idle, halted, or the timeout elapses.
- In `applicationShouldTerminate`, return `.terminateLater` when the store is processing or has queued mutations, start a task that awaits the drain, then call `NSApp.reply(toApplicationShouldTerminate: true)`.
- Keep the existing profile editor check.
- No new type. The decision is one condition on the store's state.

Verification:

- Store test with a gated persistence closure: a queued mutation commits before the drain returns.
- Store test that a halted store returns from the drain at once.
- Store test that the timeout returns without the commit and leaves the store's state untouched.

### 0.2 Single instance guard

Two copies of the app can clobber `store.json`. This happens in development when the installed copy and the `dist/` build both run.

Work:

- Before `app.run()` in `Main.swift`, look for another running application with the same bundle identifier and a different process identifier. If found, activate it and exit.
- `SENDPOINT_ALLOW_MULTIPLE=1` bypasses the guard.
- A dozen lines. One pure predicate over a list of running applications, one test for it.

Done when: quitting with a queued save never drops it, and two copies do not both write the store.

## Phase 1: Compiler floor

Goal: make the compiler enforce the quality the code already claims.

Work:

- `Package.swift` to `swift-tools-version:6.2`.
- `swiftLanguageMode(.v6)` on all targets.
- `.defaultIsolation(MainActor.self)` on the app target and app test target. `SendpointDomain` stays nonisolated.
- `MemberImportVisibility` on all targets.
- Remove the `@MainActor` annotations the default isolation now covers.
- Mark the Carbon event callback and the audio tap paths `nonisolated` explicitly.
- If FluidAudio blocks Swift 6 mode, use `@preconcurrency import FluidAudio` with a comment and an upstream note. Do not weaken the app targets.

Verification: forced clean rebuild with zero warnings, 184 tests green, no behavior change.

## Phase 2: Vocabulary

Goal: one language in code, storage, and UI. One mechanical commit, done before any structural work so later phases write new code in the final vocabulary once.

Naming table:

| Today | After |
|---|---|
| `Session` | `Stack` |
| `Session.entries` | `Stack.notes` |
| `Annotation` | `Note` |
| `Annotation.note` | `Note.body` |
| `AnnotationStore` | `StackStore` |
| `AnnotationStoreError`, `AnnotationStoreMutationOutcome` | `StackStoreError`, `StackMutationOutcome` |
| `SessionDocumentMutation(s)` | `StackDocumentMutation(s)` |
| `StoreDocument` | `StackDocument` |
| `SessionUI`, `SessionItemFacts`, `SessionUndoFacts`, `SessionNameDraft`, `SessionDialogs` | `StackUI`, `StackItemFacts`, `StackUndoFacts`, `StackNameDraft`, `StackDialogs` |
| `Profile`, `ProfileCollection`, `ProfileMutationError`, `ProfileEditorState`, `ProfileDialogs` | `Template`, `TemplateCollection`, `TemplateError`, `TemplateEditorState`, `TemplateDialogs` |
| `AnnotationCaptureTarget`, `AnnotationCaptureContext`, `AnnotationCreation` | `NoteCaptureTarget`, `NoteCaptureContext`, `NoteCreation` |

Storage follows the code:

- JSON keys: `stacks`, `currentStackID`, `recentStackIDs`, `notes`, and `lastCleared` with `stackID` and `notes`. Bump `currentVersion` to 2. Drop the custom `init(from:)` on the document; every field is required.
- UserDefaults keys: `profiles` to `templates`, `activeProfileID` to `activeTemplateID`. Combo keys stay.
- Delete every compatibility comment.
- The existing version check already refuses a v1 file. Delete `~/Library/Application Support/Sendpoint/store.json` once before launching the new build.

Verification: `grep` finds no old names except this plan; tests green; a fresh launch creates a Default stack.

## Phase 3: Capture consolidation

Goal: one owner for the capture lifecycle and one for the voice gesture, testable with no microphone, no Accessibility, and no windows.

Work:

- Introduce `CaptureSurfaces`: closures for `prepare`, `show`, `focus`, `close`, `discard`, and `stopEscapeHandling`, plus the level meter. Live implementation wraps `CaptureWindows`.
- Introduce a `VoiceRecorder` boundary wrapping `VoiceAnnotationService`, injected.
- Make `SelectionCapture` a type with injected `AutomaticSelectionMonitor`, pasteboard, and event poster.
- Fold `VoiceTriggerMachine` into `CaptureState`: add voice press, release, escape, and mode change as capture actions, and record held and release-pending state on the capture session. Delete `VoiceTriggerMachine.swift`. Migrate its 8 tests into capture state tests and drop any that then duplicate an existing capture transition.
- Delete `onVoiceCaptureEnded`, `onVoiceEscape`, `AppDelegate.voiceTrigger`, `handleVoiceTrigger`, and `runVoiceCommands`.
- Drain follow-up actions instead of re-entering `send`: one queue per controller, effects enqueue follow-ups, one loop applies them. Same treatment for `ExportController.send` and `StackPaletteModel.send`.
- Focus rules (which surface takes key, whether the previous app is restored) stay inline unless they grow past a few lines.

Verification:

- New `CaptureControllerTests` with fakes: begin, selection pending, voice hold, voice tap, finish before recording starts, escape, cancel, recording failure, transcription failure, retry, retarget, teardown, stale context rejection, refused begin, mode change mid-capture.
- Dogfood voice matrix from `docs/dogfood.md`.

Done when: capture tests run headless and the callback bus is gone.

## Phase 4: Surfaces

Goal: one owner for window ordering. Derive what can be derived; keep the presentation recipes that work.

Work:

- `Surface` enum and `SurfaceCoordinator`. The coordinator is the only code that orders windows and holds applied visibility. Feature controllers ask it to show or hide a surface; they never touch another feature's window.
- The coordinator's policy is a guard on transitions, not a full derivation of visibility from app state. The existing show and hide recipes, including `orderFrontRegardless`, `makeKeyAndOrderFront`, and `afterKeystroke` sequences, remain the transition implementations byte for byte.
- Extract `SettingsWindowController` from `AppDelegate`.
- Keep the palette controller warm across openings. Reset its query and highlight on each open so behavior is unchanged.
- Delete `hideAuxiliaryWindows`, the close-before-switcher call, the `onDismiss` nil-out, and the resign-key close rule. A user close and a modal alert become inputs to the coordinator.
- `AppDelegate` becomes an `NSApplicationDelegate` adapter plus the main menu and termination. Hotkey and menu actions call feature controllers directly.

Verification:

- Coordinator tests against a spy window layer: capture hides palette, settings, and setup; switcher beats palette; a user close updates state; a modal alert suppresses resign-key dismissal; the palette reopens warm with a reset query.
- Main menu tests: key equivalents and responder actions for cut, copy, paste, select all, undo.
- Panel invariant tests from the real factories: style masks, levels, `canBecomeKey`, `ignoresMouseEvents`, collection behavior.
- Dogfood every hotkey, menu item, palette action, and switcher action.

Done when: `AppDelegate` is under 150 lines and no feature closes another feature's window.

## Phase 5: Settings

Goal: typed settings, no singleton, one composition root.

Work:

- Split `AppSettings` only where a consumer needs one slice and nothing else: `ShortcutSettings` for the registrar and settings pane, `TemplateSettings` for export and the status menu, `VoiceSettings` for the recorder. Everything else stays together as `AppSettings`. Each is `@Observable` with injected `UserDefaults`.
- One `AppEnvironment` struct built by the composition root and injected into views and controllers.
- Delete `AppSettings.shared`, `onHotKeysChanged`, `onProfilesChanged`, and `onInputDeviceChanged`. Replacement: the settings views call explicit methods on the owning controller (`rebind`, `selectTemplate`, `chooseMicrophone`) which update the store and apply the side effect in the same call. No observation loops.
- Inject `HotKeyCenter`, `AutomaticSelectionMonitor`, and the voice recorder everywhere they are currently reached through `.shared`.
- Remove the force unwraps in shortcut accessors.
- Split `SettingsView` into pane files while touching it.

Verification:

- Port the surviving `ProfileSettingsTests`, `ShortcutCollisionTests`, `StackSwitchShortcutSettingsTests`, and `VoiceShortcutSettingsTests` to the new stores.
- `grep` finds no `.shared` in app code except the Carbon callback's `HotKeyCenter` reach, which is documented.
- Dogfood: rebinding a shortcut re-registers at once, template selection changes export, microphone change reaches the recorder, login item toggles and rolls back on failure.

Done when: one composition root, typed stores, no callbacks.

## Phase 6: Optional polish

Do only after phases 0 through 5 are stable. Stop at any point.

- Move pure provenance parsing into the domain module. Keep AX, AppleScript, and kitty adapters in the app.
- Typed rejections from the domain plus one app-side message mapper. Remove the duplicate validation in `StackUI`.
- Convert every test to Swift Testing in one mechanical batch, or leave all of them on XCTest. Two test frameworks in one repo is the one outcome to avoid.
- Split `PaletteWorkflow` only if it keeps growing.
- Replace the `OverlayScrollers` polling and the view-level focus `DispatchQueue.main.async` calls with owner-level first responder handling.

## Keep, rewrite, delete

Port as-is with renames only:

- `SelectionCapture` AX classification and pasteboard fallback, `AutomaticSelectionTracker`, `VoiceAnnotationService` and `LocalVoiceTranscriber`, panel recipes, `HotKeyCenter` and `KeyCombo`, all of `Provenance/`, `StackStore`, `StorePersistence`, `StackDocumentMutations`, `PromptComposer`, `TemplateCollection`, `NoteListing`, `TextNormalization`, `NoteCreation`, `ExportState` and `ExportController`, `StackSwitchMachine`, `StatusMenuModel`, `HotKeyRegistrar`, `Diag`, `PermissionState`, `Main`, build and release scripts, `web/`.

Rewrite in place:

- `AppDelegate` into an adapter.
- `AppSettings` into typed stores plus a smaller remainder.
- `CaptureController` wiring and `CaptureWindows` into surfaces.
- `StackPaletteModel` to state and projection only, effects executed by its controller.
- `StackSwitcherController` glue to injected panel factory and center.
- `SelectionCapture` static entry point to an injectable type.
- Settings and setup views to environment injection.

Delete:

- `AppSettings.shared` and the three callbacks.
- `VoiceTriggerMachine` and the voice callback bus.
- `.shared` reach-ins in services and panels.
- `hideAuxiliaryWindows`.
- The document's custom `init(from:)`.
- Compatibility comments and the old-key narration.

## Verification and dogfooding

Per batch:

1. `swift test` green.
2. `./build.sh debug` succeeds and signs.
3. Forced rebuild with zero warnings.
4. Diff review before the commit.

Per phase:

1. `docs/dogfood.md` checklist passes on one build: voice hold, voice tap, escape, typed note in an Electron app, standalone thought, paste export with clear, copy export preserving the clipboard, stack cycling with arrows and release, palette rename and delete and undo, template edit and save as new, microphone switch, login item toggle, `tccutil reset` and re-grant.
2. Diag excerpts recorded for anything platform-facing.

`docs/dogfood.md` is written in Phase 1 so every later phase has it.

## Batch conventions

- A batch is one reviewable change with tests.
- One commit per batch, plain message, no em dashes.
- No behavior change without a test or a listed manual check.
- Moving platform code keeps the call order byte for byte. Only the caller changes.
- If a batch fails verification twice, stop and report instead of layering fixes.

## Risks

- Window state ends up in four places. `SurfaceCoordinator` is the only owner of applied visibility and ordering.
- Hot-path presentation changes silently. The coordinator validates transitions; it does not re-derive the ordering calls.
- FluidAudio may resist Swift 6 mode. Use `@preconcurrency import` if needed.
- The settings split is the largest view churn. Do it as one cutover, not incrementally.
- The rename touches every file. It goes first, alone, so nothing else is in the same diff.

## Effort

| Phase | Batches |
|---|---|
| 0 Safety | 1 |
| 1 Compiler floor and dogfood doc | 1 |
| 2 Vocabulary | 1 |
| 3 Capture consolidation | 3 |
| 4 Surfaces | 2 |
| 5 Settings | 2 |
| 6 Optional polish | 1 or more |

Phases 0 through 5 are about ten batches. After phase 5 the returns flatten.
