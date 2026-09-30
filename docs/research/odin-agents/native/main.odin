package main
import "core:fmt"
import NS "core:sys/darwin/Foundation"

main :: proc() {
    pool := NS.AutoreleasePool_alloc()
    pool = NS.AutoreleasePool_init(pool)
    defer NS.AutoreleasePool_drain(pool)
    // Proves linkage and typed ObjC messaging without opening UI or asking permissions.
    bundle := NS.Bundle_mainBundle()
    identifier := NS.Bundle_bundleIdentifier(bundle)
    fmt.println("bundle:", NS.String_UTF8String(identifier))
}
