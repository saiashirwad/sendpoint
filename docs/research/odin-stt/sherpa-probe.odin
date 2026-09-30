package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

// Minimal hand translation of the v1.13.8 C header, not a maintained binding.
Model :: struct {
    encoder, decoder, joiner: cstring,
    para_encoder, para_decoder, zipformer: cstring,
    tokens: cstring,
    num_threads: i32,
    provider: cstring,
    debug: i32,
    model_type, modeling_unit, bpe_vocab, tokens_buf: cstring,
    tokens_buf_size: i32,
    nemo_ctc, t_one_ctc: cstring,
}
Config :: struct {
    sample_rate, feature_dim: i32,
    model: Model,
    decoding_method: cstring,
    max_active_paths, enable_endpoint: i32,
    rule1, rule2, rule3: f32,
    hotwords_file: cstring,
    hotwords_score: f32,
    ctc_graph: cstring,
    ctc_max_active: i32,
    rule_fsts, rule_fars: cstring,
    blank_penalty: f32,
    hotwords_buf: cstring,
    hotwords_buf_size: i32,
    hr_dict, hr_lexicon, hr_rules: cstring,
}
Wave :: struct { samples: [^]f32, sample_rate, num_samples: i32 }
Result :: struct {
    text, tokens: cstring,
    tokens_arr: [^]cstring,
    timestamps: [^]f32,
    count: i32,
    json: cstring,
}
foreign import sherpa "system:sherpa-onnx-c-api"
@(default_calling_convention="c", link_prefix="SherpaOnnx")
foreign sherpa {
    CreateOnlineRecognizer :: proc(config: ^Config) -> rawptr ---
    DestroyOnlineRecognizer :: proc(r: rawptr) ---
    CreateOnlineStream :: proc(r: rawptr) -> rawptr ---
    DestroyOnlineStream :: proc(s: rawptr) ---
    OnlineStreamAcceptWaveform :: proc(s: rawptr, rate: i32, samples: [^]f32, n: i32) ---
    IsOnlineStreamReady :: proc(r, s: rawptr) -> i32 ---
    DecodeOnlineStream :: proc(r, s: rawptr) ---
    OnlineStreamInputFinished :: proc(s: rawptr) ---
    GetOnlineStreamResult :: proc(r, s: rawptr) -> ^Result ---
    DestroyOnlineRecognizerResult :: proc(r: ^Result) ---
    ReadWave :: proc(path: cstring) -> ^Wave ---
    FreeWave :: proc(w: ^Wave) ---
    GetVersionStr :: proc() -> cstring ---
}
main :: proc() {
    assert(len(os.args) == 7, "encoder decoder joiner tokens wav provider")
    args: [6]cstring
    for a, i in os.args[1:] { args[i] = strings.clone_to_cstring(a) }
    defer for a in args { delete(a) }
    cfg := Config{
        sample_rate = 16000, feature_dim = 80,
        model = Model{encoder=args[0], decoder=args[1], joiner=args[2], tokens=args[3], num_threads=2, provider=args[5]},
        decoding_method = "greedy_search",
    }
    fmt.printf("sherpa=%s config_size=%d model_size=%d\n", GetVersionStr(), size_of(Config), size_of(Model))
    t0 := time.tick_now()
    r := CreateOnlineRecognizer(&cfg)
    assert(r != nil)
    defer DestroyOnlineRecognizer(r)
    fmt.printf("load_ms=%.3f\n", time.duration_milliseconds(time.tick_since(t0)))
    s := CreateOnlineStream(r)
    assert(s != nil)
    defer DestroyOnlineStream(s)
    w := ReadWave(args[4])
    assert(w != nil)
    defer FreeWave(w)
    fmt.printf("audio_s=%.3f\n", f64(w.num_samples)/f64(w.sample_rate))
    t1 := time.tick_now()
    previous := ""
    defer delete(previous)
    // Feed 20ms chunks without sleeping: throughput test, not live latency.
    step := w.sample_rate / 50
    for pos: i32 = 0; pos < w.num_samples; pos += step {
        n := min(step, w.num_samples-pos)
        OnlineStreamAcceptWaveform(s, w.sample_rate, w.samples[pos:], n)
        for IsOnlineStreamReady(r,s) != 0 { DecodeOnlineStream(r,s) }
        result := GetOnlineStreamResult(r,s)
        assert(result != nil)
        text := string(result.text)
        if text != previous {
            fmt.printf("partial audio_ms=%d text=%s\n", (pos+n)*1000/w.sample_rate, text)
            delete(previous)
            previous = strings.clone(text)
        }
        DestroyOnlineRecognizerResult(result)
    }
    tail := time.tick_now()
    OnlineStreamInputFinished(s)
    for IsOnlineStreamReady(r,s) != 0 { DecodeOnlineStream(r,s) }
    result := GetOnlineStreamResult(r,s)
    assert(result != nil)
    fmt.printf("final=%s\ntail_ms=%.3f decode_ms=%.3f\n", result.text,
        time.duration_milliseconds(time.tick_since(tail)), time.duration_milliseconds(time.tick_since(t1)))
    DestroyOnlineRecognizerResult(result)
}
