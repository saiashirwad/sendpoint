package main
// Research-only Parakeet Unified 70/2/2 inference via Objective-C, no Swift.
// Adapted from FluidInference/FluidAudio (Apache-2.0), revision 4dbf4f9.
// Modified: translated window/RNNT orchestration to Odin and dictionary providers;
// uses the published Core ML preprocessor instead of Swift mel extraction.
// See LICENSE-FluidAudio.txt and the report for source links.
import "base:intrinsics"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:encoding/json"
import "core:time"
import ns "core:sys/darwin/Foundation"
@(require) foreign import coreml "system:CoreML.framework"
send :: intrinsics.objc_send
@(objc_class="MLModelConfiguration")
Config :: struct {using _: ns.Object}
@(objc_class="MLModel")
Model :: struct {using _: ns.Object}
@(objc_class="MLMultiArray")
Array :: struct {using _: ns.Object}
@(objc_class="MLDictionaryFeatureProvider")
Features :: struct {using _: ns.Object}
str :: proc(s: cstring) -> ^ns.String { return send(^ns.String, ns.String, "stringWithUTF8String:", s) }
error_check :: proc(value: rawptr, err: ^ns.Error) {
    if value == nil {
        text := send(^ns.String, err, "localizedDescription")
        fmt.eprintln(send(cstring, text, "UTF8String"))
        os.exit(1)
    }
}
load :: proc(path: string, units: int) -> ^Model {
    p := strings.clone_to_cstring(path)
    defer delete(p)
    url := send(^ns.URL, ns.URL, "fileURLWithPath:", str(p))
    cfg := send(^Config, Config, "new")
    defer send(nil, cfg, "release")
    send(nil, cfg, "setComputeUnits:", units)
    err: ^ns.Error
    model := send(^Model, Model, "modelWithContentsOfURL:configuration:error:", url, cfg, &err)
    error_check(model, err)
    return model
}
array :: proc(shape: []int, dtype: int) -> ^Array {
    dims: [3]^ns.Number
    for d, i in shape { dims[i] = send(^ns.Number, ns.Number, "numberWithInteger:", d) }
    shape_obj := send(^ns.Array, ns.Array, "arrayWithObjects:count:", raw_data(dims[:]), uint(len(shape)))
    err: ^ns.Error
    a := send(^Array, Array, "alloc")
    a = send(^Array, a, "initWithShape:dataType:error:", shape_obj, dtype, &err)
    error_check(a, err)
    send(nil, a, "autorelease")
    return a
}
predict :: proc(model: ^Model, names: []cstring, arrays: []^Array) -> ^Features {
    keys: [4]^ns.String
    for n,i in names { keys[i] = str(n) }
    dict := send(^ns.Dictionary, ns.Dictionary, "dictionaryWithObjects:forKeys:count:", raw_data(arrays), raw_data(keys[:]), uint(len(names)))
    err: ^ns.Error
    input := send(^Features, Features, "alloc")
    input = send(^Features, input, "initWithDictionary:error:", dict, &err)
    error_check(input, err)
    defer send(nil, input, "release")
    output := send(^Features, model, "predictionFromFeatures:error:", input, &err)
    error_check(output, err)
    return output
}
feature :: proc(f: ^Features, name: cstring) -> ^Array {
    value := send(^ns.Object, f, "featureValueForName:", str(name))
    a := send(^Array, value, "multiArrayValue")
    assert(a != nil)
    return a
}
ptr :: proc(a: ^Array) -> [^]f32 { return send([^]f32, a, "dataPointer") }
scalar :: proc(value: i32) -> ^Array {
    a := array([]int{1}, 0x20020)
    send(^i32, a, "dataPointer")^ = value
    return a
}
main :: proc() {
    assert(len(os.args) == 4, "model-cache preprocessor.mlmodelc sample.f32le")
    pool := send(^ns.AutoreleasePool, ns.AutoreleasePool, "new")
    defer send(nil, pool, "drain")
    bytes, err := os.read_entire_file(os.args[3], context.allocator); assert(err == nil)
    defer delete(bytes)
    assert(len(bytes)%4 == 0)
    samples := ([^]f32)(raw_data(bytes))[:len(bytes)/4]
    vocab_bytes, verr := os.read_entire_file(fmt.tprintf("%s/vocab.json", os.args[1]), context.allocator); assert(verr == nil)
    defer delete(vocab_bytes)
    vocab: map[string]string
    assert(json.unmarshal(vocab_bytes, &vocab) == nil)
    defer {
        for key, value in vocab { delete(key); delete(value) }
        delete(vocab)
    }
    start := time.tick_now()
    pre := load(os.args[2], 0)
    enc := load(fmt.tprintf("%s/parakeet_unified_encoder_streaming_70_2_2_int8.mlmodelc", os.args[1]), 3)
    dec := load(fmt.tprintf("%s/parakeet_unified_decoder.mlmodelc", os.args[1]), 0)
    joint := load(fmt.tprintf("%s/parakeet_unified_joint_decision_single_step.mlmodelc", os.args[1]), 0)
    fmt.printf("load_ms=%.3f audio_s=%.3f\n", time.duration_milliseconds(time.tick_since(start)), f64(len(samples))/16000)
    h := array([]int{2,1,640}, 0x10020)
    c := array([]int{2,1,640}, 0x10020)
    for i in 0..<1280 { ptr(h)[i] = 0; ptr(c)[i] = 0 }
    send(nil,h,"retain"); send(nil,c,"retain")
    defer send(nil,h,"release")
    defer send(nil,c,"release")
    token: i32 = 1024
    consumed, decoded := 0, 0
    final_emitted := false
    transcript := ""
    defer delete(transcript)
    decode_start := time.tick_now()
    tail_ms: f64
    // Each iteration is the next ready window. Audio is provided without sleeps.
    for !final_emitted {
        window_pool := send(^ns.AutoreleasePool, ns.AutoreleasePool, "new")
        window_start_time := time.tick_now()
        feed := 5120 if consumed == 0 else 2560
        // Like live finish: a full window is processed before InputFinished;
        // an exact-boundary ending still gets a separate final flush.
        full := consumed+feed <= len(samples)
        next := consumed+feed if full else len(samples)
        final := !full
        if len(samples) == 0 { send(nil,window_pool,"drain"); break }
        window_start := max(0, next-94720)
        window_start += (1280-window_start%1280)%1280
        audio := array([]int{1,94720}, 0x10020)
        p := ptr(audio)
        for i in 0..<94720 { p[i] = 0 }
        for i in window_start..<next { p[i-window_start] = samples[i] }
        mel := predict(pre, []cstring{"audio_signal","audio_length"}, []^Array{audio,scalar(i32(next-window_start))})
        encoded := predict(enc, []cstring{"mel","mel_length"}, []^Array{feature(mel,"mel"),feature(mel,"mel_length")})
        encoded_array := feature(encoded,"encoder")
        length := send(^i32,feature(encoded,"encoder_length"),"dataPointer")^
        local_start := decoded-window_start/1280
        local_end := int(length) - (0 if final else 2)
        // Newly allocated encoder output has shape [1,1024,75], but use reported strides.
        strides := send(^ns.Array,encoded_array,"strides")
        stride1 := send(int,send(^ns.Number,strides,"objectAtIndex:",uint(1)),"integerValue")
        stride2 := send(int,send(^ns.Number,strides,"objectAtIndex:",uint(2)),"integerValue")
        targets := array([]int{1,1},0x20020)
        send(^i32,targets,"dataPointer")^ = token
        step := predict(dec, []cstring{"targets","target_length","h_in","c_in"}, []^Array{targets,scalar(1),h,c})
        for t in local_start..<local_end {
            enc_step := array([]int{1,1024,1},0x10020)
            for d in 0..<1024 { ptr(enc_step)[d] = ptr(encoded_array)[d*stride1+t*stride2] }
            for symbol in 0..<10 {
                decision := predict(joint, []cstring{"encoder_step","decoder_step"}, []^Array{enc_step,feature(step,"decoder")})
                new_token := send(^i32,feature(decision,"token_id"),"dataPointer")^
                if new_token == 1024 { break }
                token = new_token
                next_h, next_c := feature(step,"h_out"), feature(step,"c_out")
                send(nil,next_h,"retain"); send(nil,next_c,"retain")
                send(nil,h,"release"); send(nil,c,"release")
                h, c = next_h, next_c
                piece := vocab[fmt.tprintf("%d", token)]
                spaced, allocated := strings.replace_all(piece,"▁"," ")
                next_text := strings.concatenate({transcript,spaced})
                if allocated { delete(spaced) }
                delete(transcript); transcript = next_text
                send(^i32,targets,"dataPointer")^ = token
                step = predict(dec, []cstring{"targets","target_length","h_in","c_in"}, []^Array{targets,scalar(1),h,c})
            }
        }
        decoded += max(0,local_end-local_start)
        consumed = next
        final_emitted = final
        fmt.printf("%s audio_ms=%d text=%s\n", "final" if final else "partial", next*1000/16000, strings.trim_space(transcript))
        if final { tail_ms = time.duration_milliseconds(time.tick_since(window_start_time)) }
        send(nil,window_pool,"drain")
    }
    fmt.printf("tail_ms=%.3f decode_ms=%.3f\n",tail_ms,time.duration_milliseconds(time.tick_since(decode_start)))
}
