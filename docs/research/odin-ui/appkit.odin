// macOS AppKit-from-Odin feasibility probe. No Swift, Objective-C source, web or GPU toolkit.
// Run from the repository root. Uses synthetic input, not a human IME/VoiceOver test.
package main

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:time"
import NS "core:sys/darwin/Foundation"

@(objc_class="NSTextView") TextView :: struct {using _: NS.View}
@(objc_class="NSTextField") TextField :: struct {using _: NS.View}
@(objc_class="NSScrollView") ScrollView :: struct {using _: NS.View}
@(objc_class="NSButton") Button :: struct {using _: NS.View}
@(objc_class="NSVisualEffectView") Effect :: struct {using _: NS.View}
@(objc_class="NSFont") Font :: struct {using _: NS.Object}
@(objc_class="NSAppearance") Appearance :: struct {using _: NS.Object}
@(objc_class="NSBezierPath") Path :: struct {using _: NS.Object}
foreign import appkit "system:AppKit.framework"
foreign appkit {
    NSAccessibilityUnignoredDescendant :: proc "c" (element: ^NS.Object) -> ^NS.Object ---
}
msg :: intrinsics.objc_send
clicks: int
changes: int

str :: proc(s: cstring) -> ^NS.String { return msg(^NS.String, NS.String, "stringWithUTF8String:", s) }
utf8 :: proc(s: ^NS.String) -> string { return string(msg(cstring, s, "UTF8String")) }
yes :: proc "c" (self: NS.id, cmd: NS.SEL) -> bool { return true }
no :: proc "c" (self: NS.id, cmd: NS.SEL) -> bool { return false }
action :: proc "c" (self: NS.id, cmd: NS.SEL, sender: NS.id) {
    context = runtime.default_context()
    clicks += 1
}
changed :: proc "c" (self: NS.id, cmd: NS.SEL, notification: NS.id) {
    context = runtime.default_context()
    changes += 1
}
draw :: proc "c" (self: NS.id, cmd: NS.SEL, rect: NS.Rect) {
    // Deliberately custom drawing surrounded by real controls, not a canvas UI.
    context = runtime.default_context()
    color := msg(^NS.Color, NS.Color, "systemGreenColor")
    msg(nil, color, "setFill")
    path := msg(^Path, Path, "bezierPathWithOvalInRect:", NS.Rect{{3, 3}, {18, 18}})
    msg(nil, path, "fill")
}
subclass :: proc(name, parent: cstring) -> NS.Class {
    cls := NS.objc_allocateClassPair(NS.objc_lookUpClass(parent), name, 0)
    assert(cls != nil)
    return cls
}
method :: proc(cls: NS.Class, selector: cstring, imp: NS.IMP, encoding: cstring) {
    assert(NS.class_addMethod(cls, NS.sel_registerName(selector), imp, encoding))
}
// Runtime-created classes must be instantiated after registration. A static
// @(objc_class=...) reference can be resolved before the class exists (nil).
instance :: proc(cls: NS.Class) -> ^NS.Object { return cast(^NS.Object)NS.class_createInstance(cls, 0) }

