package main

import "base:intrinsics"
import "core:fmt"
import ns "core:sys/darwin/Foundation"

@(require) foreign import coreml "system:CoreML.framework"
@(require) foreign import avfaudio "system:AVFAudio.framework"
send :: intrinsics.objc_send
@(objc_class="MLModelConfiguration")
Model_Config :: struct {using _: ns.Object}
@(objc_class="AVAudioEngine")
Audio_Engine :: struct {using _: ns.Object}

main :: proc() {
    pool := send(^ns.AutoreleasePool, ns.AutoreleasePool, "new")
    defer send(nil, pool, "drain")
    config := send(^Model_Config, Model_Config, "new")
    assert(config != nil)
    defer send(nil, config, "release")
    // MLComputeUnitsCPUAndNeuralEngine = 3 in the SDK header.
    send(nil, config, "setComputeUnits:", int(3))
    units := send(int, config, "computeUnits")
    assert(units == 3)
    engine := send(^Audio_Engine, Audio_Engine, "new")
    assert(engine != nil)
    defer send(nil, engine, "release")
    // Do not access inputNode/start: this probe must not request microphone access.
    running := send(bool, engine, "isRunning")
    assert(!running)
    fmt.printf("Core ML computeUnits=%d; AVAudioEngine running=%v\n", units, running)
}
