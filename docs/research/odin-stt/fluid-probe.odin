package main
import "core:fmt"
import "core:os"
import "core:strings"
import "base:runtime"
foreign import fluid "system:OdinFluidProbe"
foreign fluid {
    odin_fluid_probe :: proc "c"(cache, wav: cstring, callback: proc "c"(kind: i32, text: cstring)) ---
}
received_error: bool
on_event :: proc "c" (kind: i32, text: cstring) {
    // Called on Swift's worker, which has no implicit Odin context.
    context = runtime.default_context()
    if kind == 3 { received_error = true }
    fmt.printf("event=%d %s\n", kind, text)
}
main :: proc() {
    assert(len(os.args) == 3, "cache-directory wav")
    cache := strings.clone_to_cstring(os.args[1])
    wav := strings.clone_to_cstring(os.args[2])
    defer delete(cache)
    defer delete(wav)
    // Export waits for its one Task to settle; no callbacks survive its return.
    odin_fluid_probe(cache, wav, on_event)
    assert(!received_error, "Swift bridge reported an error")
}
