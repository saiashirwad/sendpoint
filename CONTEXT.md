# Sendpoint

Sendpoint collects thoughts where they arise during reading, then hands them off together as a prompt. This glossary describes the current product, not a proposed redesign.

## Reading notes

**Note**: A thought paired with either a quoted passage or no passage, with its capture time. Voice and typing are ways to produce a note, not different kinds of saved note.
_Avoid_: Clip, annotation, recording (when referring to a saved note)

**Subject**: What a note responds to: a selected passage or a standalone thought.

**Quote**: The selected passage preserved with a note. It is context for the thought, not the thought itself.
_Avoid_: Selection (when referring to the preserved passage)

**Stack**: One of five permanent, numbered places to collect notes for a later handoff. A stack is not a named project or an archive.
_Avoid_: Notebook, workspace, folder

**Current stack**: The stack selected for viewing and new notes. During a capture, selecting another stack changes the note's destination until saving begins.
_Avoid_: Active stack, shown stack (as separate product concepts)

**Destination**: The stack a note will be saved to. An existing-note edit belongs to the original note even if the current stack changes.

**Stack slot**: One of five permanent destinations, represented by `StackSlot.one` through `.five`. A slot is its identity and number; only notes have UUID identities. `slots.json` stores the five note arrays and last cleared batch in a versioned disk envelope. Incompatible old `store.json` data remains untouched; there is no migration or import path.

**Current stack**: `StackStore.currentStackID` is the single immediate selection. Selection is not a note mutation and never waits for disk. `AppSettings` remembers the last selected slot as a preference read at bootstrap, not a second live selection. Note mutations remain serial and publish only after atomic commit. A completed move follows its destination only when no newer selection has occurred; failed moves retain their operation and can later report success on retry.

**Ownership choice**: Keep selection and the durable queue behind the existing `StackStore` façade, with separate writable state and a small preference callback. A separate observable selection owner would add a dependency and lifetime to every store consumer without removing more facts. `StackDocument` owns only note content and clear undo; `StackSelectMachine` owns only readout timing. Views and controllers call `store.select(slot)` for navigation and `store.mutate(...)` for durable note changes.

**Deferred palette commands**: A command requested while a draft saves runs after that save only if navigation has not superseded it. Local stack selection or an observed external selection discards the pending command, including an away-and-back sequence. The draft still saves to its original slot. A pending window close and committed-operation feedback remain valid across navigation. A deferred clear or export never silently retargets to a newer selection.

**Cleared batch**: The most recently removed group of notes, retained for Undo Clear. It belongs to its original stack.

## Capture and dictation

**Capture**: An interaction that creates a note from a thought and, when available, the passage selected in the reading app.

**Selection**: The text currently highlighted in another app and available to become a quote. It is not itself a saved note.

**Voice take**: One attempt to turn speech into text. A cancelled take contributes no note or dictation.
_Avoid_: Voice note (when referring to unfinished audio)

**Voice note**: A note captured by speaking, with an optional quote.

**Typed note**: A note captured by typing, with an optional quote.

**Dictation**: Speech converted to text and inserted at the cursor in another app. It does not create a note or belong to a stack.
_Avoid_: Capture (when referring to dictation's outcome)

**Hold mode**: Speaking while a shortcut is held; releasing it requests completion.

**Tap mode**: Speaking between one shortcut press to start and another to finish.

**Live transcript**: Provisional words displayed while speaking. They are not the final saved thought.

## Handoff

**Export**: Formatting a stack's notes as Markdown and placing the result on the clipboard, optionally pasting it into another app. Clearing the exported notes is optional.
_Avoid_: Send (when implying Sendpoint calls an AI service)

**Template**: A named preamble and note-formatting choices used for export. Currently it also includes the choice to clear notes after export.

**Preamble**: Instructions placed before the notes in an exported prompt.

## Interaction surfaces

**Stack viewer**: The window for browsing and editing the current stack's notes.
_Avoid_: Palette (in user-facing language)

**Stack readout**: Brief feedback identifying the stack selected by a shortcut, without opening its viewer.

**Capture editor**: The temporary editor for a new typed note.

**Latest-note editor**: The separate interaction for revising the newest note in the current stack.
