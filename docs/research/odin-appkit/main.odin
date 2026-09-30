// Native AppKit research spike. No Swift, Objective-C source, or web UI.
// Run from a logged-in macOS GUI session; default mode exits after five seconds.
package main

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:os"
import NS "core:sys/darwin/Foundation"

foreign import system "system:System"
foreign system {
    dispatch_async_f :: proc "c" (queue, data: rawptr, work: proc "c" (rawptr)) ---
    _dispatch_main_q: u8
}
foreign import cg "system:CoreGraphics.framework"
foreign import ct "system:CoreText.framework"
foreign cg {
    CGContextFillRect :: proc "c" (ctx: rawptr, rect: NS.Rect) ---
    CGContextSetTextPosition :: proc "c" (ctx: rawptr, x, y: f64) ---
    CGContextSaveGState :: proc "c" (ctx: rawptr) ---
    CGContextRestoreGState :: proc "c" (ctx: rawptr) ---
    CFRelease :: proc "c" (value: rawptr) ---
}
foreign ct {
    CTLineCreateWithAttributedString :: proc "c" (string: rawptr) -> rawptr ---
    CTLineDraw :: proc "c" (line, ctx: rawptr) ---
}
foreign import objc "system:objc"
Super :: struct { receiver: Obj, current_class: NS.Class }
foreign objc {
    @(link_name="objc_msgSendSuper2")
    send_super_raw :: proc "c" (super: rawptr, selector: NS.SEL, #c_vararg args: ..any) -> ^intrinsics.objc_object ---
}
msg :: intrinsics.objc_send
cls :: intrinsics.objc_find_class
sel :: intrinsics.objc_find_selector
Obj :: ^NS.Object
app, panel, status, delegate, root, field, editor, timer: Obj
view_class: NS.Class
launched, dispatched, block_called, drew, edited, animated: bool
appearance_count: int
manual: bool

str :: proc(s: cstring) -> ^NS.String {
    return msg(^NS.String, NS.String, "stringWithUTF8String:", s)
}
new_object :: proc(c: NS.Class) -> Obj {
    return msg(Obj, msg(Obj, cast(Obj)c, "alloc"), "init")
}
new_view :: proc(c: NS.Class, rect: NS.Rect) -> Obj {
    return msg(Obj, msg(Obj, cast(Obj)c, "alloc"), "initWithFrame:", rect)
}
add :: proc(c: NS.Class, name: cstring, imp: rawptr, encoding: cstring) {
    assert(NS.class_addMethod(c, NS.sel_registerName(name), cast(NS.IMP)imp, encoding))
}
no :: proc "c" (self: Obj, cmd: NS.SEL) -> NS.BOOL { return false }
yes :: proc "c" (self: Obj, cmd: NS.SEL) -> NS.BOOL { return true }
show :: proc "c" (self: Obj, cmd: NS.SEL, sender: Obj) {
    context = runtime.default_context()
    msg(nil, panel, "orderFrontRegardless")
    fmt.println("panel visible:", msg(NS.BOOL, panel, "isVisible"), "app active:", msg(NS.BOOL, app, "isActive"))
}
draw :: proc "c" (self: Obj, cmd: NS.SEL, dirty: NS.Rect) {
    context = runtime.default_context()
    // AppKit configures the current drawing context and effective appearance.
    color := msg(Obj, NS.Color, "controlAccentColor")
    msg(nil, color, "setFill")
    graphics := msg(Obj, cast(Obj)cls("NSGraphicsContext"), "currentContext")
    cg_context := msg(rawptr, graphics, "CGContext")
    assert(cg_context != nil)
    CGContextSaveGState(cg_context)
    defer CGContextRestoreGState(cg_context)
    CGContextFillRect(cg_context, NS.Rect{{0, 354}, {560, 6}})
    attrs := new_object(cls("NSMutableDictionary"))
    defer NS.release(attrs)
    msg(nil, attrs, "setObject:forKey:", msg(Obj, NS.Color, "labelColor"), str("NSColor"))
    msg(nil, attrs, "setObject:forKey:", msg(Obj, cast(Obj)cls("NSFont"), "systemFontOfSize:", f64(13)), str("NSFont"))
    text := msg(Obj, msg(Obj, cast(Obj)cls("NSAttributedString"), "alloc"), "initWithString:attributes:", str("Core Text drawn from Odin in drawRect:"), attrs)
    defer NS.release(text)
    line := CTLineCreateWithAttributedString(rawptr(text))
    assert(line != nil)
    defer CFRelease(line)
    CGContextSetTextPosition(cg_context, 20, 336)
    CTLineDraw(line, cg_context)
    drew = true
}
appearance_changed :: proc "c" (self: Obj, cmd: NS.SEL) {
    context = runtime.default_context()
    super := Super{self, view_class}
    send := cast(proc "c" (^Super, NS.SEL))send_super_raw
    send(&super, cmd)
    appearance_count += 1
    msg(nil, self, "setNeedsDisplay:", NS.BOOL(true))
}
text_changed :: proc "c" (self: Obj, cmd: NS.SEL, notification: Obj) {
    context = runtime.default_context()
    edited = true
    fmt.println("NSTextViewDelegate textDidChange:")
}
dispatch_callback :: proc "c" (data: rawptr) {
    context = runtime.default_context()
    dispatched = true
    fmt.println("dispatch_async_f: main queue callback")
}
animation_group :: proc "c" (data: rawptr, animation_context: Obj) {
    context = runtime.default_context()
    msg(nil, animation_context, "setDuration:", f64(0.15))
    proxy := msg(Obj, field, "animator")
    msg(nil, proxy, "setAlphaValue:", f64(0.85))
}
animation_complete :: proc "c" (data: rawptr) {
    context = runtime.default_context()
    animated = true
    fmt.println("NSAnimationContext completion")
}
block_callback :: proc "c" (data: rawptr, t: ^NS.Timer) {
    context = runtime.default_context()
    block_called = true
    // Test dark -> light effective-appearance delivery without changing system settings.
    dark := msg(Obj, cast(Obj)cls("NSAppearance"), "appearanceNamed:", str("NSAppearanceNameDarkAqua"))
    assert(dark != nil)
    msg(nil, root, "setAppearance:", dark)
    msg(nil, root, "displayIfNeeded")
    light := msg(Obj, cast(Obj)cls("NSAppearance"), "appearanceNamed:", str("NSAppearanceNameAqua"))
    assert(light != nil)
    msg(nil, root, "setAppearance:", light)
    msg(nil, root, "displayIfNeeded")
    msg(nil, root, "setAppearance:", Obj(nil)) // restore inheritance
    fmt.println("NSTimer copied block; appearance callbacks:", appearance_count)
}
finish :: proc "c" (self: Obj, cmd: NS.SEL, sender: Obj) {
    context = runtime.default_context()
    fmt.println("PASS launch/dispatch/block/draw/edit/animation:", launched, dispatched, block_called, drew, edited, animated)
    assert(launched && dispatched && block_called && drew && edited && animated && appearance_count >= 2)
    assert(!msg(NS.BOOL, root, "hasAmbiguousLayout"))
    fmt.println("Auto Layout root ambiguous:", msg(NS.BOOL, root, "hasAmbiguousLayout"))
    msg(nil, app, "stop:", Obj(nil))
    event := msg(Obj, NS.Event, "otherEventWithType:location:modifierFlags:timestamp:windowNumber:context:subtype:data1:data2:",
        uint(15), NS.Point{0, 0}, uint(0), f64(0), int(0), Obj(nil), i16(0), int(0), int(0))
    msg(nil, app, "postEvent:atStart:", event, NS.BOOL(true))
}
did_launch :: proc "c" (self: Obj, cmd: NS.SEL, notification: Obj) {
    context = runtime.default_context()
    launched = true
    show(self, cmd, nil)
    dispatch_async_f(&_dispatch_main_q, nil, dispatch_callback)
    msg(nil, editor, "setString:", str("Native NSTextView: select, edit, and use IME here.\nAutomated delegate notification follows."))
    msg(nil, editor, "didChangeText")
    assert(msg(NS.BOOL, editor, "isEditable"))
    group := NS.Block_createLocalWithParam(nil, animation_group)
    complete := NS.Block_createLocal(nil, animation_complete)
    msg(nil, cast(Obj)cls("NSAnimationContext"), "runAnimationGroup:completionHandler:", group, complete)
    NS.release(group)
    NS.release(complete)
    b := NS.Block_createLocalWithParam(nil, block_callback)
    msg(Obj, NS.Timer, "scheduledTimerWithTimeInterval:repeats:block:", f64(0.4), NS.BOOL(false), b)
    NS.release(b)
    if !manual {
        timer = msg(Obj, NS.Timer, "scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:",
            f64(5), delegate, sel("finish:"), Obj(nil), NS.BOOL(false))
        msg(Obj, timer, "retain")
    }
}
// Native NSLayoutAnchor constraints, installed on the common ancestor by AppKit.
pin :: proc(child: Obj, $child_anchor: string, parent: Obj, $parent_anchor: string, constant: f64) {
    a := msg(Obj, child, child_anchor)
    b := msg(Obj, parent, parent_anchor)
    c := msg(Obj, a, "constraintEqualToAnchor:constant:", b, constant)
    msg(nil, c, "setActive:", NS.BOOL(true))
}
main :: proc() {
    manual = len(os.args) > 1 && os.args[1] == "--manual"
    pool := NS.AutoreleasePool_init(NS.AutoreleasePool_alloc())
    defer NS.AutoreleasePool_drain(pool)
    app = msg(Obj, NS.Application, "sharedApplication")
    assert(msg(NS.BOOL, app, "setActivationPolicy:", int(1)))
    dc := NS.objc_allocateClassPair(cls("NSObject"), "OdinNativeResearchDelegate", 0)
    assert(dc != nil)
    assert(NS.class_addProtocol(dc, NS.objc_getProtocol("NSApplicationDelegate")))
    assert(NS.class_addProtocol(dc, NS.objc_getProtocol("NSTextViewDelegate")))
    add(dc, "applicationDidFinishLaunching:", rawptr(did_launch), "v@:@")
    add(dc, "textDidChange:", rawptr(text_changed), "v@:@")
    add(dc, "show:", rawptr(show), "v@:@")
    add(dc, "finish:", rawptr(finish), "v@:@")
    NS.objc_registerClassPair(dc)
    delegate = new_object(dc)
    msg(nil, app, "setDelegate:", delegate)
    pc := NS.objc_allocateClassPair(cls("NSPanel"), "OdinNativeResearchPanel", 0)
    add(pc, "canBecomeKeyWindow", rawptr(yes), "B@:")
    add(pc, "canBecomeMainWindow", rawptr(no), "B@:")
    NS.objc_registerClassPair(pc)
    panel = msg(Obj, msg(Obj, cast(Obj)pc, "alloc"), "initWithContentRect:styleMask:backing:defer:",
        NS.Rect{{200, 250}, {560, 360}}, uint(1 | (1 << 7)), uint(2), NS.BOOL(false))
    assert(panel != nil)
    msg(nil, panel, "setReleasedWhenClosed:", NS.BOOL(false))
    msg(nil, panel, "setTitle:", str("Odin / native AppKit research"))
    msg(nil, panel, "setLevel:", int(3))
    msg(nil, panel, "setHidesOnDeactivate:", NS.BOOL(false))
    assert(msg(NS.BOOL, panel, "canBecomeKeyWindow"))
    assert(!msg(NS.BOOL, panel, "canBecomeMainWindow"))
    assert(msg(uint, panel, "styleMask") & (1 << 7) != 0)

    view_class = NS.objc_allocateClassPair(cls("NSView"), "OdinNativeResearchView", 0)
    add(view_class, "drawRect:", rawptr(draw), "v@:{CGRect={CGPoint=dd}{CGSize=dd}}")
    add(view_class, "viewDidChangeEffectiveAppearance", rawptr(appearance_changed), "v@:")
    NS.objc_registerClassPair(view_class)
    root = new_view(view_class, NS.Rect{{0, 0}, {560, 360}})
    msg(nil, panel, "setContentView:", root)

    effect := new_view(cls("NSVisualEffectView"), NS.Rect{})
    msg(nil, effect, "setMaterial:", int(18)) // content background
    msg(nil, effect, "setBlendingMode:", int(0)) // behind window
    msg(nil, effect, "setState:", int(1)) // active, even though app stays inactive
    msg(nil, effect, "setTranslatesAutoresizingMaskIntoConstraints:", NS.BOOL(false))
    msg(nil, root, "addSubview:", effect)
    pin(effect, "leadingAnchor", root, "leadingAnchor", 0)
    pin(effect, "trailingAnchor", root, "trailingAnchor", 0)
    pin(effect, "topAnchor", root, "topAnchor", 36)
    pin(effect, "bottomAnchor", root, "bottomAnchor", 0)

    stack := new_view(cls("NSStackView"), NS.Rect{})
    msg(nil, stack, "setOrientation:", int(1)) // vertical
    msg(nil, stack, "setAlignment:", int(5)) // leading
    msg(nil, stack, "setSpacing:", f64(12))
    msg(nil, stack, "setTranslatesAutoresizingMaskIntoConstraints:", NS.BOOL(false))
    msg(nil, effect, "addSubview:", stack)
    pin(stack, "leadingAnchor", effect, "leadingAnchor", 20)
    pin(stack, "trailingAnchor", effect, "trailingAnchor", -20)
    pin(stack, "topAnchor", effect, "topAnchor", 20)
    label := msg(Obj, cast(Obj)cls("NSTextField"), "labelWithString:", str("Native controls, Auto Layout, vibrancy, custom drawing"))
    msg(nil, stack, "addArrangedSubview:", label)
    field = msg(Obj, cast(Obj)cls("NSTextField"), "textFieldWithString:", str("Editable NSTextField"))
    msg(nil, stack, "addArrangedSubview:", field)
    pin(field, "widthAnchor", stack, "widthAnchor", 0)
    scroll := new_view(cls("NSScrollView"), NS.Rect{{0, 0}, {520, 180}})
    editor = new_view(cls("NSTextView"), NS.Rect{{0, 0}, {520, 180}})
    msg(nil, editor, "setEditable:", NS.BOOL(true))
    msg(nil, editor, "setDelegate:", delegate)
    msg(nil, scroll, "setDocumentView:", editor)
    msg(nil, scroll, "setHasVerticalScroller:", NS.BOOL(true))
    msg(nil, stack, "addArrangedSubview:", scroll)
    pin(scroll, "widthAnchor", stack, "widthAnchor", 0)
    height := msg(Obj, msg(Obj, scroll, "heightAnchor"), "constraintEqualToConstant:", f64(180))
    msg(nil, height, "setActive:", NS.BOOL(true))
    msg(nil, field, "setWantsLayer:", NS.BOOL(true))
    layer := msg(Obj, field, "layer")
    msg(nil, layer, "setCornerRadius:", f64(4))
    msg(nil, root, "layoutSubtreeIfNeeded")
    NS.release(scroll)
    NS.release(stack)
    NS.release(effect)

    bar := msg(Obj, cast(Obj)cls("NSStatusBar"), "systemStatusBar")
    status = msg(Obj, bar, "statusItemWithLength:", f64(-1))
    msg(Obj, status, "retain")
    button := msg(Obj, status, "button")
    msg(nil, button, "setTitle:", str("Odin"))
    msg(nil, button, "setTarget:", delegate)
    msg(nil, button, "setAction:", sel("show:"))
    defer {
        if timer != nil { msg(nil, timer, "invalidate"); NS.release(timer) }
        msg(nil, editor, "setDelegate:", Obj(nil))
        msg(nil, app, "setDelegate:", Obj(nil))
        msg(nil, button, "setTarget:", Obj(nil))
        msg(nil, bar, "removeStatusItem:", status)
        NS.release(status)
        msg(nil, panel, "orderOut:", Obj(nil))
        NS.release(editor)
        NS.release(root)
        NS.release(panel)
        NS.release(delegate)
        fmt.println("teardown complete")
    }
    msg(nil, app, "run")
}
