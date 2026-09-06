# Sendpoint

Think out loud while you read.

You have the thought mid-paragraph, and by the time you have scrolled back, opened the chat box and typed enough context for it to make sense, the thought is gone. Sendpoint is a Mac app that lets you say it where it happened, keep reading, and send the whole train of thought later as one prompt.

Free. For Apple Silicon Macs on macOS 14 or later.

## How it works

1. Select the passage that raised the thought.
2. Hold <kbd>⌘\`</kbd> and say it. Release to save.
3. Press <kbd>⌃⌘V</kbd> to send the whole stack as one prompt.

The note and the passage it came from are kept together in a stack. Nothing interrupts you: the overlay is a small capsule, and focus returns to whatever you were reading.

The default shortcuts, all changeable in Settings:

|                |                                              |
| -------------- | -------------------------------------------- |
| <kbd>⌘\`</kbd> | Voice note                                   |
| <kbd>⌃⌘A</kbd> | Typed note, for when you can't talk out loud |
| <kbd>⌃⌘V</kbd> | Export stack as Markdown                     |
| <kbd>⌃⌘S</kbd> | Show stack                                   |
| <kbd>⌃⌘K</kbd> | Switch stack                                 |
| <kbd>⌃⌘⌫</kbd> | Clear stack                                  |

Voice notes work two ways, set in Settings. **Hold** is the default: hold to speak, release to save. **Tap** presses once to start and again to save. <kbd>⎋</kbd> cancels either way.

Export pastes at your cursor by default, so it lands straight in the chat box. Turn that off and it copies to the clipboard instead.

## What a stack exports as

With the Coherent template:

```markdown
These are my reading notes, captured in order while I read. Each entry is either a response to a quoted passage or a standalone thought. Read the notes as a whole and give me one coherent response that takes all of them into account. Restate enough context to make each part of your response understandable without requiring me to scroll back. Do not respond point by point unless the notes ask you to.

# Reading notes — September 2, 2026

## 1

> Because the closure captures the environment at definition time, a CEK machine never substitutes. It extends the environment instead.

wait, doesn't the environment grow forever then? when does anything get pruned

_Helium · Closures in CEK Machines · https://chatgpt.com/c/68b6f2a4 · 2:14 PM_

## 2

actually I think I get it. environment is data, continuation is control

_Ghostty · sendpoint — fish · ~/code/sendpoint · 2:17 PM_
```

## Where notes come from

Each note records the app it was taken in, the window or tab title, and a link when the app can give one. Sendpoint asks the frontmost app directly; the first time it asks a browser or terminal, macOS shows the Automation prompt for that app.

- **Browsers — page URL and tab title.** Safari, Safari Technology Preview, Chrome (including Beta, Dev and Canary), Chromium, Arc, Brave, Edge, Vivaldi, Helium.
- **Editors — the file you have open.** VS Code (including Insiders, Exploration and OSS builds), VSCodium, Cursor, Windsurf, Antigravity, T3 Code, Trae, Zed.
- **Terminals — the working directory.** Ghostty, kitty, Terminal.

Everywhere else, a note still records the app and its window title.

## Templates

A template decides what the export looks like: the preamble at the top, and whether to include the app, the window title, the link, timestamps and the date heading. Three come built in.

- **Plain** — the notes and the quotes, nothing else. The default.
- **Coherent** — asks for one answer that takes all the notes together.
- **Point by Point** — asks for each note addressed separately.

You can edit these and add your own.

## Privacy

Selected text, notes, audio, transcription, and voice-model work stay on this Mac.

The microphone is only open while a voice note is being recorded. Transcription runs locally on Parakeet v3 through Core ML. There are no analytics, and the app makes no network requests of its own — the one download is the voice model, fetched once from Hugging Face when you ask for it during setup.

Everything Sendpoint writes:

```
~/Library/Application Support/Sendpoint/store.json    your stacks and notes
~/Library/Application Support/Sendpoint/debug.log     a local log, rotated at ~2 MB
~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3    the voice model
~/Library/Preferences/app.sendpoint.plist             shortcuts, templates, settings
```

## Requirements

An Apple Silicon Mac running macOS 14 or later.

## Install

Download from [sendpoint.app/download](https://sendpoint.app/download), unzip, and move Sendpoint to your Applications folder. On first launch it walks you through three things:

- **Accessibility** — reads the text you select. Granted by hand in System Settings → Privacy & Security → Accessibility.
- **Microphone** — listens only while a voice note is open.
- **Local voice model** — Parakeet v3, a one-time 460 MB download.

## Uninstall

Turn off "Launch at login" in Settings first, then delete:

```sh
rm -rf /Applications/Sendpoint.app
rm -rf ~/Library/Application\ Support/Sendpoint
rm -rf ~/Library/Application\ Support/FluidAudio/Models/parakeet-tdt-0.6b-v3
defaults delete app.sendpoint
```

The FluidAudio directory may hold models other apps put there, so remove the one folder rather than the whole thing.

## Development

Swift Package Manager from the terminal; no Xcode project is needed.

```sh
swift test                     # Debug build and tests
./build.sh                     # Debug app bundle, locally signed
./install.sh                   # Replace the installed app and launch it
./build.sh release             # Optimized app bundle for performance checks
./release.sh 1.4               # Build, notarize, staple and zip a release
./release.sh 1.4 --publish     # ...then publish it on GitHub
```

`./release.sh VERSION --ad-hoc` builds without an Apple account. See the notes at the top of the script for the one-time notarization setup.

[AGENTS.md](AGENTS.md) has the engineering guidelines this codebase follows — state, concurrency, and where the system boundaries are.

Speech to text is [FluidAudio](https://github.com/FluidInference/FluidAudio) running Parakeet TDT v3.

## License

[MIT](LICENSE).
