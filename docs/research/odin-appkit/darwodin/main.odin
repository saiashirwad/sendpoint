// Optional third-party generated-binding probe; see parent README for collection flag.
package main
import "core:fmt"
import "base:intrinsics"
import UI "darwodin:AppKit"
import NS "darwodin:Foundation"
main :: proc() {
    pool := intrinsics.objc_send(^NS.AutoreleasePool, NS.AutoreleasePool, "alloc")
    pool = intrinsics.objc_send(^NS.AutoreleasePool, pool, "init")
    defer intrinsics.objc_send(nil, pool, "drain")
    app := UI.Application.sharedApplication()
    assert(app != nil)
    text := NS.String.stringWithUTF8String("Generated bindings")
    field := UI.TextField.textFieldWithString(text)
    assert(field != nil)
    fmt.println("darwodin native text field created")
}
