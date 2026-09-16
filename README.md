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
| <kbd>⌘U</kbd>  | Switch stack                                 |
| <kbd>⌃⌘⌫</kbd> | Clear stack                                  |

Switching works like <kbd>⌘⇥</kbd>. Tap <kbd>⌘U</kbd> to go back to the stack you used last. Keep <kbd>⌘</kbd> held and tap <kbd>U</kbd> again to keep cycling, <kbd>⌘⇧U</kbd> goes backwards, and letting go picks the lit stack. Press <kbd>↑</kbd> or <kbd>↓</kbd> while holding to open the full list instead. Next and previous stack keys exist too, unbound until you set them in Settings.

Voice notes work two ways, set in Settings. **Hold** is the default: hold to speak, release to save. **Tap** presses once to start and again to save. <kbd>⎋</kbd> cancels either way.

Export pastes at your cursor by default, so it lands straight in the chat box. Turn that off and it copies to the clipboard instead.

## What a stack exports as

With the Coherent template:

```markdown
These are my reading notes, captured in order while I read. Each entry is either a response to a quoted passage or a standalone thought. Read the notes as a whole and give me one coherent response that takes all of them into account. Restate enough context to make each part of your response understandable without requiring me to scroll back. Do not respond point by point unless the notes ask you to.

# Reading notes — September 2, 2026

## 1

> When a reader begins a transaction, it records a read-mark in the shared-memory WAL index (.shm file), pointing to the last valid commit frame at that exact moment.

wait so the reader doesn't even touch or lock the main db file, it just grabs an integer index in memory and walks the log for changes before that number?

_2:14 PM_

## 2

> Checkpoint rule: SQLite cannot truncate or overwrite WAL frames beyond the oldest active reader's read-mark.

wait hang on, so if a background query hangs, does that mean writes start failing, or does the wal file just expand forever because checkpoint can't touch it?

_2:16 PM_

## 3

right, so writes still succeed, but disk usage explodes because old frames can't be recycled until every slow reader drops its read-mark

_2:17 PM_
```

## Templates

A template is the preamble plus the note formatting options. Three are built in: **Plain** (default), **Coherent**, and **Point by Point**. Edit them or add your own.

## Privacy

Everything stays on this Mac. The microphone is open only while recording. Transcription is local (Parakeet Unified, Core ML). No analytics. Network access is limited to the one-time voice-model download and Sparkle's signed update checks.

```
~/Library/Application Support/Sendpoint/store.json                       notes
~/Library/Application Support/Sendpoint/debug.log                        log
~/Library/Application Support/FluidAudio/Models/parakeet-unified-en-0.6b     voice model
~/Library/Preferences/app.sendpoint.plist                                settings
```

## Install

Apple Silicon, macOS 14 or later. Download from [sendpoint.app/download](https://sendpoint.app/download), move to Applications, and grant Accessibility, Microphone, and the on-device voice model when asked.

## Uninstall

```sh
rm -rf /Applications/Sendpoint.app
rm -rf ~/Library/Application\ Support/Sendpoint
rm -rf ~/Library/Application\ Support/FluidAudio/Models/parakeet-unified-en-0.6b
defaults delete app.sendpoint
```

## Development

```sh
swift test                  # tests
./build.sh                  # debug app bundle
./install.sh                # replace the installed app and launch it
./release.sh 1.6 --ad-hoc --publish  # Sparkle-sign, package as DMG, publish; no paid Apple account
./release.sh 1.6 --publish           # also Developer ID-sign and notarize
./release.sh 1.6 --ad-hoc --resume-publish  # finish a failed upload/deploy
```

`--ad-hoc` is a true ad-hoc signature, not this Mac's Apple Development
certificate. Other people can open it via Privacy & Security → Open Anyway.
Those builds disable hardened-runtime library validation so Sparkle can load
without an Apple Team ID. Published update archives and feeds are still
verified with Sparkle's signing key.

Sparkle's private update-signing key lives in this Mac's login Keychain. Back it up once to secure storage; never commit the exported file or generate a replacement:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x /secure/path/sendpoint-sparkle-private-key
```

See [AGENTS.md](AGENTS.md) for engineering guidelines. Speech to text is [FluidAudio](https://github.com/FluidInference/FluidAudio).

## License

[MIT](LICENSE).
