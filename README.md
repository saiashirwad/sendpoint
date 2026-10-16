# Sendpoint

A tiny macOS menu bar app for annotating what you read.

1. Select text anywhere.
2. **⌘G** to type a note on it, or **hold ⌘E** to speak one (tap ⌘E to keep listening until the next press).
3. **↩** saves the note to the current stack. **⇧↩** adds a new line, **esc** cancels.
4. **⌥1–⌥4** switch between four stacks.
5. **⌃⌘V** pastes the current stack as Markdown into the front app and clears it.

Speech runs on-device with Apple's SpeechAnalyzer (macOS 26+). Sendpoint needs Accessibility (to read selections and paste) and Microphone.

```sh
./check.sh     # build + tests
./install.sh   # build, install to /Applications, launch
```
