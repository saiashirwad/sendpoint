# Parakeet Unified in a web-UI Sendpoint

Research for [ticket #37](https://github.com/saiashirwad/sendpoint/issues/37), under [map #35](https://github.com/saiashirwad/sendpoint/issues/35). Checked 2026-09-30. Research only; no application changes or performance runs.

## Decision

**Keep FluidAudio/Core ML as the native STT boundary for the rewrite spike, in either shell.** WKWebView-in-Swift can call the existing engine directly. Tauri 2 can use it through a custom desktop Rust↔Swift adapter; a persistent Swift sidecar is an alternative, not a per-recording executable. Stream small typed status/level/transcript messages to TypeScript, never microphone PCM through the web view.

**sherpa-onnx now supports Parakeet Unified specifically, including real buffered RNNT streaming.** It is not limited to Parakeet TDT or offline re-transcription. Its changelog records offline support in 1.13.0 and streaming in 1.13.2, and downloadable INT8 streaming artifacts exist. It is a viable alternative engine, but not a demonstrated faster/lower-memory/ANE-equivalent replacement on this Mac. Do not change engine and shell simultaneously in the first comparison. [S1–S5]

This resolves the STT integration question, **not** the map's shell go/no-go or performance gate. No measured key-release latency, process RAM, idle CPU, or signed Tauri microphone integration is claimed here.

## Evidence snapshot and model identity

- Sendpoint baseline: [`3288cbac`](https://github.com/saiashirwad/sendpoint/tree/3288cbacb3872f65845636e843319adc203b074c). `Package.resolved` pins FluidAudio **0.15.6**, revision `4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b`; `Package.swift` permits versions from 0.15.5. [A1]
- FluidAudio current HEAD inspected: **`8145085136df11758cc1303ab54d8e032c12bd41`**. The relevant load/stream/finish/compute-unit implementation was also checked against Sendpoint's pinned revision. [F1, F2]
- sherpa-onnx current HEAD inspected: **`040afe360a38e25daaa325ce8889abf93ea02609`**. Support statements below refer to this source snapshot and its release changelog, not every historical Rust binary. [S1]
- README's privacy/cache name is `parakeet-unified-en-0.6b`. FluidAudio's model is [`FluidInference/parakeet-unified-en-0.6b-coreml`](https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml), converted from **`nvidia/parakeet-unified-en-0.6b`**: English, ~0.6B FastConformer-RNNT, 16 kHz mono, punctuation/capitalization. This is not `parakeet-tdt-0.6b-v3`. The Core ML card declares CC-BY-4.0; retain model attribution when distributing it. [A1, F3]

## What already runs today

`LocalStreamingTranscriber` is an actor wrapping `StreamingUnifiedAsrManager`. It explicitly selects **`UnifiedConfig(leftFrames: 70, chunkFrames: 2, rightFrames: 2)`**, default INT8 encoder. It prepares one manager, primes it with silent chunk+right audio, then resets it. The speech session resets the manager, installs a partial callback, appends microphone buffers, processes available chunks, calls `finish()` for the tail, then resets. Preparation and speech carry task/session identity checks. [A2]

`VoiceNoteService` starts the mic, drains a native audio queue, feeds the actor, coalesces partials, and emits take-tagged output. On stop it cancels and awaits the streaming pump, waits for microphone stop, drains leftover audio, and finishes. `VoiceLevelMeter` computes normalized RMS/dB level independently of STT; no ASR round trip is necessary to animate the orb. [A3, A4]

These are useful native boundary behaviors to retain, **not a reason to keep app policy in Swift**. Per the map, port `CaptureState`/`VoiceMachine` policy to TypeScript; Swift retains audio/model resource ownership, serialization, cancellation safety, and request-context validation. Avoid keeping two competing business state machines.

## Shell comparison

| Route | Native path and UI delivery | Benefits | Extra work / unresolved risk |
|---|---|---|---|
| **Swift/AppKit + WKWebView + FluidAudio** | Native hotkey → TS workflow → Swift mic/ASR service; JS commands via `WKScriptMessageHandlerWithReply`; Swift pushes typed events with `callAsyncJavaScript` arguments | Smallest STT delta; same model cache and compute configuration; no extra STT process | Implement origin/frame validation, ordered delivery, reconnect/snapshot behavior, and teardown on web-content failure |
| **Tauri 2 + in-process FluidAudio** | TS `invoke` → Rust desktop command/plugin → custom Swift bridge → FluidAudio; native callbacks → Rust `Channel` → TS | Preserves Core ML engine, avoids helper-process IPC; PCM stays native | Build/link SwiftPM output into Rust app; explicit C-compatible/Objective-C-compatible interface, buffer ownership and callback lifetime; sign and test assembled app |
| **Tauri 2 + Swift sidecar** | Rust owns one persistent bundled Swift child; framed commands over stdin and events over stdout; Rust forwards events on a channel | Clear process boundary; can restart failed engine; retains FluidAudio | Extra process footprint; startup/warm-up; EOF/crash/cancel protocol; permissions/signing identity; stderr-only diagnostic logs; never allow orphan mic capture |
| **Tauri 2 + sherpa-onnx via Rust** | Native mic buffers → Rust worker → sherpa C/C++/ONNX Runtime through Rust API → channel | Unified streaming supported; removes FluidAudio dependency | Different model assets, feature/decoder/runtime behavior and provider packaging; parity, latency, memory and ANE coverage need measurement |

Apple documents the request/reply handler and asynchronous JS call APIs. Pass transcripts as structured **arguments**, not interpolated JavaScript source. Keep native services alive independently of whether the overlay is visible. [W1, W2]

**Important Tauri distinction:** Tauri's documented Swift plugin scaffold is for **iOS**. The docs explicitly split `desktop.rs` (Rust implementation) from `mobile.rs` (native mobile invocation). A macOS “Swift plugin” therefore means custom desktop interop, not an out-of-the-box `register_ios_plugin` integration. Neither the in-process adapter nor its distribution pipeline was built in this research. [T1]

Tauri officially bundles arbitrary-language sidecars with `externalBin` and architecture-suffixed binaries; Rust can own the child and read/write its pipes. Prefer that backend ownership over granting the web UI generic shell execution. Use a bounded framed protocol (e.g. length-limited JSON lines), reserve stdout for protocol, handle broken pipes and process termination, and close the microphone on parent EOF. Permission attribution for the signed helper must be tested, not assumed identical to the host. [T2; protocol details are recommendations]

## Streaming contract and ownership (proposed)

Use the same TypeScript-facing API whichever engine/shell is chosen:

- Commands: `prepare`, `start(context)`, `finish(context)`, `cancel(context)`, `dispose`.
- Events: `modelProgress`, `ready`, `started`, `level`, `partial`, `final`, `failed`, `cancelled`.
- Context: `{appGeneration, takeID, captureContextID}` plus monotonically increasing event sequence. Resolve the capture context to its stack/note/dictation target in TS; a take ID alone must not authorize writing into a newly selected destination.
- One TS owner retains the bridge subscription and lifecycle handles. One native owner retains mic/model/worker handles. A command acknowledgement is not a transcript. `finish` produces at most one terminal result; `cancel` revokes the context immediately and eventually acknowledges native cleanup.
- Keep microphone buffers, resampling and inference off the UI thread and out of JSON. Coalesce level to a proposed 20–30 Hz and partials to latest-value snapshots; finals/errors/cancel acknowledgements are reliable, not droppable. A partial is the **whole current transcript**, not an append-only token delta.
- Register the stream before starting capture. On page recreation request a current snapshot; do not replay old take events into a new page generation. On lost page/owner, fail closed: stop mic, invalidate take, cancel/await work, reset stream; duplicate teardown is harmless.
- Serialize the complete native operation sequence, not just individual calls. A cancelled inference may still return. Check cancellation and full context before and after each external await and before publishing; do not reset a manager while the old pump is still using it.

Tauri recommends **channels for ordered streaming**; its general events are not designed for low-latency/high-throughput traffic. Small low-rate status broadcasts can use events, but the take stream should be a channel with a tagged union payload. WKWebView needs the equivalent serial native sender plus bounded/coalesced queue. [T3]

## Hold, tap, stop and cancel semantics

Preserve the current user contract rather than delegating it to an ASR silence endpoint:

1. **Hold:** first key-down starts; repeat key-down is ignored; matching key-up requests finish. **Tap:** first press starts, next matching press finishes; release does not finish. Existing `releasePending` prevents a trailing release from ending a later session. [A5]
2. Selection acquisition and mic start can overlap. Release while selection/mic startup is pending must remain a pending finish intent in the TS capture machine; it must not become a lost native `stop` (the current voice machine only accepts stop once recording). [A5, A6]
3. **Finish:** stop audio ingress, await native stop and feed worker, drain tail once, flush recognizer, publish final if context still matches, reset session while retaining warm model. Silence alone must not terminate a hold/tap session.
4. **Cancel/Escape:** revoke the take first, stop mic, drop queued PCM/partials, cancel and await worker/finish, reset; never publish a cancelled final. A new take waits for reset/settlement. Cleanup must also happen on quit, navigation/bridge loss and sidecar death. [A3, A6; cross-process cases are recommendations]
5. Preserve the current **0.3 s minimum recorded clip** rule: a shorter clip is abandoned and emits an empty transcript, rather than forcing inference. Test actual mic-start time, not merely key-down time. [A6]

Port transition tests, particularly release-before-mic-start, cancel-during-finish, permission denial, key repeat, mismatched key release, stale selection/target, rapid restart and duplicate teardown. Native cancellation is not guaranteed to interrupt an already-running Core ML/ONNX call; correctness comes from fencing its output and awaiting safe settlement.

## FluidAudio versus sherpa-onnx: actual support and acceleration

### FluidAudio

The manager is genuinely streaming, but **not a cache-aware encoder**: it re-encodes a rolling `[left | chunk | right]` window and retains RNNT decoder state. `appendAudio` resamples, `processBufferedAudio` processes full windows, the callback publishes changed text, and `finish` flushes the remaining padded window(s). `reset` clears session state; `cleanup` also releases model references. [F1, F2]

At the inspected pinned/current implementations, decoder and joint run **CPU-only**; mel extraction is native Swift. The INT8 encoder default `.all` is coerced to **`.cpuAndNeuralEngine`**, with a source comment explaining an INT8 GPU/MPSGraph failure. FP16 allows GPU with `.all`. Therefore “all STT runs on ANE” and “FluidAudio uses GPU by default” are both inaccurate descriptions of this configuration. Eligible compute units are not a per-operation hardware residency measurement. [F1, F2]

The 320 ms variant is already selected by Sendpoint. Upstream's other Core ML variants are 640 ms `(70,7,1)`, 1120 ms `(70,7,7)`, and default 2080 ms `(70,13,13)`. Keep the explicit config: silently using the SDK default would significantly change partial cadence. [A2, F3, F4]

### sherpa-onnx

The source contains a dedicated `OnlineRecognizerTransducerNeMoParakeetUnifiedImpl`, dedicated model and greedy RNNT decoder, plus ONNX exports of the exact NVIDIA Unified checkpoint. It is **buffered streaming**, not the separate Rust `parakeet_tdt_simulate_streaming_microphone` example. `IsReady` waits for chunk+right feature frames; after `InputFinished` it permits final short chunks with zero-padded right context. Only `greedy_search` is accepted by this implementation. [S2, S3]

A Rust integration can configure encoder/decoder/joiner/tokens on `OnlineRecognizerConfig`, create one stream per take, call `accept_waveform`, repeatedly `is_ready`/`decode`, read `get_result` for partials, then `input_finished` and drain readiness for final. Set automatic endpointing off for hold/tap. Drop/reset the stream after cancel, retain the loaded recognizer, and run decoding in an owned worker rather than on Tauri's UI thread. The official Rust example demonstrates this generic API, but is **Zipformer**, not a verified Unified Rust sample; Unified compatibility is supported by the shared recognizer implementation and still needs an integration smoke test with the chosen Rust/native library versions. Do not copy Zipformer's extra 0.3 s padding blindly: Unified has its own final-flush path. [S2, S4]

Published INT8 Unified streaming presets are **240 ms `(70,1,2)`**, **560 ms `(70,2,5)`**, and **1120 ms `(70,7,7)`**. These are not identical to FluidAudio's 320 ms preset; compare matched context/precision where possible, not just similarly named model families. [S3, S5]

sherpa's `coreml` provider branch registers ONNX Runtime's Core ML EP on supported Apple builds, using the older flags API with flags zero; unsupported builds can fall back to CPU. ONNX Runtime has operator/shape restrictions and says ANE eligibility does not guarantee the entire model runs there. Thus a CPU path is straightforward to test, but **Unified INT8 ANE/GPU acceleration through sherpa is unconfirmed here**. Do not infer it from a `coreml` string, generic Apple support, or FluidAudio's converted encoder benchmarks. Verify packaged provider availability, partitioning/compute plan, load time and actual performance before selecting it. [S6, O1]

## Latency: what the numbers do and do not mean

FluidAudio defines theoretical streaming latency as `(chunk + right) × 80 ms`: Sendpoint's `(2 + 2) × 80 = 320 ms`. Chunk advance is 160 ms; left history is 5.6 s. These are audio-window requirements, **not measured key-release-to-text time**. Early windows use padding rather than waiting 5.6 s for left context. [F4, F5]

Both engines explicitly flush at end of input, so release does not need to wait for a full extra real-time lookahead interval. Release-to-visible-final consists of:

`hotkey delivery + TS/native dispatch + mic stop/drain + queued inference + tail inference + transcript/event delivery + JS render`.

Model download/load/first prediction adds a separate cold-start cost. Keep one prepared engine, reuse it across takes, and measure cold, warm, and restart separately. Cancelled work must settle before a new take can reuse the same manager; that can affect rapid-restart latency. [A2, A3, F2, S2; decomposition is analytical]

Upstream's 150-file LibriSpeech sweep reports **10× RTFx** for Core ML 320 ms, versus 27×/33×/54× for 640/1120/2080 ms, with different accuracy tradeoffs. RTFx is audio duration divided by processing time, not the time until the UI shows text; the benchmark is not a Sendpoint hotkey test and its results must not be substituted for an end-to-end p95. No equivalent measured Unified sherpa/Mac comparison was established. [F3, F6]

## RAM, downloads and idle behavior

- **Model bytes are not RAM.** FluidAudio's config documents roughly **565 MB INT8 vs 1.1 GB FP16 per encoder**, excluding the decoder/joint/vocabulary and runtime allocations. Its loader fetches only the selected streaming encoder and required decoder/joint/vocab, checks completeness and retries a bad load through `ModelHub.loadWithRecovery`. The current app's preliminary file-existence check alone is not an integrity check. Preserve download progress and recoverable errors in TS. [F1, F4, A2]
- Keep the existing native cache `~/Library/Application Support/FluidAudio/Models/parakeet-unified-en-0.6b` if keeping FluidAudio. A shell rewrite does not require re-downloading the weights if the native service resolves the same directory. Downloading a different context tier does require that tier's encoder. [A1, F1]
- GitHub's live `asr-models` release API returned **501,358,456 bytes** for sherpa's INT8 240 ms archive, **501,360,769** for 560 ms, **501,356,335** for 1120 ms, and **501,350,460** for offline. These are compressed network sizes, not installed sizes or resident memory. Each streaming archive has encoder/decoder/joiner/tokens and example/provenance files. A switch requires a separate native download/cache manager with progress, cancellation, partial-download recovery, safe extraction, pinned artifact identity and integrity validation; Core ML bundles cannot be reused as ONNX models. [S3, S5]
- No defensible numeric resident-memory or idle-CPU budget follows from those sizes. Measure host + WebKit child processes + sidecar if any, and report physical footprint and peak during first load as well as warmed steady state. Avoid comparing one process's RSS to another shell's entire process tree.
- Keep one engine, not one per web window. A sidecar adds a process but need not duplicate weights if it is the sole engine owner; a persistent warm engine retains model resources between takes. Stopping the mic and feed loop avoids recording/inference work at idle; web animation/timers and runtime/provider pools still need measurement. Unloading models saves resources at the cost of the next warm-up—leave that as a measured policy choice. [A2, A3, F2; measurement/policy recommendations]

## Required spike measurements / remaining unknowns

Run identical recorded PCM plus live hold/tap tests on the target Mac, same explicit `(70,2,2)` Core ML config and same warmed model for both shells. Record hardware, OS, app/package revisions, model artifact revision, power mode and process list.

1. Native monotonic timestamps at key-down/up, mic-first-buffer/stopped, first partial, feed drain, finish start/end, bridge send; JS receive/render acknowledgement. Calibrate clocks or return JS acknowledgements to the native clock rather than subtracting unrelated clock origins.
2. At least 30 warm takes across short/long speech and silence; report median/p95 release→final-render and first-audio→first-partial. Separate first launch, cached cold load, and rapid cancel/restart.
3. Process-tree idle CPU over a defined quiet interval, warm-idle/recording/peak physical footprint, model load time, bytes downloaded and installed. Check resources return to baseline after repeated cancels; test bridge reload and helper crash.
4. If sherpa remains a candidate, test its Unified CPU path first, then explicitly instrument Core ML provider availability and execution placement. Compare transcript parity/word error and latency on the same audio; preset/quantization differences must be disclosed.
5. Validate microphone consent and hardened/signature behavior in the **packaged** Tauri app/helper, not only a development binary. Confirm cancel never inserts text and no orphan worker holds the microphone.

No new app settings, state machines, shortcuts, benchmarks or dependencies were added for this research. It establishes available mechanisms and a recommended starting engine, not measured superiority of either shell.

## Primary sources

Application links are pinned to the baseline above; external source links are pinned where practical. Documentation/model cards and release-asset metadata were read live on the check date.

- **A1:** [README privacy](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/README.md#privacy), [Package.resolved](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Package.resolved), [Package.swift](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Package.swift).
- **A2:** [VoiceTranscriber.swift](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Sources/Sendpoint/Voice/VoiceTranscriber.swift).
- **A3:** [VoiceNoteService.swift](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Sources/Sendpoint/Voice/VoiceNoteService.swift).
- **A4:** [VoiceLevelMeter.swift](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Sources/Sendpoint/Voice/VoiceLevelMeter.swift).
- **A5:** [CaptureState.swift](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Sources/SendpointDomain/CaptureState.swift).
- **A6:** [VoiceMachine.swift](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Sources/SendpointDomain/VoiceMachine.swift).
- **F1:** [StreamingUnifiedAsrManager at current HEAD](https://github.com/FluidInference/FluidAudio/blob/8145085136df11758cc1303ab54d8e032c12bd41/Sources/FluidAudio/ASR/Parakeet/Unified/StreamingUnifiedAsrManager.swift).
- **F2:** [Same manager at Sendpoint's pinned revision](https://github.com/FluidInference/FluidAudio/blob/4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b/Sources/FluidAudio/ASR/Parakeet/Unified/StreamingUnifiedAsrManager.swift).
- **F3:** [FluidInference Unified Core ML model card](https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml/blob/main/README.md).
- **F4:** [UnifiedConfig and encoder-size comments](https://github.com/FluidInference/FluidAudio/blob/8145085136df11758cc1303ab54d8e032c12bd41/Sources/FluidAudio/ASR/Parakeet/Unified/UnifiedConfig.swift).
- **F5:** [UnifiedStreamingWindower](https://github.com/FluidInference/FluidAudio/blob/8145085136df11758cc1303ab54d8e032c12bd41/Sources/FluidAudio/ASR/Parakeet/Unified/UnifiedStreamingWindower.swift).
- **F6:** [Unified benchmark and methodology](https://github.com/FluidInference/FluidAudio/blob/8145085136df11758cc1303ab54d8e032c12bd41/Sources/FluidAudio/ASR/Parakeet/Unified/benchmark.md).
- **S1:** [sherpa changelog: 1.13.0 and 1.13.2](https://github.com/k2-fsa/sherpa-onnx/blob/040afe360a38e25daaa325ce8889abf93ea02609/CHANGELOG.md).
- **S2:** [Unified online recognizer implementation](https://github.com/k2-fsa/sherpa-onnx/blob/040afe360a38e25daaa325ce8889abf93ea02609/sherpa-onnx/csrc/online-recognizer-transducer-nemo-parakeet-unified-impl.h).
- **S3:** [Exact Unified ONNX streaming export/presets](https://github.com/k2-fsa/sherpa-onnx/blob/040afe360a38e25daaa325ce8889abf93ea02609/scripts/nemo/parakeet-unified-en-0.6b/export_onnx_streaming.py), [artifact packaging](https://github.com/k2-fsa/sherpa-onnx/blob/040afe360a38e25daaa325ce8889abf93ea02609/scripts/nemo/parakeet-unified-en-0.6b/run-streaming.sh).
- **S4:** [Official Rust streaming API example (Zipformer)](https://github.com/k2-fsa/sherpa-onnx/blob/040afe360a38e25daaa325ce8889abf93ea02609/rust-api-examples/examples/streaming_zipformer.rs).
- **S5:** [ASR model release assets](https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models), [release API used for exact archive sizes](https://api.github.com/repos/k2-fsa/sherpa-onnx/releases/tags/asr-models).
- **S6:** [sherpa provider session configuration](https://github.com/k2-fsa/sherpa-onnx/blob/040afe360a38e25daaa325ce8889abf93ea02609/sherpa-onnx/csrc/session.cc).
- **O1:** [ONNX Runtime Core ML EP requirements/options/operator support](https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html).
- **T1:** [Tauri mobile plugin development and desktop/mobile split](https://v2.tauri.app/develop/plugins/develop-mobile/).
- **T2:** [Tauri sidecar packaging and process APIs](https://v2.tauri.app/develop/sidecar/).
- **T3:** [Tauri frontend events versus ordered channels](https://v2.tauri.app/develop/calling-frontend/).
- **W1:** [Apple WKScriptMessageHandlerWithReply](https://developer.apple.com/documentation/webkit/wkscriptmessagehandlerwithreply).
- **W2:** [Apple callAsyncJavaScript](https://developer.apple.com/documentation/webkit/wkwebview/callasyncjavascript(_:arguments:in:in:completionhandler:)).
