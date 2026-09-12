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

## Export

- [ ] Paste export with "clear after export" on. The markdown lands in the front app and the stack empties.
- [ ] Copy export with a full clipboard. The markdown replaces it and nothing else changes.
- [ ] Undo Clear from the status menu restores the batch.

## Stacks

- [ ] Hold the switch shortcut, cycle with repeated presses, release. The lit stack becomes current.
- [ ] Hold the switch shortcut, press Up or Down. The palette opens on the lit stack, sidebar focused, notes on the right.
- [ ] In the palette: Tab moves focus between the stack list and the notes; the unfocused pane dims its highlight.
- [ ] Show Stack opens at the bottom of the newest stack's notes, last note highlighted.
- [ ] In the palette: rename, delete with confirmation, undo a clear.
- [ ] Only one stack: the switch shortcut beeps.

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
