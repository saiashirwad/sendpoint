# Sendpoint

Select text in any app, annotate it by typing or speaking, collect notes in one of four stacks, paste a stack as Markdown. Nothing else.

## How it works

- All behavior lives in `step(&world, event) -> [Effect]` in `Sources/Core/World.swift`. It is pure (Foundation only) and the only place decisions are made.
- `Sources/App/main.swift` is the loop: a key or callback sends an `Event`, `step` updates `world`, `render()` redraws from `world`, and `perform` carries out each `Effect`.
- The App files only translate: `Keys` (Carbon hotkeys), `Selection` (Accessibility read, ⌘C fallback, ⌘V paste), `Speech` (mic + SpeechAnalyzer + level meter), `Panel` (the note card), `StatusMenu`.
- Speech results carry their `take`. `step` drops any result whose take doesn't match, so old or cancelled recordings can't land.
- Notes persist to `~/Library/Application Support/Sendpoint/notes.json` (`Saved`), written off the main thread. Every save also mirrors each stack to `stack-N.md` next to it; the `open` shortcut opens that file in the user's editor. There is no stack viewer.
- Settings are `~/.config/sendpoint/config.toml` (or `$XDG_CONFIG_HOME`), a small TOML subset parsed by `parseConfig` in `Sources/Core/Config.swift` into `world.config`. `main.swift` polls its mtime once a second and sends `.configure`; a change to the keys yields `.bindKeys`. The file is written from `defaultConfigText` when missing.

## Rules

- New behavior is a new `Event` or `Effect` case, a `step` branch, and a test in `Tests/CoreTests/StepTests.swift`. Views never decide; they `send`.
- Keep the hot path synchronous: hotkey → read selection → `send`. Build windows and load models at launch, never on a keypress.
- No SwiftUI, no macros, no dependencies. Code that is slow to type-check gets a compiler warning (see `Package.swift`); fix it.
- Main thread everywhere (`defaultIsolation(MainActor)`). Only `Tap` in `Speech.swift` runs on the audio thread.
- Shortcuts and card look come from the config file only. A new setting is a `Config` field, a `parseConfig` case, a line in `defaultConfigText`, and a test (`defaultConfigFileParsesToTheBuiltInDefaults` keeps the file and defaults in step).

## Commands

- `./check.sh`: build and run Core tests.
- `./build.sh`: assemble and sign `dist/Sendpoint.app`.
- `./install.sh`: build, install to /Applications, relaunch. Run it only when asked.
