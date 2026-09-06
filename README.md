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

Every note records the app and window title. Some apps give more:

- **Browsers** add the page URL: Safari, Chrome, Chromium, Arc, Brave, Edge, Vivaldi, Helium.
- **Editors** add the open file: VS Code, VSCodium, Cursor, Windsurf, Antigravity, T3 Code, Trae, Zed.
- **Terminals** add the working directory: Ghostty, kitty, Terminal.

## Templates

A template is the preamble plus which metadata to include. Three are built in: **Plain** (default), **Coherent**, **Point by Point**. Edit them or add your own.

## Privacy

Everything stays on this Mac. The microphone is open only while recording. Transcription is local (Parakeet v3, Core ML). No analytics. The only network request is the one-time model download.

```
~/Library/Application Support/Sendpoint/store.json                       notes
~/Library/Application Support/Sendpoint/debug.log                        log
~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3     voice model
~/Library/Preferences/app.sendpoint.plist                                settings
```

## Install

Apple Silicon, macOS 14 or later. Download from [sendpoint.app/download](https://sendpoint.app/download), move to Applications, and grant Accessibility, Microphone, and the 460 MB voice model when asked.

## Uninstall

```sh
rm -rf /Applications/Sendpoint.app
rm -rf ~/Library/Application\ Support/Sendpoint
rm -rf ~/Library/Application\ Support/FluidAudio/Models/parakeet-tdt-0.6b-v3
defaults delete app.sendpoint
```

## Development

```sh
swift test                  # tests
./build.sh                  # debug app bundle
./install.sh                # replace the installed app and launch it
./release.sh 1.4 --publish  # notarize, zip, publish on GitHub
```

See [AGENTS.md](AGENTS.md) for engineering guidelines. Speech to text is [FluidAudio](https://github.com/FluidInference/FluidAudio).

## License

[MIT](LICENSE).
