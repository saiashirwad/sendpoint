# Sendpoint shell: Swift/AppKit + WKWebView versus Tauri 2

Research for [ticket #36](https://github.com/saiashirwad/sendpoint/issues/36), under [map #35](https://github.com/saiashirwad/sendpoint/issues/35). Sources inspected 2026-09-30. Sendpoint baseline: `3288cbacb3872f65845636e843319adc203b074c`. This is a research recommendation, not the map's final rewrite go/no-go or a measured performance result.

## Answer

**Use the existing Swift/AppKit executable hosting WKWebView for the first end-to-end rewrite spike.** Move UI **and domain/application logic** to TypeScript; retain Swift only for native capabilities and their resource lifetimes. Do not interpret this as keeping today's Swift controllers/state machines and merely replacing their views.

Tauri 2 is feasible, not disqualified by hotkey release events or panels. Its advantage is packaged web development, IPC, capabilities, and testing infrastructure. However, for this macOS-only app it adds Rust and an FFI boundary around Swift capabilities we still need: Accessibility, Parakeet Unified, native panel/focus behavior, Service Management, and Sparkle. Both candidates use the system WKWebView, so there is **no evidenced RAM/CPU/startup winner** here. Prefer the shorter integration path, then measure the actual always-on TypeScript architecture. [T1–T5, W1–W2, C1–C9]

The largest unresolved risk is not Rust overhead: **where does the always-running TypeScript state live when all panels are hidden, and what happens when that web process reloads, throttles, or dies?** Neither shell automatically supplies a persistent TypeScript backend outside the renderer. Tauri's documented core is Rust, and its docs recommend global state there—which differs from this map's scope. [T1]

## What exists today, and how each candidate supplies it

Local source links below are relative to this report; the baseline above identifies the exact revision inspected.

| Requirement | Existing Sendpoint behavior | Swift-hosted WKWebView | Tauri 2 |
|---|---|---|---|
| Non-activating floating voice panel | `CaptureWindows.makeVoicePanel` creates `.borderless, .nonactivatingPanel`, floating level, all-Spaces/fullscreen-auxiliary behavior; shows via `orderFrontRegardless`. Editor is intentionally different: an activating, resizable panel. [C1] | Retain AppKit panel construction and replace its content view with WKWebView (an NSView). Preserve separate voice/editor focus policies. [W2] | Use a custom native implementation or the third-party `tauri-nspanel` plugin. Its current 2.1 API provides panel classes, a builder, conversion from windows, and main-thread operations. This is a viable route, not a built-in guarantee of Sendpoint's exact behavior. [T4] |
| Return focus | Capture remembers the frontmost application at context creation and conditionally activates it on close; `SurfaceCoordinator` toggles accessory/regular activation. [C2] | Swift keeps opaque native app handles; TS decides whether/when to restore through an effect. Capture the target before presenting a panel. | Same native contract through a plugin/FFI; do not substitute merely focusing/hiding the Tauri window. Returning to an external app still needs native implementation. [C2, T2–T3] |
| Menu bar item | `NSStatusItem`, title/tooltip, flashes, and `NSMenu`; menu model is separate. [C3] | Retain native renderer, send a TS-produced menu description and return action IDs to TS. | Official tray/menu APIs are available from TS and Rust (`tray-icon` feature). Reproduce dynamic title/menu behavior rather than porting the Swift menu model into Rust. [T5] |
| Hold and tap global shortcuts | Carbon `RegisterEventHotKey`, separate pressed/released handlers; registrar routes voice and dictation pairs. [C4] | Retain Carbon registration as native service; forward ordered, timestamped edges to TS, which owns hold/tap decisions. | Official global-shortcut TS API explicitly has `state: 'Released' | 'Pressed'`, delivered on a channel. It can support hold gestures, not only taps. Alternatively retain Carbon via Swift to minimize behavior drift. Test repeats, conflicts, modifier-release order and layout semantics; API parity is not behavioral proof. [T6] |
| Selected text via Accessibility | Checks trust, reads focused AX element, selected text/range/bounds; distinguishes empty selection from unavailable; falls back to cached selection and targeted Cmd-C with clipboard restoration/revision checks. [C5] | Reuse native AX/clipboard primitives. Move policy/deadlines/selection workflow to TS; retain cancellation and target context checks at native calls. | A desktop Rust command/plugin can call the same Swift adapter through FFI. Tauri IPC permissions do not grant macOS Accessibility consent. A clipboard plugin alone is not equivalent to this feature. [C5, T2–T3] |
| Microphone permission and recording | AVFoundation authorization request/status; native microphone boundary; `NSMicrophoneUsageDescription` in app plist. [C6] | Keep native AVFoundation access and audio capture; TS commands start/stop/cancel. No browser `getUserMedia` requirement. | Same Swift implementation via desktop plugin; carry usage description and entitlements into the Tauri bundle. Choosing browser media capture would introduce a different permission/capture path for no demonstrated benefit. [C6, T2–T3] |
| Parakeet Unified | `LocalStreamingTranscriber` actor owns FluidAudio `StreamingUnifiedAsrManager`, local model cache, frames, partial callbacks, take UUIDs and teardown. [C7] | Keep the model/audio engine native; expose start/feed ownership internally, stop/abandon, progress/partial/final events externally. TS owns user workflow, not PCM processing. | Static Swift package linked into Rust; Rust command forwards requests and a channel returns typed events. Async Swift actors need explicit completion/callback and cancellation adapters; swift-rs is not an async actor bridge. [T2–T3, T7] |
| Launch at login | `SMAppService.mainApp.register/unregister/status`. [C8] | Preserve these native calls; move desired-setting/error UI state into TS. | Official autostart plugin works, but inspected implementation uses LaunchAgent or AppleScript, **not** existing SMAppService semantics. For parity, bridge Swift Service Management instead. [T8] |
| Sparkle | `SPUStandardUpdaterController`, signed appcast, public key, signed-feed and pre-extraction checks, custom packaging/signing. [C9] | Retain framework, native updater object, feed and release machinery. UI can invoke checks through the bridge. | Integrate Sparkle through Swift and custom bundle/framework signing. Official Tauri updater is a **different updater**, with JSON endpoints and signed `.app.tar.gz` artifacts, not a drop-in reader of Sparkle's appcast. Do not silently migrate update systems. [T9, S1] |
| Ad-hoc builds | Release script forces identity `-`, skips notarization; build script handles nested Sparkle code and alternate library-validation entitlement. [C9] | Preserve pipeline, adding built web assets. | Supported: `bundle.macOS.signingIdentity: "-"`. Still requires user approval for downloaded unnotarized apps; does not solve stable Accessibility identity. Sparkle embedding/signing still needs validation. [T10, C9, S1] |

**Panel test contract:** retain target-app keyboard focus throughout voice capture, permit intended mouse interaction without activating the app, support full-screen Spaces and multiple displays, activate editor only on explicit transition, and restore focus according to the setting on save/dismiss. The existing code establishes intent, not proof that WKWebView input/focus behavior will match. Test IME, text selection, Escape and Cmd-Return in the embedded editor too. [C1–C2; proposed acceptance tests]

## Calling Swift: actual integration paths

### Swift shell

Proposed path: `TypeScript → window.webkit.messageHandlers.native.postMessage(envelope) → WKScriptMessageHandlerWithReply → Swift capability`, with Swift-to-TS events via a fixed `callAsyncJavaScript` function and its **arguments dictionary**, not string interpolation. WebKit's header documents promise-returning message calls, asynchronous replies, allowed serializable values, and a reply handler called at most once. `callAsyncJavaScript` can pass structured arguments and await returned promises. Both APIs are available from macOS 11, below Sendpoint's macOS 14 floor. [W1–W2, C10]

This is a small bridge to build, not a framework provided for free: define a versioned envelope, runtime validation, explicit errors, request IDs, session/take IDs, monotonic event sequence, cancel commands, bounded event buffering and one teardown owner. Remove handlers and cancel native work when the web context disappears. Do not expose generic filesystem, shell, arbitrary JavaScript evaluation or unrestricted AX calls to web content. Restrict navigation/frames to bundled content (loopback dev URL only in development), use a restrictive CSP, and treat captured text as data. These are design requirements, not claims that WKWebView automatically enforces the desired policy.

### Tauri shell

Proposed path: `TypeScript invoke → Rust desktop plugin/command → Swift static package through swift-rs/C ABI → native APIs`; reverse path: Swift completion callback → Rust → Tauri channel → TS. Official plugin docs explicitly describe the generated Swift package as **iOS** support; the desktop implementation is Rust. Do not mistake the mobile Swift plugin tutorial for a ready-made macOS Swift bridge. [T2]

The swift-rs maintainer documents static Swift packages, Cargo `build.rs`/`SwiftLinker`, global `@_cdecl` exports and unsafe Rust calls. Strings/data use wrappers; Swift structs/generics are not freely passed across the boundary. Keep this FFI narrow: opaque handles and serialized messages, explicit ownership/release, completion callbacks, main-thread dispatch for AppKit and cancellation IDs. The integration of Sendpoint's exact Swift 6.2 + FluidAudio + Sparkle dependency graph was **not compiled here**. [T3, C10]

Tauri channels are documented as ordered and optimized for streaming; its global event bus is not designed for low latency/high throughput. Use channels for transcription, not broadcast events or raw audio. PCM stays entirely in Swift in both candidates; only progress, meter values and transcripts cross the bridge. [T7; recommendation]

## TypeScript ownership: a spike gate for either shell

Proposed initial arrangement: one retained owner web context runs the pure TS machines, store, composer and templates; surface contexts send intents and render snapshots, not independent copies of application state. Native code is a capability executor plus safety/resource cleanup. The owner must survive ordinary window closes. This is a proposal to validate, not an assurance that a hidden WKWebView behaves as a daemon. Tauri's core/webview process split does not eliminate this issue. [T1]

Require a ready/epoch handshake before delivering native events. A reload changes the epoch, invalidates pending replies and cancels recordings; restoring durable state must not replay irreversible effects. On renderer loss, native safety teardown stops the mic and releases tasks even if JS cannot send a cancel. TS still owns product decisions; native resource lifetimes and emergency cleanup are not duplicated business state machines. Hidden-owner wake latency, throttling and crash recovery are decisive tests. If this fails, examine a dedicated JS runtime as a **new architectural decision**, not an unannounced move of app logic back into Swift/Rust.

## Size, idle RAM/CPU and cold start

**No comparable Sendpoint measurements were made in this research.** No fabricated “Tauri is 10 MB / WKWebView is 30 MB” estimates: app size is not renderer memory, and an empty hello-world is not the proposed retained-TS-owner app.

| Metric | Confirmed facts | Decision-relevant unknown |
|---|---|---|
| Download / installed size | Tauri uses OS webview libraries rather than bundling them; on macOS that is WKWebView. Direct Swift hosting also uses that framework. Tauri documents release stripping/LTO/unused-command pruning. Sendpoint already includes FluidAudio and Sparkle, with models downloaded into Application Support. [T1, T11, C7, C9–C10] | Actual stripped same-architecture bundles, compressed artifacts and model cache measured separately. Rust adds code/dependencies but total delta is not established. |
| Idle memory | Both have native host and WebKit-side costs; Tauri explicitly documents multiple processes. Model-ready state differs from unloaded state. [T1, C7] | Whole-app footprint including attributable WebContent/GPU/network processes, after all panels close and after repeated capture cycles. Host-only RSS is misleading. |
| Idle CPU | No cited source establishes an apples-to-apples advantage. JS timers, event delivery and model lifecycle are implementation-dependent. | Long-window CPU/wakeups with hidden owner, microphone off, UI animation paused; unloaded and warm-model variants. |
| Cold start / first capture | Web content and native/model readiness are separate milestones; existing transcriber loads and primes models. [C7] | Launch-to-hotkey-ready, launch-to-TS-ready, first overlay paint and first transcript; warm-cache relaunch is not disk-cold boot. |

### Reproducible measurement plan (not executed)

1. Build release versions on the same Mac/OS/architecture and fixed dependency revisions, no dev server/inspector. Compare current Sendpoint, Swift/WK host and (only if needed to decide) Tauri host with identical TS assets and model configuration. Record hardware, signing mode and power state.
2. Measure `.app` logical bytes, disk allocation and compressed release bytes; list framework/assets contributions. Exclude model download from shell size but report it separately.
3. Run at least 20 launches after full termination, distinguish warm filesystem cache from first launch after reboot. Timestamp native entry, hotkey registration, TS ready and first rendered-frame acknowledgment. Report median/p95 and raw samples.
4. Sample five minutes of idle after settling: no UI, overlay visible, all surfaces closed again; do each with model unloaded and warmed. Attribute helper processes rather than counting just the host or all system WebKit processes. Report host/helper RSS separately and physical footprint when available; RSS sum can double-count shared pages. CPU: accumulated CPU-time delta divided by wall time, summed across attributable processes; report wakeups separately.
5. Timestamp hotkey edge → AX result → mic ready → native first partial → JS receipt → rendered transcript. Do not subtract uncalibrated JS/native clocks. Use host acknowledgments or clock calibration. Repeat short tap, long hold and release while a window opens; report dropped/reordered events.
6. Repeat after prolonged hidden idle, sleep/wake, web reload/crash, permission denial and 100 capture/cancel cycles. Failure to retain/recover TS ownership or to stop the mic is a correctness failure regardless of speed.

The map must set acceptable regression budgets before interpreting these measurements. This ticket picks the lowest-integration-risk shell for the spike; it does not approve shipping the rewrite.

## Agent-friendliness and developer loop

| Concern | Swift + WKWebView | Tauri 2 |
|---|---|---|
| UI changes | Proposed Vite dev URL loaded by WKWebView using `loadRequest`; HMR can run without rebuilding Swift. Enable `isInspectable` in debug. Need a script to launch dev server + host and bundle production assets. [W2] | Documented `beforeDevCommand`, `devUrl`, `tauri dev`; frontend updates without native rebuild, Rust changes automatically rebuild/restart. Stronger off-the-shelf loop. [T12] |
| Native changes | Existing Swift package/build tools; one native language and existing APIs. [C10] | Cargo plus SwiftPM and TS toolchains. Swift package watch/relink behavior needs explicit verification; documented watcher is Rust/workspace oriented. [T3, T12] |
| Headless logic tests | Proposed pure TS tests with fake native adapter and deterministic clocks, independent of WebKit. Swift boundary tests stay native. | Same TS tests; Tauri additionally provides mock-runtime/unit/integration tests without native webview libraries. [T13] |
| Web UI tests | Proposed browser-based fixture tests/screenshots plus actual WKWebView snapshot/integration tests; WebKit exposes `takeSnapshot`. Browser success does not prove AppKit focus or AX. [W2] | Same fixture approach; current Tauri docs link WebdriverIO support including macOS. Official direct `tauri-driver` limitations must not be generalized to “no macOS testing.” WebdriverIO offers embedded/CrabNebula providers. These still need validation for our NSPanel and native flows. [T13–T14] |
| Full native interaction | Requires a real logged-in macOS session and controlled permission fixtures for panel/focus/AX/mic checks; not replaced by TS unit tests. | Same native test burden; mocks do not execute native webview libraries. Keep any embedded automation plugin test-only. [T13–T14; recommendation] |

Assessment: most agent-friendly work comes from moving deterministic application logic and UI into TS with fixture adapters, not from Tauri specifically. Tauri wins scaffolding; Swift hosting wins minimizing unfamiliar native/FFI/debugging layers for this repo. This is an engineering judgment, not a measured agent productivity claim.

## Decision and unresolved work

- **Choose Swift/AppKit + WKWebView for the map's hold-⌘E → AX → Parakeet Unified → web overlay spike.** Keep Sparkle, Carbon, Service Management and native audio boundaries; move application policy/state into TS.
- **Keep Tauri as a viable fallback**, especially if cross-platform goals or turnkey tooling become more important. It supports release edges, tray UI, ad-hoc signing and community NSPanel integration; it does not remove the Swift integration need under this scope.
- **Not confirmed:** comparative resource numbers, hidden-owner reliability, exact webview panel focus/input parity, Swift/FluidAudio/Sparkle linking inside Tauri, full Sparkle upgrade across a shell change, or actual macOS E2E harness behavior. Do not claim those have passed.
- **Before rewrite go/no-go:** run the functional/performance spike above, choose TS runtime ownership/recovery, verify signed bundle permissions/update continuity and preserve existing state-machine cancellation/stale-result invariants. Migration order and screenshot tooling remain map decisions, not silently settled here.

## Primary sources

### Sendpoint at the baseline revision

- **C1:** [CaptureWindows.swift](../../Sources/Sendpoint/Capture/CaptureWindows.swift), especially `makeVoicePanel`, `makeEditorPanel`, `presentVoice`, `presentEditor`.
- **C2:** [CaptureController.swift](../../Sources/Sendpoint/Capture/CaptureController.swift), `beginContext` and `.close`; [SurfaceCoordinator.swift](../../Sources/Sendpoint/App/SurfaceCoordinator.swift), activation and surface effects.
- **C3:** [StatusItemController.swift](../../Sources/Sendpoint/App/StatusItemController.swift).
- **C4:** [HotKeyCenter.swift](../../Sources/Sendpoint/Input/HotKeyCenter.swift) and [HotKeyRegistrar.swift](../../Sources/Sendpoint/Input/HotKeyRegistrar.swift).
- **C5:** [SelectionCapture.swift](../../Sources/Sendpoint/Capture/SelectionCapture.swift).
- **C6:** [PermissionCheck.swift](../../Sources/Sendpoint/Platform/PermissionCheck.swift), [Microphone.swift](../../Sources/Sendpoint/Voice/Microphone.swift), [Info.plist](../../Resources/Info.plist).
- **C7:** [VoiceTranscriber.swift](../../Sources/Sendpoint/Voice/VoiceTranscriber.swift), `LocalVoiceModelFiles` and `LocalStreamingTranscriber`.
- **C8:** [AppSettings.swift](../../Sources/Sendpoint/Settings/AppSettings.swift), `setLaunchAtLogin`/SMAppService calls.
- **C9:** [UpdateController.swift](../../Sources/Sendpoint/App/UpdateController.swift), [build.sh](../../build.sh), [release.sh](../../release.sh), [Info.plist](../../Resources/Info.plist).
- **C10:** [Package.swift](../../Package.swift): Swift 6.2, macOS 14, FluidAudio, Sparkle and tests.

### Framework/tool maintainers

- **W1:** Apple/WebKit [WKScriptMessageHandlerWithReply.h](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKScriptMessageHandlerWithReply.h): asynchronous promise/reply contract and availability. Apple documentation pages returned no readable content; the owning project's API headers supplied the evidence instead.
- **W2:** Apple/WebKit [WKWebView.h](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebView.h): NSView superclass, loading, argument-based JS invocation, snapshots, inspector and availability. Only APIs available at macOS 14 or earlier are proposed above.
- **T1:** Tauri [Process Model](https://v2.tauri.app/concept/process-model/).
- **T2:** Tauri [Plugin Development](https://v2.tauri.app/develop/plugins/).
- **T3:** swift-rs maintainer [README](https://github.com/Brendonovich/swift-rs/blob/main/README.md).
- **T4:** tauri-nspanel maintainer [2.1 README](https://github.com/ahkohd/tauri-nspanel/blob/v2.1/README.md). Third-party plugin, primary evidence for its own API, not an official Tauri guarantee.
- **T5:** Tauri [System Tray](https://v2.tauri.app/learn/system-tray/).
- **T6:** Tauri [global-shortcut TypeScript source](https://github.com/tauri-apps/plugins-workspace/blob/v2/plugins/global-shortcut/guest-js/index.ts), `ShortcutEvent`/`register`; [plugin permissions](https://v2.tauri.app/plugin/global-shortcut/).
- **T7:** Tauri [Calling the Frontend from Rust](https://v2.tauri.app/develop/calling-frontend/), events versus channels.
- **T8:** Tauri [autostart source](https://github.com/tauri-apps/plugins-workspace/blob/v2/plugins/autostart/src/lib.rs), `MacosLauncher` and `Builder`.
- **T9:** Tauri [Updater](https://v2.tauri.app/plugin/updater/), signing, artifact format and JSON protocol.
- **T10:** Tauri [macOS Code Signing](https://v2.tauri.app/distribute/sign/macos/), ad-hoc section.
- **T11:** Tauri [App Size](https://v2.tauri.app/concept/size/).
- **T12:** Tauri [Develop](https://v2.tauri.app/develop/), dev URL, HMR, watcher and inspector.
- **T13:** Tauri [Tests](https://v2.tauri.app/develop/tests/), mock runtime and current macOS E2E distinction.
- **T14:** WebdriverIO [Tauri testing](https://webdriver.io/docs/desktop-testing/tauri/), service/provider options and embedded plugin.
- **S1:** Sparkle [Basic Setup](https://sparkle-project.org/documentation/): framework embedding, runpaths, library validation, EdDSA and appcasts.

External branch/doc links are moving references, inspected on the date above. No benchmark binaries or throwaway spikes were produced; no application code changed.
