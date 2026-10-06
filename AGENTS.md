# Engineering rules

- Use Swift Observation for app-owned state. Do not add `ObservableObject`, `@Published`, or TCA.
- Model finite workflows with closed enums, one event transition function, and one idempotent teardown path.
- Keep data transformations pure and outside views.
- Give each lifecycle task one owner. Retain and cancel its handle; do not use `Task.detached` for lifecycle work.
- Check cancellation around external calls. Apply a result only when its full context still matches the current state.
- Inject small system boundaries for deterministic tests. Test behavior, including cancellation, stale results, invalid transitions, and teardown.
- Make clean cutovers. Delete obsolete callers, state, settings, imports, and files.
- Verify with `./check.sh` (builds and tests; prints one summary line plus any errors; full log in `.build/check.log`).
- See UI with `./shots.sh --filter testName --appearance light` while iterating: it renders one `ScreenshotTests` method into `.build/shots/`. Each `sendpoint.<slug>-<appearance>.png` has a `.txt` beside it with the on-screen text and its `x,y` position. Read the `.txt`. Open a PNG only when color or shape is the question. Find a slug's test with `grep -n '"<slug>' Tests/SendpointScreenshotTests/ScreenshotTests.swift`.
- Before reporting UI work done, run `./shots.sh --diff`. It fails on each screen whose pixels or text changed. `summary` in `.build/shots.json` lists `mismatches` and `text_diffs`; read those, not the stages. An empty text diff means only color or layout changed. Run plain `./shots.sh` to accept the new set. A new screen or state gets a case in `Tests/SendpointScreenshotTests/ScreenshotTests.swift`.
- Hand UI verification to the `ui-verify` agent when one is available, so screen output stays out of your context.
- Finish every change under `Sources/` or `Resources/` with `./ship.sh` (build, assemble, install, launch; full log in `.build/ship.log`) before reporting it done. Website changes under `web/` skip it.
- Publish only with `./release.sh X.Y.Z --ad-hoc --publish`.
- Before adding a setting, a shortcut, or a state machine, read its guide first: `.claude/skills/add-setting/SKILL.md`, `.claude/skills/add-shortcut/SKILL.md`, or `.claude/skills/add-state-machine/SKILL.md`.

# Folder map

- `Sources/SendpointDomain`: pure types, Foundation only (no AppKit). Models (`Subject`, `Note`, `StackSlot`, `Stack`, `StackDocument`), `StackStore` (observable queue), `StorePersistence` (`slots.json`), templates, `PromptComposer` (Markdown), and every pure machine. Slots one through five are permanent; the document stores five named note arrays. Decode validates incoming notes once; trusted mutations preserve validity. Disk format version belongs to the persistence envelope, not the operational document. Old `store.json` files are left untouched and are not imported.
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
| `TemplateWorkspace` | `TemplateSettings` |
| `SurfaceState` | `SurfaceCoordinator` |
| `AutomaticSelectionTracker` | `AutomaticSelectionMonitor` |
| `ExportState` | `ExportController` (same file) |

Settings stores: `AppSettings` (general), `VoiceSettings` (voice and preview), `TemplateSettings` (templates). Views send events; they never assign properties or touch UserDefaults.
