package main
import "core:fmt"
foreign import audio "system:CoreAudio.framework"
Address :: struct { selector, scope, element: u32 }
foreign audio {
    AudioObjectGetPropertyData :: proc "c"(object: u32, address: ^Address, qualifier_size: u32, qualifier: rawptr, size: ^u32, data: rawptr) -> i32 ---
}
main :: proc() {
    // AudioHardware.h: system object 1, default input 'dIn ', global 'glob', main 0.
    address := Address{0x64496e20, 0x676c6f62, 0}
    device: u32
    size := u32(size_of(device))
    status := AudioObjectGetPropertyData(1, &address, 0, nil, &size, &device)
    assert(status == 0)
    assert(size == 4)
    fmt.printf("CoreAudio default input device=%d status=%d (no capture started)\n", device, status)
}
