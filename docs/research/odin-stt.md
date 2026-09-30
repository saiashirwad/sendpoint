# Parakeet Unified from Odin — native AppKit rewrite

Research for [#48](https://github.com/saiashirwad/sendpoint/issues/48), under [map #35](https://github.com/saiashirwad/sendpoint/issues/35). Checked **2026-09-30**. Research code only; no app changes, microphone recording, `check.sh`, or `ship.sh`.

## Decision

**Build the next STT spike around direct Core ML calls from Odin, keeping the existing Parakeet Unified Core ML weights. No Swift is required to perform inference.** This is now demonstrated with real audio, incremental text, and a final flush in [`coreml-stream.odin`](odin-stt/coreml-stream.odin), not merely inferred from Objective-C interoperability.

**sherpa-onnx's C API is straightforward and works from Odin**, but the tested INT8 240 ms Unified export was substantially slower than real time on this M5, on both CPU and the packaged `coreml` provider. Keep it as a portable/reference path, not the default low-latency Mac choice on this evidence. These results do not rule out other exports, context sizes, thread counts, or an improved provider configuration.

**FluidAudio in a Swift dylib/helper is last-resort fallback only.** A working dylib reference was built to compare the same Core ML assets, but is not required by the pure-Odin prototype. No web view, TypeScript, Electron, or Tauri is proposed. The user's mid-research clarification supersedes the map's original web-UI premise.

The remaining gate is **productionizing native audio capture, ownership/cancellation, model installation and AppKit delivery**, then measuring real key-release→visible-text latency and total system footprint. This research does not declare the whole rewrite ready to ship.

## What actually ran

Environment: Apple **M5**, **32 GiB** memory, macOS **27.0 (26A428)**, Odin **dev-2026-09:a2fb372b7**, Apple Swift **6.4** for the optional reference. Low-power mode was disabled in both battery/AC profiles. This was a shared working machine, not an isolated benchmark lab; power source, thermal state and competing work were not controlled.

| Spike | Verified result | What it does not establish |
|---|---|---|
| [`objc-probe.odin`](odin-stt/objc-probe.odin) | Creates `MLModelConfiguration`, sets/reads CPU+ANE, instantiates `AVAudioEngine` directly from Odin | Does not start capture or prove hardware execution placement |
| [`audio-probe.odin`](odin-stt/audio-probe.odin) | Calls CoreAudio's C `AudioObjectGetPropertyData`; default input device 108, status 0 | Device IDs are machine-local; no capture/permission test |
| [`coreml-probe.odin`](odin-stt/coreml-probe.odin) | Loads real Unified bundles, inspects shapes, runs the initial RNNT decoder prediction with blank token/zero recurrent state; 640 output values | Decoder-only smoke test, not transcription by itself |
| [`coreml-stream.odin`](odin-stt/coreml-stream.odin) | **Full pure-Odin file transcription:** Core ML preprocessor → INT8 encoder → decoder/joint → vocabulary, partials and final | File-fed, no real-time microphone, no cancellation API, no corpus accuracy test |
| [`sherpa-probe.odin`](odin-stt/sherpa-probe.odin) | Direct foreign imports of sherpa's streaming C API, full real-audio transcription on CPU and `coreml` | Hand-written subset binding, not ABI-stable production package |
| [`fluid-bridge/`](odin-stt/fluid-bridge/) + [`fluid-probe.odin`](odin-stt/fluid-probe.odin) | Odin → Swift C export → pinned FluidAudio → C callbacks into Odin; real partials/final | Blocking research export, not the proposed production lifecycle API; no IPC prototype |

### Measurements: file-fed, not hotkey latency

Input: the **7.435 s**, 16 kHz mono `test_wavs/0.wav` in sherpa's published Unified 240 ms archive. Three successful fresh-process runs per path; files already downloaded. Sherpa accepts 20 ms chunks without sleeping and drains every ready window. FluidAudio accepts the same 20 ms chunks without sleeping. Direct Core ML evaluates each ready 320/160 ms window without sleeping. Logging and result retrieval are included. Models remain loaded throughout each recording, but are not reused across recordings in one process.

| Path / preset | Model load range | Decode total range (median) | Tail flush range | Process max RSS range |
|---|---:|---:|---:|---:|
| Odin → sherpa CPU, INT8 **240 ms**, 2 threads | 815–934 ms | 23.75–26.88 s (**26.16 s**) | 779–1,137 ms | 1.225–1.236 GB |
| Odin → sherpa `coreml`, same export/threads | 3.95–4.94 s | 34.17–36.46 s (**35.23 s**) | 1,083–1,591 ms | 2.305–2.723 GB |
| **Odin → Core ML directly**, INT8 **320 ms**, Core ML preprocessor | 101–136 ms¹ | 0.764–0.803 s (**0.797 s**) | 16.9–17.2 ms | 68.8 MB¹ |
| Optional Odin → Swift FluidAudio, INT8 **320 ms**, Swift mel | 74–6,700 ms | 0.669–0.696 s (**0.696 s**) | 13.4–15.9 ms | 59.9–657.0 MB¹ |

¹ **Do not interpret the low warmed Core ML process RSS as the model's total RAM cost.** Core ML/ANE caches and services can be outside the measured process, and OS/model caches were not purged. Initial direct encoder load alone took 6.88 s; the first FluidAudio run loaded in 6.70 s with 657 MB max RSS, later processes were much cheaper. Direct successful full-stream runs occurred after earlier model loads. `/usr/bin/time -l` also reports a distinct peak-footprint counter; raw values are retained, not conflated with RSS. No total process-tree/system-delta RAM or idle CPU conclusion follows here.

All raw results are in [`odin-stt/results/`](odin-stt/results/), including [`direct-stream.txt`](odin-stt/results/direct-stream.txt), [`cpu-run.txt`](odin-stt/results/cpu-run.txt), [`coreml-run.txt`](odin-stt/results/coreml-run.txt), and [`fluid-run.txt`](odin-stt/results/fluid-run.txt). The Core ML-provider runs emitted `Context leak detected, CoreAnalytics returned false`; this was not diagnosed as an application memory leak.

The direct Core ML and FluidAudio final transcripts **matched on this one clip**:

> Well, I don't wish to see it any more, observed Phoebe, turning away her eyes it is certainly very like the old portrait

Sherpa produced `anymore` and a period before `It`. These are different export/context/preprocessor paths; no WER or bitwise-parity claim. The direct path is ~9.3× real-time throughput here; sherpa CPU is ~0.28×. A “240 ms” preset is a required audio-context window, **not a promise that computation finishes in 240 ms**.

An additional real-audio truncation at exactly **7.360 s** exercised the direct path's exact-chunk-boundary final flush; [`direct-boundary.txt`](odin-stt/results/direct-boundary.txt) contains exactly one final. This is a narrow regression check, not a full stream test suite.

## A. sherpa-onnx C API via `foreign import`

This path is real and simple: link `libsherpa-onnx-c-api.dylib`, which links ONNX Runtime and libc++; no C++ or Swift application source is necessary. The included program translates the versioned config/result structs, uses `cstring`, `i32`, `f32` and opaque pointers, and declares the **C calling convention**. Odin's default procedure convention includes implicit context and must not be used as a C callback signature. Strings returned inside results are borrowed until that result is destroyed; clone text before handing it to another queue. [O1, S1]

The verified sequence is:

1. Zero-initialize the complete `SherpaOnnxOnlineRecognizerConfig`; set encoder, decoder, joiner and tokens paths, provider, threads, and `greedy_search`. Leave endpoint detection off for hold/release recording.
2. `CreateOnlineRecognizer` once per loaded model, `CreateOnlineStream` once per take.
3. `OnlineStreamAcceptWaveform` → while `IsOnlineStreamReady`, `DecodeOnlineStream` → `GetOnlineStreamResult` → copy changed text → `DestroyOnlineRecognizerResult`.
4. On release, stop ingress, drain queued audio, `OnlineStreamInputFinished`, drain readiness again, publish final once, then destroy the stream. Retain the recognizer for later takes.
5. On cancel, invalidate context, stop audio and stop scheduling decode work, allow the current call to return, then destroy the stream on its owner thread. Do not destroy an in-use stream from the UI thread. [S1, S2; lifecycle ordering is the proposed integration contract]

Unified streaming was added in **1.13.2**; the executed package/header was **1.13.8**. This is the actual Unified FastConformer-RNNT, not Parakeet TDT or repeatedly running an offline recognizer. Its dedicated implementation accepts only greedy search, builds buffered feature windows, and permits short zero-padded right context after input finishes. `PostInit` takes feature dimension from model metadata and sets Unified's feature-extraction options; the generic 80-bin config field in the C example is overridden for this model. [S2, S3]

**ABI maintenance is a real task:** tested config/model sizes were 272/136 bytes on arm64. Match the whole header and library version, not a guessed prefix of a growing config struct. Add C/Odin size, alignment and field-offset checks in a maintained binding; the successful inference here is not a promise of compatibility with the next sherpa release. Release builds need app-relative `@rpath`, correct arm64/x86_64 slices if supporting both, embedded dylib signing and licence notices. The reproduction script's absolute build-directory rpath is deliberately not a shipping layout. [S1, S4; packaging recommendations]

### Why `provider=coreml` did not fix performance

The inspected sherpa `session.cc` registers the **older Core ML flags API with flags zero** on supported builds. ONNX Runtime now documents that API as deprecated; defaults use the NeuralNetwork model format, while the newer options support MLProgram, compute-unit selection, static-shape restrictions, compute-plan profiling and model caching. Operator support and graph partitioning are constrained. **A provider name does not prove that Unified's expensive encoder executes on ANE.** [S5, OR1]

The packaged provider did run and produced text, but was slower and larger in these samples. We did not collect graph partitioning or per-operation compute plans; therefore cannot attribute its cost conclusively to CPU fallback, conversions, partitions or caching. Exploring a patched/newer MLProgram provider and matching contexts is a separate optimization experiment, not a reason to claim ANE parity today.

## B. Direct Core ML from pure Odin — recommended native route

### Bindings are available at the runtime level, not as a finished STT package

Odin's current `core:sys/darwin/Foundation` has Objective-C runtime declarations, AppKit/Foundation types, subclass helpers and compiler-backed `intrinsics.objc_send`. Define a missing Apple class with `@(objc_class="MLModel")` and `using _: ns.Object`, then call its documented selectors with exact argument/return types. The probes use this path, rather than blindly casting variadic `objc_msgSend`. Use `nil` as the void return specification, not a fictitious Odin `void` type. Link frameworks explicitly with `@(require) foreign import ... "system:CoreML.framework"`. [O2, O3; compiled probes]

**Surprising migration trap:** `vendor:darwin/Foundation` is a three-line `#panic` stub saying it moved to `core:sys/darwin/Foundation`. At the inspected Odin revision, `vendor:darwin` contains CoreVideo, Foundation stub, Metal, MetalKit and QuartzCore; there are no ready CoreML/CoreAudio/AVFoundation packages in that tree. `core:sys/darwin` supplies Foundation, CoreFoundation, CoreGraphics, Security and OS interfaces, not comprehensive bindings to every Apple SDK. Native frameworks remain callable; missing typed declarations are work to own, not a Swift requirement. [O2–O4]

Manual Objective-C memory management matters: retain live model/state objects, release them at a single owner boundary, and use autorelease pools on worker iterations. Core ML tensors have data types, shapes and strides; do not assume all are contiguous just because one sample is. The direct prototype reads encoder strides and preserves RNNT recurrent state across windows. Production needs checked errors instead of assertions/exits and typed wrappers around selectors. [A1, A2; prototype]

### A full pipeline, not “call MLModel and get words”

The included direct implementation uses these real stages:

- **Core ML preprocessor** (`parakeet_unified_preprocessor.mlmodelc`), CPU-only, accepts `audio_signal` Float32 `[1,N]` and `audio_length` Int32 `[1]`; yields `mel` and `mel_length`.
- **Streaming INT8 encoder 70/2/2**, CPU+ANE allowed: input `mel` Float32 `[1,128,593]`, output `encoder` Float32 `[1,1024,75]` plus lengths. One window is 94,720 samples; first advance is 5,120 samples (320 ms), subsequent advances 2,560 (160 ms), with two right-context encoder frames held back.
- **RNNT decoder**, CPU-only: `targets [1,1]`, `target_length [1]`, recurrent `h_in/c_in [2,1,640]`. Initialize zero state and blank token **1024**. Decode/joint outputs advance recurrent state only on accepted nonblank tokens; blank advances time, and the reference caps emissions at 10 symbols per frame.
- **Single-step joint decision**, CPU-only: `encoder_step [1,1024,1]` plus `decoder_step [1,640,1]` → `token_id`/probability. Translate token IDs through the model vocabulary and SentencePiece word marker `▁` to spaces.
- **Rolling window/final rules:** retain left history, align windows to encoder frames, suppress re-decoding old frames, and emit the withheld tail once even when release happens on an exact chunk boundary. [F1–F4, H1; actual model descriptions in results]

The orchestration is adapted from FluidAudio's **Apache-2.0** source, with its licence retained as [`LICENSE-FluidAudio.txt`](odin-stt/LICENSE-FluidAudio.txt); it is not a port of the whole Swift SDK. The prototype is intentionally narrow: one fixed preset, simple vocabulary assembly, no vocabulary boosting, corpus validation, live resampling or production session owner.

**Useful discovery: the published Core ML preprocessor can avoid an initial DSP port.** Its MIL signature permits dynamic audio length up to 240,000 samples, including the 94,720-sample streaming window. It was downloaded at pinned Hugging Face revision `d32e972dd4315f1dc3f6be28fb2aab0ab3e80358` and worked in the full Odin transcript test. This differs from today's FluidAudio Swift mel implementation, so retain parity tests rather than assuming numeric equivalence. [H1, H2, F3]

If preprocessing becomes a bottleneck, port the native mel path using C Accelerate/vDSP calls or Odin DSP, not Swift: 16 kHz; FFT 512; symmetric Hann 400; hop 160; 128 mel bins; preemphasis 0.97; log guard 2^-24; **per-feature** mean/variance normalization over valid frames. Pay attention to valid length `floor(samples/160)`, versus tensor extent `floor(samples/160)+1`, and padding masks. Those details are accuracy-sensitive, especially at small streaming chunks. Do not substitute a generic log-mel implementation. [F3]

### Acceleration

The caller language does not select the hardware. Direct Odin can set the same `MLModelConfiguration.computeUnits` as Swift and use the same converted models. Keep decoder/joint on CPU; allow CPU+ANE for the INT8 encoder. FluidAudio specifically coerces INT8 `.all` to `.cpuAndNeuralEngine` to avoid a known GPU/MPSGraph failure; FP16 `.all` is a distinct option, with different memory/performance tradeoffs. This research verified configuration and successful inference, **not exact ANE residency**. Use Core ML Instruments/compute-plan inspection before asserting where each operation runs. [F1, A1]

## Microphone capture, levels and AppKit delivery

Both choices below can be implemented with **Odin application code only**:

| Capture path | Mechanism | Tradeoff |
|---|---|---|
| **CoreAudio HAL C API** | Foreign-bind `AudioDeviceCreateIOProcID`, `AudioDeviceStart/Stop`, property/listener APIs and `AudioDeviceDestroyIOProcID`; inspect device format; copy input into an owned PCM queue | Ordinary C callbacks with user-data are a clean fit for Odin. More format/device/resampling and hot-plug handling to implement |
| **AVAudioEngine via Objective-C** | Create engine/input node, query format, install/remove input tap, prepare/start/stop; copy `AVAudioPCMBuffer` data before the callback returns; use AVAudioConverter or an explicit resampler | Closer to current Sendpoint. The tap is an Objective-C **block with two arguments**, not a C function pointer |

Apple SDK declarations and the current app demonstrate these APIs. The native probes verify framework linkage/device query/engine construction, **not live capture**. [A3, A4, B1]

Odin's `NSBlock.odin` supplies zero- and **one-parameter** helper constructors; it is not a ready-made two-parameter `AVAudioNodeTapBlock` adapter. Implement the correct block literal/invoke signature with copy/dispose/lifetime handling, or choose the CoreAudio C callback path. Do not pass a stack closure or cast an ordinary `proc "c"` to a block. New macOS 27 tap APIs also expose an error-returning selector; bind with availability handling rather than assuming a latest-SDK call works on all supported macOS versions. [O5, A4, B1]

Proposed architecture for AppKit:

- Main thread owns AppKit widgets and the closed Odin workflow enum/event transition. One retained native worker owns the recognizer, stream state and inference calls. One audio owner handles the capture lifecycle. Queue commands rather than mutating either from arbitrary callbacks.
- Audio callback only copies into a **bounded preallocated ring**, records sequence/format, and computes cheap sum-of-squares/peak if desired. No inference, UI, disk/network, heap growth or blocking waits there. Detect overflow as an error/discontinuity, not invisible transcript loss.
- Convert hardware channel layout/rate to **16 kHz mono Float32** on the worker. Do not assume the physical device is 16 kHz or interleaved. Preserve current preferred-device selection; rebuild after route/rate changes.
- Compute RMS/dB level from PCM independently of STT, coalesce to ~20–30 Hz, and deliver the latest value to the main thread. Coalesce partial **whole-transcript snapshots**, but reliably deliver finals/errors/cancel acknowledgements. Never append partial strings as if they were deltas.
- One main-thread mailbox/run-loop wakeup handles events and updates `NSTextField`/`NSTextView` or drawing state. No JSON/IPC or web rendering is needed for the direct/native paths. Tag every event with app generation, take ID, capture-target identity and sequence; validate before applying it.
- Add `NSMicrophoneUsageDescription`, request consent, and validate packaged signing/hardened-runtime microphone entitlement behavior. A development CLI's permission identity is not evidence that the signed menu-bar app is correct. [A5; architecture recommendations]

## Release latency and cancellation contract

**Tail inference time is not key-release-to-text time.** The measured 17 ms direct flush begins after all preceding file-fed windows have finished; a real recording can have an inference backlog. Measure:

`key-up delivery + stop ingress + callback settlement + queued audio/resampling + pending inference + final-window prediction + main-thread delivery + AppKit display`.

Theoretical 320 ms context is not an extra timer to wait after release: the final window can be padded/flushed immediately. A sufficiently slow backend (as in the tested sherpa preset) can accumulate seconds of backlog; a fast FFI boundary cannot hide that. [F2, S2; analytical decomposition]

Proposed semantics, not implemented by the research CLI:

1. `start(context)` opens exactly one take after permission/model readiness. Preserve a pending finish if key-up occurs before mic startup completes.
2. `finish(context)` stops audio ingress, waits for callback/worker ownership to settle, drains accepted samples exactly once, finalizes the stream, publishes one terminal result if the full context still matches, resets while retaining warm models.
3. `cancel(context)` invalidates the take **immediately**, stops mic, discards queued samples and UI partials, signals the worker, waits for any external call to return, then resets/destroys its per-take state. A returned stale inference result is ignored. A new take waits for settlement, not merely a cancel-request acknowledgement.
4. Check cancellation/context before and after every download/load/prediction/decode boundary. Neither the synchronous Core ML prediction call used here nor sherpa's C streaming API supplies this application's complete cancel protocol; cancellation must be safe even if a call cannot be interrupted.
5. Idempotent teardown on Escape, quit, device failure and owner loss: stop capture, revoke context, stop/join worker, release stream/tensors/model when safe, remove callbacks/listeners. Never free a callback context until callback invocation is impossible.

Tests needed: short clips; empty input; exact-boundary flush; release-before-start; cancellation during model load/inference/finish; duplicate finish/teardown; repeated cancel/restart; route changes; permission denial; queue overflow; stale target; no live mic after teardown. The narrow boundary smoke test does **not** satisfy this list.

## Downloads, RAM and packaging

- **Keep the checkpoint, not necessarily the runtime.** The Core ML assets and ONNX exports derive from `nvidia/parakeet-unified-en-0.6b`, but are not interchangeable files. Core ML conversion/model card declares **CC-BY-4.0**; retain NVIDIA/FluidInference attribution independently of software licences. [H1, S3]
- Direct Odin can read the existing cache at `~/Library/Application Support/FluidAudio/Models/parakeet-unified-en-0.6b` without linking FluidAudio. The inspected cache total was **608,330,968 bytes**, including encoder/decoder/joint/vocab/config/metadata. File names, sizes and SHA-256 hashes are recorded in [`coreml-cache-manifest.json`](odin-stt/results/coreml-cache-manifest.json); its original download revision was not independently established. The additional pinned preprocessor is ~623 KB. Existing cache bytes were not modified.
- sherpa's tested streaming INT8 archive is **501,358,456 bytes compressed**. `prepare.py` pins the downloaded archive hash, library hash, and preprocessor revision. These are network/disk quantities, not RAM budgets. Core ML 320 ms and sherpa 240 ms have different chunk/right contexts, so the comparison is not export-equivalent. [S4, H1; local hashes]
- A production pure-Odin installer must own HTTPS download progress/cancel, a pinned manifest, integrity verification, safe extraction, staging and atomic promotion, retry/recovery after interruption, and model-version/config compatibility. Use Foundation NSURLSession through delegates/blocks or an audited C HTTP boundary; Swift is not intrinsically required. The research downloader is a convenience script, not that installer.
- Keep downloaded/compiled models outside the signed application bundle. Download only the chosen tier and required shared stages; do not fetch every variant. If distributing source model packages instead of `.mlmodelc`, add Core ML compilation as an owned, cancellable/fenced preparation step. Preserve a previously valid cache until the replacement validates. [A1, F1; installer recommendations]
- Measure warmed/recording/peak **system delta** and relevant Core ML services, not only host RSS. Also measure idle CPU with capture stopped; neither this CLI nor a model file size establishes idle cost. Retaining warm models trades memory for subsequent-start latency.

## C. Last-resort Swift dylib or helper

The pinned reference uses FluidAudio `4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b` (Sendpoint's 0.15.6 baseline). Its real C-export/dylib test works, with a retained Swift task, UTF-8 callback strings borrowed only during the callback, and an Odin `proc "c"` callback that initializes its own Odin context. It exposes **no Swift object, String, array or async ABI directly**. `@_cdecl` is underscored compiler surface, not an assumption that arbitrary Swift symbols form a stable C API. [F1, B2; built reference]

If direct-Odin parity or engineering cost blocks delivery, replace that blocking probe with a small versioned opaque-handle C contract: create/prepare/start/finish/cancel/destroy and tagged events. Define buffer ownership, allowed caller/callback threads, last-callback acknowledgement and allocator pairing. Keep policy in Odin; Swift owns only its audio/model resources.

A persistent helper process is another fallback: bounded length-framed commands/events, stdout reserved for protocol, stderr for logs, parent-EOF teardown, sequence/take IDs and a restart handshake. Prefer capturing in the engine-owning process rather than sending high-rate PCM through a text protocol. A helper isolates crashes but adds startup/IPC/process/TCC/signing work; it does not automatically save RAM or preserve the parent's microphone permission. No helper IPC or signed-distribution path was executed here.

## Reproduce and next gate

From repository root (arm64 Mac, Odin installed):

```sh
python3 docs/research/odin-stt/prepare.py  # Python >=3.12; ~510 MB initial download
bash docs/research/odin-stt/run.sh native
bash docs/research/odin-stt/run.sh sherpa cpu
bash docs/research/odin-stt/run.sh sherpa coreml
bash docs/research/odin-stt/run.sh direct
# Optional comparison only, not the chosen app architecture:
bash docs/research/odin-stt/run.sh fluid
```

Direct/native/reference modes require the existing Core ML cache; set `COREML_CACHE` to an equivalent directory. The manifest records exact inspected assets. The Python setup converts the **real provided WAV** to Float32 PCM; it does not synthesize audio. All binaries, weights and generated fixtures stay under `.build/odin-research`; only source and logs are committed. The probes are compiled individually with `-file`, not as one directory package. `run.sh native` and `run.sh direct` were executed successfully; the other modes reproduce the build/run commands used for the recorded runs.

**Next gate:** retain direct Odin/Core ML, replace file feeding with one signed CoreAudio/AVAudioEngine capture owner, implement/test the cancellation contract and AppKit delivery, and compare at least 30 warm live takes plus cold start on target hardware. Record first-audio→partial, release→visible-final median/p95, total memory/idle CPU and corpus transcript parity against FluidAudio. Test multiple input rates, Bluetooth/device loss and fast cancel/restart. Decide whether the Core ML preprocessor is accurate/fast enough across that corpus before investing in a native DSP port.

## Primary sources

The Swift baseline was read from [`research/rewrite-stt` at 6987331](https://github.com/saiashirwad/sendpoint/blob/6987331726f24452d89b63a1878b2911ac336652/docs/research/rewrite-stt.md). It is background, not a substitute for the source inspection and executed spikes above.

- **O1:** [Odin foreign system / procedure conventions](https://odin-lang.org/docs/overview/#foreign-system).
- **O2:** [Odin Foundation Objective-C declarations](https://github.com/odin-lang/Odin/blob/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/core/sys/darwin/Foundation/objc.odin), [type/intrinsic setup](https://github.com/odin-lang/Odin/blob/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/core/sys/darwin/Foundation/NSTypes.odin).
- **O3:** [Odin subclass/context helpers](https://github.com/odin-lang/Odin/blob/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/core/sys/darwin/Foundation/objc_helper.odin).
- **O4:** [vendor Foundation moved stub](https://github.com/odin-lang/Odin/blob/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/vendor/darwin/Foundation/dummy.odin), [core Darwin tree](https://github.com/odin-lang/Odin/tree/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/core/sys/darwin), [vendor Darwin tree](https://github.com/odin-lang/Odin/tree/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/vendor/darwin).
- **O5:** [Odin block implementation and helper signatures](https://github.com/odin-lang/Odin/blob/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/core/sys/darwin/Foundation/NSBlock.odin).
- **S1:** [sherpa v1.13.8 streaming C API/header, ownership and struct layout](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/c-api/c-api.h).
- **S2:** [Unified online recognizer, readiness/finalization/feature configuration](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/online-recognizer-transducer-nemo-parakeet-unified-impl.h).
- **S3:** [changelog](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/CHANGELOG.md), [Unified streaming export/packaging](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/scripts/nemo/parakeet-unified-en-0.6b/run-streaming.sh).
- **S4:** [1.13.8 native libraries](https://github.com/k2-fsa/sherpa-onnx/releases/tag/v1.13.8), [model archives](https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models). Tag resolved to `11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf` during inspection.
- **S5:** [sherpa execution-provider setup](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/session.cc).
- **OR1:** [ONNX Runtime Core ML EP options, old/new APIs and supported operators](https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html).
- **F1:** [pinned FluidAudio StreamingUnifiedAsrManager — load, compute units, finish/reset/cleanup](https://github.com/FluidInference/FluidAudio/blob/4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b/Sources/FluidAudio/ASR/Parakeet/Unified/StreamingUnifiedAsrManager.swift).
- **F2:** [window/final-boundary algorithm](https://github.com/FluidInference/FluidAudio/blob/4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b/Sources/FluidAudio/ASR/Parakeet/Unified/UnifiedStreamingWindower.swift), [configuration](https://github.com/FluidInference/FluidAudio/blob/4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b/Sources/FluidAudio/ASR/Parakeet/Unified/UnifiedConfig.swift).
- **F3:** [precise mel/length/normalization contract](https://github.com/FluidInference/FluidAudio/blob/4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b/Sources/FluidAudio/ASR/Parakeet/Unified/UnifiedMelExtractor.swift).
- **F4:** [RNNT recurrent-state algorithm](https://github.com/FluidInference/FluidAudio/blob/4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b/Sources/FluidAudio/ASR/Parakeet/Unified/UnifiedRnntDecoder.swift), [feature names](https://github.com/FluidInference/FluidAudio/blob/4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b/Sources/FluidAudio/ASR/Parakeet/Unified/UnifiedFeatureProviders.swift), [Apache-2.0 licence](https://github.com/FluidInference/FluidAudio/blob/4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b/LICENSE).
- **H1:** [Core ML model identity, presets and CC-BY-4.0 model card](https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml/blob/d32e972dd4315f1dc3f6be28fb2aab0ab3e80358/README.md).
- **H2:** [published preprocessor MIL signature](https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml/blob/d32e972dd4315f1dc3f6be28fb2aab0ab3e80358/parakeet_unified_preprocessor.mlmodelc/model.mil).
- **A1:** [Apple MLModel](https://developer.apple.com/documentation/coreml/mlmodel), [MLModelConfiguration](https://developer.apple.com/documentation/coreml/mlmodelconfiguration), [MLComputeUnits](https://developer.apple.com/documentation/coreml/mlcomputeunits).
- **A2:** [Apple MLMultiArray](https://developer.apple.com/documentation/coreml/mlmultiarray), [MLDictionaryFeatureProvider](https://developer.apple.com/documentation/coreml/mldictionaryfeatureprovider).
- **A3:** [Apple AudioDeviceCreateIOProcID](https://developer.apple.com/documentation/coreaudio/audiodevicecreateioprocid(_:_:_:_:)), [Core Audio](https://developer.apple.com/documentation/coreaudio). Exact C signatures/constants were read in the installed macOS SDK `CoreAudio.framework/Headers/AudioHardware.h` and `AudioHardwareBase.h`.
- **A4:** [Apple AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioengine), [AVAudioNode](https://developer.apple.com/documentation/avfaudio/avaudionode). Objective-C selectors/types are also in installed SDK `AVFAudio.framework/Headers`, `CoreML.framework/Headers`.
- **A5:** [Apple microphone usage description](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription), [audio-input entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input).
- **B1:** [Sendpoint microphone baseline](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Sources/Sendpoint/Voice/Microphone.swift).
- **B2:** [Sendpoint streaming baseline](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Sources/Sendpoint/Voice/VoiceTranscriber.swift).