pump :: proc(app: ^NS.Application, seconds: f64) {
    start := time.tick_now()
    for time.duration_seconds(time.tick_since(start)) < seconds {
        pool := NS.new(NS.AutoreleasePool)
        date := msg(^NS.Date, NS.Date, "dateWithTimeIntervalSinceNow:", f64(0.01))
        event := msg(^NS.Event, app, "nextEventMatchingMask:untilDate:inMode:dequeue:", ~uint(0), date, str("kCFRunLoopDefaultMode"), bool(true))
        if event != nil { msg(nil, app, "sendEvent:", event) }
        msg(nil, app, "updateWindows")
        msg(nil, pool, "drain")
    }
}
main :: proc() {
    pool := NS.new(NS.AutoreleasePool)
    defer msg(nil, pool, "drain")
    app := msg(^NS.Application, NS.Application, "sharedApplication")
    _ = msg(bool, app, "setActivationPolicy:", int(1))
    msg(nil, app, "finishLaunching")

    cls := subclass("SendpointProbePanel", "NSPanel")
    method(cls, "canBecomeKeyWindow", cast(NS.IMP)yes, "B@:")
    method(cls, "canBecomeMainWindow", cast(NS.IMP)no, "B@:")
    NS.objc_registerClassPair(cls)
    target_class := subclass("SendpointProbeTarget", "NSObject")
    method(target_class, "save:", cast(NS.IMP)action, "v@:@")
    method(target_class, "textDidChange:", cast(NS.IMP)changed, "v@:@")
    NS.objc_registerClassPair(target_class)
    target := NS.init(instance(target_class))
    defer NS.release(target)
    orb_class := subclass("SendpointProbeOrb", "NSView")
    method(orb_class, "drawRect:", cast(NS.IMP)draw, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}")
    NS.objc_registerClassPair(orb_class)

    panel := msg(^NS.Panel, instance(cls), "initWithContentRect:styleMask:backing:defer:", NS.Rect{{100, 100}, {560, 280}}, uint(1 << 7), uint(2), bool(false))
    defer NS.release(panel)
    msg(nil, panel, "setReleasedWhenClosed:", bool(false))
    msg(nil, panel, "setHidesOnDeactivate:", bool(false))
    msg(nil, panel, "setBecomesKeyOnlyIfNeeded:", bool(false))
    msg(nil, panel, "setLevel:", int(3))
    msg(nil, panel, "setOpaque:", bool(false))
    msg(nil, panel, "setBackgroundColor:", msg(^NS.Color, NS.Color, "clearColor"))

    effect := msg(^Effect, NS.alloc(Effect), "initWithFrame:", NS.Rect{{0, 0}, {560, 280}})
    defer NS.release(effect)
    msg(nil, effect, "setMaterial:", int(6)) // popover
    msg(nil, effect, "setBlendingMode:", int(0)) // behindWindow
    msg(nil, effect, "setState:", int(1)) // active
    msg(nil, panel, "setContentView:", effect)

    label := msg(^TextField, TextField, "labelWithString:", str("Sendpoint · AppKit from Odin"))
    msg(nil, label, "setFrame:", NS.Rect{{24, 232}, {480, 24}})
    msg(nil, effect, "addSubview:", label)
    scroll := msg(^ScrollView, NS.alloc(ScrollView), "initWithFrame:", NS.Rect{{24, 72}, {512, 148}})
    defer NS.release(scroll)
    msg(nil, scroll, "setHasVerticalScroller:", bool(true))
    text := msg(^TextView, NS.alloc(TextView), "initWithFrame:", NS.Rect{{0, 0}, {490, 148}})
    defer NS.release(text)
    msg(nil, text, "setRichText:", bool(false))
    msg(nil, text, "setAllowsUndo:", bool(true))
    msg(nil, text, "setVerticallyResizable:", bool(true))
    msg(nil, text, "setHorizontallyResizable:", bool(false))
    msg(nil, text, "setFont:", msg(^Font, Font, "systemFontOfSize:", f64(18)))
    msg(nil, text, "setString:", str("Retina · العربية · 日本語 · 👩🏽‍💻\nNative selection, editing, undo and input methods."))
    msg(nil, text, "setAccessibilityLabel:", str("Note"))
    msg(nil, text, "setDelegate:", target)
    defer msg(nil, text, "setDelegate:", NS.id(nil))
    msg(nil, scroll, "setDocumentView:", text)
    msg(nil, effect, "addSubview:", scroll)
    button := msg(^Button, Button, "buttonWithTitle:target:action:", str("Save"), target, NS.sel_registerName("save:"))
    msg(nil, button, "setFrame:", NS.Rect{{440, 20}, {96, 32}})
    msg(nil, effect, "addSubview:", button)
    orb := msg(^NS.View, instance(orb_class), "initWithFrame:", NS.Rect{{24, 24}, {24, 24}})
    defer NS.release(orb)
    // Custom decorative drawing does not become a meaningful AX control by magic.
    msg(nil, orb, "setAccessibilityElement:", bool(false))
    msg(nil, effect, "addSubview:", orb)

    fmt.printf("Before show: app active=%v\n", msg(bool, app, "isActive"))
    msg(nil, panel, "orderFrontRegardless")
    pump(app, 0.1)
    msg(nil, panel, "makeKeyWindow")
    assert(msg(bool, panel, "makeFirstResponder:", text))
    assert(msg(^NS.Object, panel, "firstResponder") == cast(^NS.Object)text)
    fmt.printf("Panel key=%v; app active=%v; backingScale=%.1f\n", msg(bool, panel, "isKeyWindow"), msg(bool, app, "isActive"), msg(f64, panel, "backingScaleFactor"))
    msg(nil, text, "setSelectedRange:", NS.Range{0, 6})
    assert(msg(NS.Range, text, "selectedRange").length == 6)
    msg(nil, text, "setMarkedText:selectedRange:replacementRange:", str("にほん"), NS.Range{0, 3}, NS.Range{0, 6})
    assert(msg(bool, text, "hasMarkedText"))
    // Production state projection must not call setString while this is true.
    msg(nil, text, "insertText:replacementRange:", str("日本"), NS.Range{0, 3})
    assert(!msg(bool, text, "hasMarkedText"))
    msg(nil, button, "performClick:", NS.id(nil))
    assert(clicks == 1 && changes > 0)
    fmt.printf("AX roles: text=%s button=%s; callbacks: save=%d change=%d\n", utf8(msg(^NS.String, text, "accessibilityRole")), utf8(msg(^NS.String, NSAccessibilityUnignoredDescendant(cast(^NS.Object)button), "accessibilityRole")), clicks, changes)

    // Restore the same fixture after synthetic composition, for comparable images.
    msg(nil, text, "setString:", str("Retina · العربية · 日本語 · 👩🏽‍💻\nNative selection, editing, undo and input methods."))
    msg(nil, text, "setSelectedRange:", NS.Range{0, 0})
    // Snapshot only this app's content view; no desktop screenshot permission.
    dark := len(os.args) > 1 && os.args[1] == "dark"
    appearance := msg(^Appearance, Appearance, "appearanceNamed:", str("NSAppearanceNameDarkAqua" if dark else "NSAppearanceNameAqua"))
    msg(nil, panel, "setAppearance:", appearance)
    pump(app, 0.2)
    bounds := msg(NS.Rect, effect, "bounds")
    bitmap := msg(^NS.BitmapImageRep, effect, "bitmapImageRepForCachingDisplayInRect:", bounds)
    msg(nil, effect, "cacheDisplayInRect:toBitmapImageRep:", bounds, bitmap)
    props := NS.new(NS.Dictionary)
    defer NS.release(props)
    data := msg(^NS.Data, bitmap, "representationUsingType:properties:", uint(4), props)
    output := str("docs/research/odin-ui/appkit-dark.png" if dark else "docs/research/odin-ui/appkit-light.png")
    assert(msg(bool, data, "writeToFile:atomically:", output, bool(true)))
    msg(nil, panel, "orderOut:", NS.id(nil))
    msg(nil, text, "setDelegate:", NS.id(nil))
    msg(nil, panel, "setContentView:", NS.id(nil))
    msg(nil, panel, "close")
    fmt.println("PASS: native controls, subclass drawRect, target/action, text delegate, selection, synthetic marked text, snapshot, explicit teardown")
}
