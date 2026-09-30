// Tests compiler-generated Objective-C implementation, separately from runtime registration.
package main
import "base:intrinsics"
import "core:fmt"
import NS "core:sys/darwin/Foundation"

@(objc_class="OdinResearchAttributeObject", objc_implement=true, objc_superclass=NS.Object)
Probe :: struct { using _: NS.Object }

@(objc_type=Probe, objc_name="answer", objc_selector="answer")
Probe_answer :: proc "c" (self: ^Probe) -> int { return 47 }

main :: proc() {
    pool := NS.AutoreleasePool_init(NS.AutoreleasePool_alloc())
    defer NS.AutoreleasePool_drain(pool)
    obj := intrinsics.objc_send(^Probe, Probe, "alloc")
    obj = intrinsics.objc_send(^Probe, obj, "init")
    defer NS.release(obj)
    answer := intrinsics.objc_send(int, obj, "answer")
    assert(answer == 47)
    fmt.println("objc_implement answer:", answer)
}
