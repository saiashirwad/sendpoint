package main
import "base:intrinsics"
import "core:fmt"
import NS "core:sys/darwin/Foundation"

// Missing wrappers are deliberately tiny and typed, not an untyped objc_msgSend cast.
@(objc_class="NSTextField")
Text_Field :: struct {using _: NS.View}
@(objc_class="NSTextView")
Text_View :: struct {using _: NS.View}
@(objc_class="NSVisualEffectView")
Visual_Effect_View :: struct {using _: NS.View}
msg :: intrinsics.objc_send

main :: proc() {
    pool := NS.AutoreleasePool_init(NS.AutoreleasePool_alloc())
    defer NS.AutoreleasePool_drain(pool)
    app := NS.Application_sharedApplication()
    NS.Application_setActivationPolicy(app, .Accessory)
    rect := NS.Rect{{0, 0}, {400, 180}}
    panel := msg(^NS.Panel, NS.Panel, "alloc")
    panel = msg(^NS.Panel, panel, "initWithContentRect:styleMask:backing:defer:",
        rect, NS.WindowStyleMask{.NonactivatingPanel}, NS.BackingStoreType.Buffered, NS.BOOL(false))
    assert(panel != nil)
    msg(nil, panel, "setReleasedWhenClosed:", NS.BOOL(false))
    defer msg(nil, panel, "release")
    defer msg(nil, panel, "close")
    visual := msg(^Visual_Effect_View, Visual_Effect_View, "alloc")
    visual = msg(^Visual_Effect_View, visual, "initWithFrame:", rect)
    defer msg(nil, visual, "release")
    msg(nil, panel, "setContentView:", visual)
    field := msg(^Text_Field, Text_Field, "alloc")
    field = msg(^Text_Field, field, "initWithFrame:", NS.Rect{{16, 130}, {368, 24}})
    defer msg(nil, field, "release")
    msg(nil, field, "setEditable:", NS.BOOL(false))
    text := NS.MakeConstantString("Odin native AppKit probe")
    msg(nil, field, "setStringValue:", text)
    msg(nil, visual, "addSubview:", field)
    editor := msg(^Text_View, Text_View, "alloc")
    editor = msg(^Text_View, editor, "initWithFrame:", NS.Rect{{16, 16}, {368, 100}})
    defer msg(nil, editor, "release")
    msg(nil, editor, "setString:", text)
    msg(nil, visual, "addSubview:", editor)
    // Intentionally never orderFront/run: no visible app or permission prompts.
    assert(msg(^NS.String, field, "stringValue") != nil)
    fmt.println("NSPanel + NSVisualEffectView + NSTextField + NSTextView constructed")
}
