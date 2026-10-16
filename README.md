# Sendpoint

A tiny macOS menu bar app for annotating what you read.

1. Select text anywhere.
2. **⌘G** to type a note on it, or **hold ⌘E** and talk; letting go saves the note. With `mode = "tap"` under `[voice]` in the config, tap ⌘E to start and tap again to save.
3. **↩** saves the note to the current stack. **⇧↩** adds a new line, **esc** cancels.
4. **⌥H ⌥J ⌥K ⌥L** switch between four stacks.
5. **⌃⌘S** opens the current stack as a Markdown file in your editor.
6. **⌃⌘V** pastes the current stack as Markdown into the front app and clears it.

Shortcuts, stack names and the note card's size and opacity live in `~/.config/sendpoint/config.toml`, written with commented defaults on first launch. Changes apply when you save the file; mistakes show up in the menu bar menu.

Speech runs on-device with Apple's SpeechAnalyzer (macOS 26+). Sendpoint needs Accessibility (to read selections and paste) and Microphone.

```sh
./check.sh     # build + tests
./install.sh   # build, install to /Applications, launch
```
