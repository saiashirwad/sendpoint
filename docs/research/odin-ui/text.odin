// Core Text is callable from Odin; this is shaping evidence, not an editor/renderer.
package main
import "base:intrinsics"
import "core:fmt"
import NS "core:sys/darwin/Foundation"

foreign import ct "system:CoreText.framework"
foreign import cf "system:CoreFoundation.framework"
foreign ct {
    CTLineCreateWithAttributedString :: proc "c" (s: rawptr) -> rawptr ---
    CTLineGetGlyphRuns :: proc "c" (line: rawptr) -> rawptr ---
    CTLineGetTypographicBounds :: proc "c" (line: rawptr, ascent, descent, leading: ^f64) -> f64 ---
    CTRunGetGlyphCount :: proc "c" (run: rawptr) -> int ---
    CTRunGetAttributes :: proc "c" (run: rawptr) -> rawptr ---
    CTFontCopyPostScriptName :: proc "c" (font: rawptr) -> ^NS.String ---
    kCTFontAttributeName: rawptr
}
foreign cf {
    CFArrayGetCount :: proc "c" (array: rawptr) -> int ---
    CFArrayGetValueAtIndex :: proc "c" (array: rawptr, index: int) -> rawptr ---
    CFDictionaryGetValue :: proc "c" (dictionary, key: rawptr) -> rawptr ---
    CFRelease :: proc "c" (value: rawptr) ---
}
@(objc_class="NSAttributedString") AttributedString :: struct {using _: NS.Object}
@(objc_class="NSAutoreleasePool") Pool :: struct {using _: NS.Object}
msg :: intrinsics.objc_send
main :: proc() {
    pool := NS.new(Pool)
    defer msg(nil, pool, "drain")
    samples := []cstring{"Sendpoint", "العربية", "日本語", "👩🏽‍💻", "é"}
    for sample in samples {
        string := msg(^NS.String, NS.String, "stringWithUTF8String:", sample)
        attr := msg(^AttributedString, NS.alloc(AttributedString), "initWithString:", string)
        line := CTLineCreateWithAttributedString(attr)
        runs := CTLineGetGlyphRuns(line)
        fmt.printf("%s: width %.2f pt, %d runs\n", sample, CTLineGetTypographicBounds(line, nil, nil, nil), CFArrayGetCount(runs))
        for index in 0..<CFArrayGetCount(runs) {
            run := CFArrayGetValueAtIndex(runs, index)
            font := CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName)
            name := CTFontCopyPostScriptName(font)
            fmt.printf("  %s: %d glyphs\n", msg(cstring, name, "UTF8String"), CTRunGetGlyphCount(run))
            NS.release(name)
        }
        CFRelease(line)
        NS.release(attr)
    }
}
