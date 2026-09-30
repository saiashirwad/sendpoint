package main
import "base:intrinsics"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import ns "core:sys/darwin/Foundation"
@(require) foreign import coreml "system:CoreML.framework"
send :: intrinsics.objc_send
@(objc_class="MLModelConfiguration")
Model_Config :: struct {using _: ns.Object}
@(objc_class="MLModel")
Model :: struct {using _: ns.Object}
@(objc_class="MLMultiArray")
Multi_Array :: struct {using _: ns.Object}
@(objc_class="MLDictionaryFeatureProvider")
Feature_Provider :: struct {using _: ns.Object}

str :: proc(s: cstring) -> ^ns.String {
    return send(^ns.String, ns.String, "stringWithUTF8String:", s)
}
array :: proc(shape: []int, dtype: int) -> ^Multi_Array {
    dims: [3]^ns.Number
    for d, i in shape { dims[i] = send(^ns.Number, ns.Number, "numberWithInteger:", d) }
    ns_shape := send(^ns.Array, ns.Array, "arrayWithObjects:count:", raw_data(dims[:]), uint(len(shape)))
    err: ^ns.Error
    a := send(^Multi_Array, Multi_Array, "alloc")
    a = send(^Multi_Array, a, "initWithShape:dataType:error:", ns_shape, dtype, &err)
    assert(a != nil)
    return a
}
decoder_step :: proc(model: ^Model) {
    // Genuine RNNT initial state: blank token 1024, length 1, zero h/c.
    targets := array([]int{1,1}, 0x20020)
    length := array([]int{1}, 0x20020)
    h := array([]int{2,1,640}, 0x10020)
    c := array([]int{2,1,640}, 0x10020)
    defer send(nil, targets, "release")
    defer send(nil, length, "release")
    defer send(nil, h, "release")
    defer send(nil, c, "release")
    send(^i32, targets, "dataPointer")^ = 1024
    send(^i32, length, "dataPointer")^ = 1
    states := [2]^Multi_Array{h,c}
    for state in states {
        data := send([^]f32, state, "dataPointer")
        for i in 0..<1280 { data[i] = 0 }
    }
    keys := [4]^ns.String{str("targets"), str("target_length"), str("h_in"), str("c_in")}
    values := [4]^Multi_Array{targets,length,h,c}
    dict := send(^ns.Dictionary, ns.Dictionary, "dictionaryWithObjects:forKeys:count:", raw_data(values[:]), raw_data(keys[:]), uint(4))
    err: ^ns.Error
    features := send(^Feature_Provider, Feature_Provider, "alloc")
    features = send(^Feature_Provider, features, "initWithDictionary:error:", dict, &err)
    assert(features != nil)
    defer send(nil, features, "release")
    start := time.tick_now()
    result := send(^Feature_Provider, model, "predictionFromFeatures:error:", features, &err)
    assert(result != nil)
    value := send(^ns.Object, result, "featureValueForName:", str("decoder"))
    output := send(^Multi_Array, value, "multiArrayValue")
    count := send(int, output, "count")
    assert(count == 640)
    fmt.printf("decoder_prediction_ms=%.3f output_count=%d first_value=%f\n", time.duration_milliseconds(time.tick_since(start)), count, send(^f32, output, "dataPointer")^)
}
main :: proc() {
    assert(len(os.args) == 2 || len(os.args) == 3, "compiled .mlmodelc directory [decoder]")
    pool := send(^ns.AutoreleasePool, ns.AutoreleasePool, "new")
    defer send(nil, pool, "drain")
    path := strings.clone_to_cstring(os.args[1])
    defer delete(path)
    str := send(^ns.String, ns.String, "stringWithUTF8String:", path)
    url := send(^ns.URL, ns.URL, "fileURLWithPath:", str)
    config := send(^Model_Config, Model_Config, "new")
    defer send(nil, config, "release")
    send(nil, config, "setComputeUnits:", int(0) if len(os.args) == 3 else int(3))
    err: ^ns.Error
    start := time.tick_now()
    model := send(^Model, Model, "modelWithContentsOfURL:configuration:error:", url, config, &err)
    if model == nil {
        message := send(^ns.String, err, "localizedDescription")
        fmt.println(send(cstring, message, "UTF8String"))
        os.exit(1)
    }
    fmt.printf("load_ms=%.3f\n", time.duration_milliseconds(time.tick_since(start)))
    description := send(^ns.Object, model, "modelDescription")
    text := send(^ns.String, description, "description")
    fmt.println(send(cstring, text, "UTF8String"))
    if len(os.args) == 3 { decoder_step(model) }
}
