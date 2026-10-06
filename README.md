# Sendpoint

Sendpoint is a Mac app for thinking out loud while you read, then handing those thoughts to a model as one prompt.

Select a passage, hold a key, and talk about it: what you think it means, what confuses you, where you disagree. Release the key and the note is saved with the passage it came from. Keep reading. When you're done, one shortcut pastes everything as Markdown into whatever chat box is in front: Gemini, ChatGPT, Claude Code, OpenCode.

It's useful for two things.

**Learning.** Putting your understanding into your own words while you read makes it stick, and it makes you read more carefully. The model also gets a record of how you reasoned, so it can tell you where you're right, show where your reasoning went wrong, and fill your specific gaps instead of explaining from scratch.

**Steering an agent.** A coding agent hands you a long response. Instead of replying with one vague message, go through it, select the parts that matter and react to each one: agree, question, object, change this. Paste that back. It usually takes two or three rounds until you and the agent agree, and then it acts.

You don't have to select anything. A note can also be a standalone thought, which is useful for thinking out loud before you start a task.

Free. Apple Silicon, macOS 14 or later. [Download](https://sendpoint.app/download).

## Shortcuts

All of these can be changed in Settings.

|                   |                                              |
| ----------------- | -------------------------------------------- |
| <kbd>⌘E</kbd>     | Voice note                                   |
| <kbd>⌘G</kbd>     | Typed note, for when you can't talk out loud |
| <kbd>⌃⌘E</kbd>    | Edit the latest note                         |
| <kbd>⌃⌘V</kbd>    | Export the current stack                     |
| <kbd>⌃⌘S</kbd>    | Show the stack                               |
| <kbd>⌥H</kbd> <kbd>⌥J</kbd> <kbd>⌥K</kbd> <kbd>⌥L</kbd> <kbd>⌥;</kbd> | Switch to stack 1, 2, 3, 4 or 5 |
| <kbd>⌃⌘⌫</kbd>    | Clear the stack                              |
| <kbd>⌥Space</kbd> | Dictate                                      |

Voice notes default to Hold mode: hold to talk, release to save. In Tap mode you press once to start and again to save. <kbd>⎋</kbd> cancels either way. While you talk, a small capsule shows the live transcript, and focus stays in the app you're reading.

Dictation is a side feature: hold <kbd>⌥Space</kbd>, speak, release, and the words paste at the cursor. It doesn't create a note. Clear the shortcut to turn it off.

## Stacks

Notes collect in a stack. There are always five, one per home-row key, and you never create, name or delete them. Reading two articles at once means one key to switch between them. New notes go to the current stack, and the menu bar shows its number.

Switching stacks is immediate, even while notes are saving or storage needs a retry. Sendpoint remembers the last selected slot separately from the notes file. A capture follows your selection until you save; a saved request and an existing-note edit keep their original destination.

Stacks are meant to be thrown away. Exporting empties the stack, so each round with the model starts fresh. If you clear one by mistake, Undo Clear in the menu bar brings the notes back.

In the stack viewer, highlight a note and add <kbd>⇧</kbd> to a stack key to move it there: <kbd>⌥⇧J</kbd> sends it to the end of stack 2.

## Templates

Export pastes the stack as Markdown at the cursor, or copies it to the clipboard if you prefer. A template decides what the export looks like: a preamble of instructions placed before the notes, whether to include a dated heading, note numbers and timestamps, and whether to clear the stack afterwards. Three are built in. You can edit them or add your own.

- **Plain** (default): just the notes.
- **Learn**: asks the model to check your understanding. It should confirm what you got right, show where your reasoning went off, answer in terms of the mental model you're already using, and write one connected response rather than a reply to each note.
- **Steer**: tells the model the quotes are from its own previous response and your notes are direction. It answers your questions, pushes back where it thinks you're wrong, and says what it would change, but doesn't act until you agree.

A stack exported with Learn:

```markdown
Below are notes I spoke out loud while reading. Each is either a passage I quoted followed by my reaction, or a standalone thought. They're transcribed speech, so expect loose phrasing, half-finished sentences and transcription errors.

I'm saying these to understand the material, not just to get answers. Read them as a record of how I'm thinking:
- Where I've got it right, say so briefly and move on.
- Where I'm wrong or incomplete, show exactly where my reasoning went off and what's actually true.
- Answer my questions using the mental model I'm already using, then extend it.
- Point out anything important I seem to have missed.

Write one connected response, not a reply to each note in turn. Organize it however explains it best, even if that's not the order of my notes. Restate what you're responding to so I don't have to scroll back.

# Reading notes — September 2, 2026

> When a reader begins a transaction, it records a read-mark in the shared-memory WAL index (.shm file), pointing to the last valid commit frame at that exact moment.

wait so the reader doesn't even touch or lock the main db file, it just grabs an integer index in memory and walks the log for changes before that number?

_2:14 PM_

> Checkpoint rule: SQLite cannot truncate or overwrite WAL frames beyond the oldest active reader's read-mark.

wait hang on, so if a background query hangs, does that mean writes start failing, or does the wal file just expand forever because checkpoint can't touch it?

_2:16 PM_

right, so writes still succeed, but disk usage explodes because old frames can't be recycled until every slow reader drops its read-mark

_2:17 PM_
```

## Install

Download from [sendpoint.app/download](https://sendpoint.app/download) and move it to Applications. When asked, grant Accessibility and Microphone access and allow the voice model download.

Selection works in most apps. Some terminal apps handle the mouse themselves and never expose a selection; there, record the note without one.

## Privacy

Everything stays on your Mac. The microphone is open only while you're recording. Transcription runs locally (Parakeet via Core ML). There are no analytics. Sendpoint goes online only to download the voice model once and to check for signed updates through Sparkle.

```
~/Library/Application Support/Sendpoint/slots.json                          notes
~/Library/Application Support/Sendpoint/debug.log                           log
~/Library/Application Support/FluidAudio/Models/parakeet-unified-en-0.6b    voice model
~/Library/Preferences/app.sendpoint.plist                                   settings
```

To uninstall:

```sh
rm -rf /Applications/Sendpoint.app
rm -rf ~/Library/Application\ Support/Sendpoint
rm -rf ~/Library/Application\ Support/FluidAudio/Models/parakeet-unified-en-0.6b
defaults delete app.sendpoint
```

## Development

Swift 6.2, Swift Package Manager. Speech to text uses [FluidAudio](https://github.com/FluidInference/FluidAudio). Updates use [Sparkle](https://sparkle-project.org).

```sh
./check.sh     # build and run the tests; one summary line, full log in .build/check.log
./shots.sh     # render every screen, light and dark, into .build/shots/ (--diff to compare with the last set)
./ship.sh      # build, install and launch the app
```

Releases:

```sh
./release.sh 1.12.0 --ad-hoc --publish          # Sparkle-sign, package as a DMG, publish; no paid Apple account needed
./release.sh 1.12.0 --publish                   # also Developer ID-sign and notarize
./release.sh 1.12.0 --ad-hoc --resume-publish   # finish a failed upload or deploy
```

`--ad-hoc` makes a true ad-hoc signature, not this Mac's Apple Development certificate. Other people can open these builds via Privacy & Security → Open Anyway. They disable hardened-runtime library validation so Sparkle can load without an Apple Team ID; update archives and feeds are still verified with Sparkle's signing key.

Sparkle's private signing key lives in this Mac's login Keychain. Back it up once to secure storage. Never commit the exported file, and never generate a replacement key, or existing installs will stop accepting updates:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x /secure/path/sendpoint-sparkle-private-key
```

Engineering rules and the code layout are in [AGENTS.md](AGENTS.md). Product vocabulary is in [CONTEXT.md](CONTEXT.md).

## License

[MIT](LICENSE)
