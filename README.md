# Sendpoint

A macOS menu bar app for making voice notes while you read.

Select a passage in any app, hold Command–backtick, and say what you are thinking:
what you don't follow, what seems off, or what you want checked. Hold the
shortcut while you talk and release it to save to the stack. For hands-free
recording, choose Tap mode in Settings: press once to start and again to save. Keep reading. Each note is stamped with where you were. When
you reach the end, one shortcut turns the whole train of thought into a prompt
and pastes it into whatever model you're talking to, so it answers your
reasoning and not just your question.

For a typed note, press `⌃⌘A` to capture the selection and open the note box.
Voice notes and typed notes both require Accessibility. Voice notes also need
Microphone access and the local voice model. The model downloads
on first voice use or when you choose to set it up explicitly.

It works on anything you can select: LLM output, docs, papers, code, or a draft
of your own.

Requires macOS 14 or later on Apple Silicon.

## Install

Download the latest zip from [Releases](../../releases), unzip it, and drag
**Sendpoint** into `/Applications`. Open it and look for the
speech-bubble icon in the menu bar.

The current builds are ad-hoc signed and are not notarized by Apple. On the
first launch, macOS may block the app. Try to open it once, then open **System
Settings > Privacy & Security**, scroll to **Security**, click **Open Anyway**,
and confirm **Open**. Only do this if you trust this repository.

The setup assistant asks for:

- **Accessibility.** Required. It reads your selection and sends the paste
  keystroke.
- **Microphone and a voice model.** Required for voice notes. The local model
  downloads on first voice use or during explicit setup. It is a one-time
  460 MB download. Transcription runs on your Mac and audio never leaves it.

The first time you capture from a browser, macOS asks whether the app may
control it. Allowing it lets notes record the tab's title and URL.

## Shortcuts

| Key      | Action                                                            |
| -------- | ----------------------------------------------------------------- |
| Command–backtick | Voice note: hold to talk and release to save to the stack |
| `⌃⌘A`    | Typed note: capture the selection and open the note box           |
| `⌘↩`     | Save the typed note and close the box                             |
| `⎋`      | Discard the typed note                                            |
| `⌃⌘V`    | Paste the stack as Markdown into the current app                  |
| `⌃⌘S`    | Open the stack palette inside the current stack                   |
| `⌃⌘K`    | Open the stack palette at the list of stacks                      |
| `⌃⌘⌫`    | Clear the current session                                         |
| `⌘Z`     | Undo the last clear in the stack palette                          |

All six global shortcuts, including voice, are rebindable in Settings. Voice
uses Hold mode by default; Settings → Voice offers an explicit Hold / Tap
choice. In either mode, Escape discards the recording. Choosing Voice Note
from the menu starts recording; choose it again or press the voice shortcut
to finish and save. The typed note save and discard keys belong to the note
box; `⌘Z` belongs to the stack palette.

Inside the palette: `↑↓` move, `↩` switch, `→` opens a stack's notes and `←`
comes back, `⌘1`–`⌘9` jump, `⌘K` lists every action, `⌘P` picks the copy
template, `⌘C` copies, `⌘R` renames, `⌘N` makes a stack, `⌘⌫` deletes,
`⇧⌘⌫` clears. On a note, `↩` edits it and `⌥↑`/`⌥↓` reorder it.

## Development

Use Swift Package Manager from the terminal; no Xcode project is needed:

```sh
swift test                     # Debug build and tests
./build.sh                     # Debug app bundle, locally signed
./install.sh                   # Replace the installed app and launch it
./build.sh release             # Optimized app bundle for performance checks
```

`build.sh` defaults to `debug`, which skips release optimization and the signing
server timestamp. It still packages the app's permission descriptions and signs
with the available certificate so development uses the same app identity. Both
configurations produce `dist/Sendpoint.app`; `install.sh` stops the old copy
before starting the new one. Use that bundle for microphone and permission
checks rather than launching the bare executable with `swift run`.

SwiftPM keeps separate debug and release caches in `.build`. Leave them in place
between edits. The first build of either configuration compiles its dependencies
and takes longer. Use release builds to judge transcription speed; debug code
runs without optimization. `release.sh` always selects the release configuration
and retains the signing timestamp needed for notarization.
