# Dogfood checklist

Run on one build after every phase. Each line is a behavior the automated
tests cannot see: a TCC prompt, a foreign app, a key held down by a person.

## Capture

- [ ] Hold the voice shortcut, speak, release. The note saves to the current stack.
- [ ] Tap mode: press once, speak, press again. Same result.
- [ ] Press Escape mid-recording. Nothing saves and the overlay closes.
- [ ] Typed note over a selection in an Electron app (VS Code or Slack). The quote is the selection.
- [ ] Typed note with nothing selected. A standalone thought saves.
- [ ] Open a typed note, then quit immediately after saving. Relaunch and confirm the note is there.
- [ ] Put the cursor in a text field in another app, hold ⌥Space, speak, release. The words paste there and no note is saved.
- [ ] Dictate with the card on. The card shows the app's name in its footer and no stack picker.
- [ ] Hold ⌥Space while a voice note is recording. It beeps and the note keeps recording.
- [ ] Press ⌥Space with Sendpoint's Settings in front. Nothing happens.
- [ ] Clear the Dictate shortcut in Settings. The status menu loses its Dictate item.

## Export

- [ ] Paste export with "clear after export" on. The markdown lands in the front app and the stack empties.
- [ ] Copy export with a full clipboard. The markdown replaces it and nothing else changes.
- [ ] Undo Clear from the status menu restores the batch.

## Stacks

- [ ] Press each stack shortcut with nothing open. The readout names the stack and its note count, then leaves; the menu bar number follows.
- [ ] Press the current stack's shortcut. The readout shows and nothing else changes.
- [ ] Press a stack shortcut with the viewer open. No readout; the header and the notes change to that stack.
- [ ] Press a stack shortcut while editing a note in the viewer. The edit saves to the stack it began in, then the viewer shows the new stack.
- [ ] Press a stack shortcut while recording a voice note. The capsule's destination follows and the note lands there.
- [ ] Show Stack opens at the bottom of the current stack's notes, last note highlighted.
- [ ] In the viewer: click a numeral or press ⌘1–⌘5 to switch; clear the stack and undo it.
- [ ] Launch over a version 3 store. The five most recent stacks arrive with their notes and `store.v3.json` sits beside `store.json`.

## Templates

- [ ] Edit a template's preamble and save. The next export uses it.
- [ ] Save as new. The original is untouched and the clone is active.
- [ ] Close the editor with unsaved changes. The dialog offers Save, Discard, Cancel.

## Settings and permissions

- [ ] Change the microphone. The next recording uses it.
- [ ] Rebind a shortcut. It works at once without relaunch.
- [ ] Toggle Launch at Login on and off. System Settings agrees.
- [ ] `tccutil reset Accessibility app.sendpoint`, relaunch, re-grant. Capture works again.
- [ ] Launch a second copy. It exits and the first shows Settings.
- [ ] Open Sendpoint from Raycast or the Dock. Settings appears. A login launch does not.
