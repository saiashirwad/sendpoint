# Engineering rules

- Use Swift Observation for app-owned state. Do not add `ObservableObject`, `@Published`, or TCA.
- Model finite workflows with closed enums, one event transition function, and one idempotent teardown path.
- Keep data transformations pure and outside views.
- Give each lifecycle task one owner. Retain and cancel its handle; do not use `Task.detached` for lifecycle work.
- Check cancellation around external calls. Apply a result only when its full context still matches the current state.
- Inject small system boundaries for deterministic tests. Test behavior, including cancellation, stale results, invalid transitions, and teardown.
- Make clean cutovers. Delete obsolete callers, state, settings, imports, and files.
- GitHub Actions `Verify` is the authoritative automated acceptance gate: require `behavior`, `screenshots`, and `packaging` for the reviewed revision. Review logs, JSON results, and light/dark PNG artifacts; see `docs/verification.md`. Do not claim remote success before the run completes.
- CI reuses `./check.sh` for builds/tests and `./shots.sh` for fresh rendering without baseline comparison. A new screen or state gets a case in `Tests/SendpointScreenshotTests/ScreenshotTests.swift`. Snapshots are not full-app end-to-end coverage.
- Local builds, tests, screenshots, installation, and launch are optional, explicitly requested developer diagnostics or manual acceptance—not mandatory completion steps. Do not run `./install.sh` or `./ship.sh` on the developer host without explicit approval. Real microphone, Accessibility/selection, pasted export, downloaded-model transcription, and updater acceptance remain manual; CI ad-hoc packaging is not notarization.
- Publish only with `./release.sh X.Y.Z --ad-hoc --publish`.
- Before adding a setting, a shortcut, or a state machine, read its guide first: `.claude/skills/add-setting/SKILL.md`, `.claude/skills/add-shortcut/SKILL.md`, or `.claude/skills/add-state-machine/SKILL.md`.

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
