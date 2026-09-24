# Engineering rules

- Use Swift Observation for app-owned state. Do not add `ObservableObject`, `@Published`, or TCA.
- Model finite workflows with closed enums, one event transition function, and one idempotent teardown path.
- Keep data transformations pure and outside views.
- Give each lifecycle task one owner. Retain and cancel its handle; do not use `Task.detached` for lifecycle work.
- Check cancellation around external calls. Apply a result only when its full context still matches the current state.
- Inject small system boundaries for deterministic tests. Test behavior, including cancellation, stale results, invalid transitions, and teardown.
- Make clean cutovers. Delete obsolete callers, state, settings, imports, and files.
- Verify with `./check.sh` (builds and tests; prints one summary line plus any errors; full log in `.build/check.log`).
- Finish every requested change with `./ship.sh` (build, assemble, install, launch; full log in `.build/ship.log`) before reporting it done.
- Publish only with `./release.sh X.Y.Z --ad-hoc --publish`.
- Before adding a setting, a shortcut, or a state machine, load the `add-setting`, `add-shortcut`, or `add-state-machine` skill.

# Folder map

- `Sources/SendpointDomain`: pure types, Foundation only (no AppKit). Models (`Subject`, `Note`, `Stack`, `StackDocument`), `StackStore` (observable queue), `StorePersistence` (`store.json`), templates, `PromptComposer` (Markdown), and every pure machine.
- `Sources/Sendpoint/<Area>`: controllers, windows, and SwiftUI. Areas: `App` (lifecycle, `AppDelegate+*`, `AppEnvironment`, menu bar), `Capture`, `Input` (shortcuts), `Palette`, `StackSwitcher` (app-wide switcher, not the palette's), `Platform` (export, permissions), `Settings` (settings, setup, templates), `SharedUI` (`Theme`, `Controls`), `Voice`.
- `Tests/SendpointDomainTests`: pure transitions. `Tests/SendpointTests`: controllers.

Machine (SendpointDomain) → controller (app):

| Machine | Controller |
|---|---|
| `CaptureState` | `CaptureController` (the shape to copy) |
| `VoiceMachine` | `VoiceNoteService` |
| `StackSelectMachine` | `StackSelector` |
| `PaletteWorkflow` (`PaletteUpdate.update`) | `StackPaletteController` |
| `PermissionState` | `PermissionController` |
| `LatestNoteState` | `LatestNoteEditor` |
| `TemplateEditorState` | `TemplateEditorController` |
| `SurfaceState` | `SurfaceCoordinator` |
| `AutomaticSelectionTracker` | `AutomaticSelectionMonitor` |
| `ExportState` | `ExportController` (same file) |

Settings stores: `AppSettings` (general), `VoiceSettings` (voice and preview), `TemplateSettings` (templates). Views send events; they never assign properties or touch UserDefaults.
