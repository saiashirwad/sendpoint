// Non-mutating probes: no mic/AX prompt, hotkey registration, or login-item change.
package main
import "base:intrinsics"
import "core:fmt"
import NS "core:sys/darwin/Foundation"
@(require) foreign import av "system:AVFoundation.framework"
@(require) foreign import sm "system:ServiceManagement.framework"
foreign import ax "system:ApplicationServices.framework"
foreign import audio "system:CoreAudio.framework"
foreign ax {
    AXIsProcessTrusted :: proc "c" () -> u8 ---
    AXUIElementCreateSystemWide :: proc "c" () -> rawptr ---
    CFRelease :: proc "c" (rawptr) ---
}
Address :: struct { selector, scope, element: u32 }
foreign audio {
    AudioObjectGetPropertyData :: proc "c" (id: u32, address: ^Address, qualifier_size: u32, qualifier: rawptr, size: ^u32, data: rawptr) -> i32 ---
}
msg :: intrinsics.objc_send
Obj :: ^NS.Object
@(objc_class="AVAudioEngine") Engine :: struct { using _: NS.Object }
@(objc_class="AVCaptureDevice") Capture :: struct { using _: NS.Object }
@(objc_class="SMAppService") Service :: struct { using _: NS.Object }
main :: proc() {
    pool := NS.AutoreleasePool_init(NS.AutoreleasePool_alloc())
    defer NS.AutoreleasePool_drain(pool)
    engine := msg(Obj, msg(Obj, Engine, "alloc"), "init")
    assert(engine != nil)
    defer NS.release(engine)
    fmt.println("AVAudioEngine running:", msg(NS.BOOL, engine, "isRunning"))
    audio_type := msg(^NS.String, NS.String, "stringWithUTF8String:", cstring("soun"))
    fmt.println("AVCaptureDevice audio authorization status:", msg(int, Capture, "authorizationStatusForMediaType:", audio_type))
    service := msg(Obj, Service, "mainAppService")
    assert(service != nil)
    fmt.println("SMAppService status (unbundled):", msg(int, service, "status"))
    fmt.println("AX trusted:", AXIsProcessTrusted() != 0)
    system := AXUIElementCreateSystemWide()
    assert(system != nil)
    CFRelease(system)
    // kAudioHardwarePropertyDefaultInputDevice='dIn ', global scope='glob', main element=0.
    address := Address{0x64496e20, 0x676c6f62, 0}
    device: u32
    size := u32(size_of(device))
    err := AudioObjectGetPropertyData(1, &address, 0, nil, &size, &device)
    fmt.println("CoreAudio default input query OSStatus:", err, "has device:", device != 0)
    assert(err == 0)
}
