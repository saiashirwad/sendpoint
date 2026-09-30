package main

import "core:fmt"
import "core:strings"
import edit "core:text/edit"
import ui "vendor:microui"

main :: proc() {
	builder: strings.Builder
	defer strings.builder_destroy(&builder)
	state: edit.State
	edit.init(&state, context.allocator, context.allocator)
	defer edit.destroy(&state)
	edit.setup_once(&state, &builder)
	assert(edit.input_text(&state, "first\nsecond") == 12)
	assert(strings.to_string(builder) == "first\nsecond")
	// Vertical navigation consumes positions supplied by the layout host.
	state.up_index = 3
	edit.move_to(&state, .Up)
	assert(state.selection[0] == 3)
	edit.move_to(&state, .End)
	// Despite its per-frame comment, begin resets selection and undo history.
	edit.begin(&state, 1, &builder)
	assert(state.selection == [2]int{12, 0})
	fmt.printf("PASS: multiline buffer, host-supplied Up, begin selects all; microui Context=%d bytes\n", size_of(ui.Context))
}
