# Odin for agent-written Sendpoint: testing, native boundaries, and shipping

Research for [#50](https://github.com/saiashirwad/sendpoint/issues/50), part of [map #35](https://github.com/saiashirwad/sendpoint/issues/35). Investigated 2026-09-30; no application code changed.

## Decision

**The user has chosen a ground-up Odin + native AppKit rewrite.** This report supersedes the map's original web/Swift framing for this ticket: Odin owns domain state, effects, native controllers and AppKit UI. No WKWebView, web UI, Electron/Tauri or Swift layer is proposed. Odin can express the required state machines, tests and ordinary macOS distribution pipeline. The implementation should proceed with explicit ownership, a small audited AppKit binding layer, and native integration gates—not an unproven assumption that agents inherently write Odin better than other languages.

The strongest positive evidence is executable: an agent wrote a CaptureState voice/selection slice and six deterministic tests; it compiles and runs, rejects stale contexts, cancels a fake retained handle, and tears down idempotently. A separate Odin executable calls Apple's Objective-C Foundation bindings, lives in an ad-hoc-signed `.app`, and stops at an Odin source breakpoint in LLDB. The principal risk is **ownership and platform integration**, not whether a reducer can be expressed. These experiments do not measure UI quality, mic/AX behavior, STT, or application latency. [E1]

A significant surprise: **`vendor:darwin/Foundation` is now a compile-time error directing you to `core:sys/darwin/Foundation`**. And that `Foundation` package contains AppKit bindings such as NSApplication and NSPanel. Agents using old examples can make either the wrong import or the wrong claim that no AppKit bindings exist. [S2–S4]

## Evidence and reproducibility

Local environment: Apple M5, arm64, macOS 27.0 (26A428); already-installed Homebrew Odin `dev-2026-09:a2fb372b7`, full source revision `a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924`. Sendpoint source read at `3288cbacb3872f65845636e843319adc203b074c`. No install was necessary.

Run from repository root:

```sh
python3 docs/research/odin-agents/run.py
```

The script creates only scratch outputs, runs each timing command five times, executes tests, creates/signs/verifies a research bundle, and invokes LLDB. It does not install or launch Sendpoint, contact the notary service, or access signing credentials. `codesign --sign -` is an ad-hoc signature. The bundle probe runs directly via its executable, **not** via Finder/LaunchServices; it has no window or event loop. Committed [results.json](odin-agents/results.json) retains command results and all five samples. [E1]

| Probe | Median wall time, five builds/runs |
|---|---:|
| `odin check capture -no-entry-point` | 0.0778 s |
| `odin test capture` including compile/link/run | 0.7009 s |
| Foundation probe `odin build native -debug` | 0.5115 s |
| Foundation probe `odin build native -o:speed` | 1.5314 s |

These are tiny repeated builds on a busy developer machine, not cold-cache or production-project benchmarks. The final test execution itself was 120 µs; claiming that as build time would be misleading. Debug executable: 430,808 bytes; speed-optimized executable: 191,040 bytes, excluding dSYM, system frameworks, Sparkle, UI assets and speech models. No comparison to Sendpoint's Swift build or runtime memory was performed. [E1]

## How well do agents write Odin?

### What we can and cannot establish

There is now an Odin-specific paper, **OdinEval** (August 2026). It reports 168 localized repository repairs, six models, and complete-resolution rates of 45.8–66.7%. Crucially, its reported experiment is *one patch, no compiler/test feedback to the model*, not the interactive tool-using development loop used here. It does not establish Odin-versus-Swift productivity or UI-building performance. Its text also mixes completed-result language with future-tense artifact-release and protocol details; I did not locate/execute its frozen artifacts in this investigation. Treat these as **authors' reported results, not independently reproduced agent rankings**. [S10]

No source examined discloses how many Odin tokens current commercial models were trained on. Public repository availability is not training-set membership. Claims that an agent must be bad at Odin because training data is sparse are hypotheses, not measured facts here. Conversely, this session's successful small spike is one agent working with official source and compiler feedback, not a general benchmark.

### What happened in this session

- The first capture test compile failed on a composite literal directly in a `for` header. The diagnostic pointed at the comma and said `Expected 1 expression`; moving the literal into a named local fixed it. The second compile passed all six tests. This is evidence of a short syntax-feedback loop, not first-shot correctness. [E1; retained failure described here]
- A deliberately incomplete enum switch produces `Unhandled switch case: Voice` and suggests `#partial switch`. File/line positions are actionable. Do **not** accept the suggested partial switch merely to silence a missing transition: exhaustiveness is the desired safety property. The script asserts this negative probe fails. [E1]
- The native Foundation probe compiled on the first attempt after reading actual binding declarations. Guessing Swift-like import and method spellings was unnecessary. [E1, S3]
- Debugging initially failed to resolve a source breakpoint because the executable had been copied into a bundle but its generated dSYM was left at the original path. Explicit `target symbols add <path>/native.dSYM` fixed it; LLDB then stopped in `main.odin` and displayed the pool pointer. Keep symbols with the correct binary, including in an agent's packaging loop. [E1]

### Likely mistakes to review explicitly

These are language/source-derived risk areas, **not frequency estimates**. [S1–S4]

1. **Version drift:** stale `vendor:darwin/Foundation`, deprecated syntax, guessed package APIs. Pin the compiler and read its own `core` sources before writing bindings.
2. **Swift/Go syntax transfer:** enum-associated data belongs in distinct structs inside a tagged union; pointers are `^T`, dereference is `p^`, immutable procedure arguments require a local copy before modification. Use `union #no_nil` where there must not be an implicit nil state.
3. **Ownership disguised as value copying:** strings and slices copy descriptors, not the pointed-to bytes. A transcript returned from a temporary allocator or Objective-C string buffer cannot simply be stored forever. Clone into an explicitly owned session arena or transfer an owned message; free it at a documented point. `defer` is scope-exit cleanup, not ARC, and is not a substitute for async lifetime design.
4. **FFI calling convention/context:** ordinary Odin procedures carry implicit context; foreign callbacks need the correct C ABI and an established Odin context before using context-dependent services. A stored proc pointer does not provide Swift-style captured closure lifetime management.
5. **Threading:** no Swift actor isolation or Sendable checking protects this design. Serialize state updates, retain and cancel handles, prevent callback-after-free, and marshal AppKit work to the main thread.
6. **ObjC assumptions:** message selectors are strings at the low-level boundary. Typed wrappers do not prove selector availability or correct ownership/ABI. Verify BOOL, integer widths, struct returns, delegate lifetime, and OS availability against Apple headers; never replace them casually with an untyped `objc_msgSend` cast.

Recommended agent contract: pin Odin + OLS revisions; give the agent the overview, relevant local package declarations, and this tested reducer skeleton; require check/test after small edits; prohibit ownership-free `string` storage from external callbacks; review native boundaries independently. Compiler success cannot detect a use-after-free caused by a borrowed asynchronous result.

## Development loop

### Tests

`@(test)` procedures take `^testing.T`; `odin test <package>` compiles and runs them. `core:testing` supplies expectations, seed controls, timeout support, and allocator tracking for leaks/bad frees. The default runner can parallelize tests, so fake boundary state should be per test rather than global. For reproducibility this spike uses one thread and seed 42. Imported-package tests require `-all-packages`; do not mistake one package's success for a whole project suite. Memory tracking covers allocations through the tracked allocator, not arbitrary Objective-C/C allocations. [S5]

Use `odin check` for cheap diagnostics, `odin test` for behavior, and `odin build -debug` for LLDB. The installed compiler also exposes `-json-errors`, `-error-pos-style:unix`, `-vet`, optimization flags, and timing exports. This makes an agent's shell-driven loop quite practical even without an editor LSP. [S6, E1]

### OLS

OLS advertises completion, references, rename, navigation, hover, semantic tokens, signature help, and odinfmt integration. It explicitly calls itself early development and targets Odin master. Its configuration can pin `odin_command`, declare collections and Darwin/arm64 profiles, and set explicit `checker_path` entries. The README labels workspace-wide checking experimental and recommends explicit checker paths instead. Prefer the actual compiler as the final arbiter; OLS is an editing aid, not a replacement for execution. OLS was source-reviewed, **not installed or benchmarked** here. [S7]

### Hot reload

Karl Zylinski's real template supports macOS: a stable executable loads a game dylib, recompiles to a temporary filename, then renames it into place; game memory survives the reload. Release builds import the code normally and do not use the reload DLL. Its documented macOS debugger is CodeLLDB. This is concrete evidence that Odin supports a useful development reload architecture—not evidence of automatic SwiftUI-style view previews or arbitrary state-layout migration. [S8]

For Sendpoint, make reload a *development-only* feature if needed: the stable owner must cancel/quiesce callbacks before unloading their code, invalidate old function pointers, and reject or migrate incompatible state layouts. ObjC delegate methods registered with pointers into an unloaded dylib are particularly dangerous. Native event loops, microphone callbacks, STT buffers and accessibility operations make this less trivial than replacing a pure draw/update function. Prefer fast restart plus deterministic replay first. No hot-reload template was run here, and no release should need unsigned mutable dylibs or disabled library validation to enable it. [Design inference from S8, S11]

## CaptureState translated: what carries over

See [capture.odin](odin-agents/capture/capture.odin) and [capture_test.odin](odin-agents/capture/capture_test.odin). The source being translated is [CaptureState.swift at the inspected revision](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Sources/SendpointDomain/CaptureState.swift).

```odin
Idle :: struct {}
Torn_Down :: struct {}
Lifecycle :: union #no_nil {Idle, Session, Torn_Down}
Capture_State :: struct { lifecycle: Lifecycle }

update :: proc(state: ^Capture_State, event: Event) -> Effects {
    if _, dead := state.lifecycle.(Torn_Down); dead { return {} }
    // Exhaustive event/type switches; effects returned as plain data.
    // Teardown sets Torn_Down and emits Close exactly once.
    // Completion events compare the complete Capture_Context.
    // ... see the compiled source for the actual implementation.
}
```

This is deliberately a **voice-selection rendezvous slice**, not a complete replacement for the 497-line Swift file. It preserves begin/read/start/show, recording-before-selection and selection-before-recording, finish-before-start closure, release waiting for selection, invalid-event rejection, complete-context matching, dismiss and terminal teardown. IDs are u64 stand-ins, not production UUID serialization. Transcript reception ends at `Editing` to keep the example independent of persistence; Swift instead constructs a save request. Omitted: text capture, hold/tap key gesture state, dictation insertion, destination picker, save/retry outcomes, partial transcripts and failure timers. A real port must translate these and run parity traces against Swift before claiming equivalence.

| Repository rule | Odin form in the example / required production extension |
|---|---|
| Closed workflow | `union #no_nil` of payload structs; enum for effects without payloads; exhaustive switches |
| One event transition | `update(^Capture_State, Event) -> Effects`; no UI/platform access |
| Pure data transforms | Reducer reads event/state only; bounded effect array needs no allocator |
| Idempotent teardown | Terminal union variant; one `Close`; every later event ignored |
| Inject small boundaries | `Boundary` stores proc pointer plus `userdata`; fake counts cancel calls |
| One lifecycle owner | `Owner` retains an opaque handle and clears it before cancellation |
| Cancellation + stale result | Close cancels once; late events cannot revive idle/torn-down state; compare stack, note and timestamp |
| Deterministic tests | Six tests cover both arrival orders, stale contexts, invalid transitions, early finish, cancellation and teardown |

The small owner tests handle cancellation, not real asynchronous resource reclamation. Production needs the current controller's event queue/drain pattern, a handle per work kind, cancellation checks around the external call, full-context validation when dequeuing, and an acknowledgement/join contract before freeing callback userdata. No callback may recursively call `send`; enqueue it. Add a generation token if contexts can ever be reused. Test teardown during an in-flight call, synchronous completion during launch, and completion after a newer session. Keep the controller alive until native callbacks are quiescent. The example borrows literal text; it intentionally does not pretend to solve production transcript storage ownership. [E1, S1, Sendpoint source above]

Swift Observation itself is Swift-specific and is not supplied by Odin. For the chosen rewrite, Odin owns the state and an explicit main-thread render/update procedure maps state snapshots into retained AppKit controls. Delegate and target/action callbacks enqueue domain events; they do not mutate model fields. Do not recreate Swift Observation as a framework: start with explicit change application, updating only affected control values/layout and calling `setNeedsDisplay:` for custom drawing.

## Native macOS: more support than the package names suggest

At the inspected revision, `core:sys/darwin` includes CoreFoundation, CoreGraphics, Foundation and Security packages plus Darwin system-call/process/synchronization declarations. `core:sys/darwin/Foundation/objc.odin` links Foundation and requires Cocoa on macOS, exposes ObjC runtime declarations, and the package includes NSApplication, NSPanel, NSMenu and many other AppKit wrappers. `vendor:darwin` retains graphics/media-oriented packages including Metal, MetalKit, QuartzCore and CoreVideo; its Foundation directory is the migration-error stub. [S2–S4]

This is enough to avoid writing all Cocoa interop from scratch, but **not a complete AppKit UI toolkit**. In particular, NSPanel's file declares only its type and a modal-response enum; inherited window operations still need correctly typed calls. No NSTextField/NSTextView/NSVisualEffectView source files were found in this Foundation directory, and no `AXUIElement` or `SPUStandardUpdater` declarations were found in the Darwin core search. These are missing bindings in this checkout, not missing OS capabilities. Implement narrow audited Odin wrappers, following existing `@(objc_class=...)` and `intrinsics.objc_send` patterns. Use C-callable Objective-C glue only where callback/block or ownership complexity warrants it; no Swift host is required. [S2–S4]

The scope-change follow-up added a **pure Odin AppKit construction spike**: [appkit/main.odin](odin-agents/appkit/main.odin), [observed output](odin-agents/appkit-result.txt). It creates NSApplication, an accessory-policy nonactivating NSPanel, an NSVisualEffectView content view, an NSTextField and an NSTextView; sets text, attaches the controls, and releases owned objects. It compiled and executed successfully without showing a window or entering the event loop. Run `odin run docs/research/odin-agents/appkit -out:<scratch-path>` to repeat. This validates basic missing-binding interop, not focus, input methods, material appearance, accessibility or drawing correctness.

The first AppKit compile exposed two concrete agent errors: `objc_send` requires typed arguments (`NS.BOOL(false)`, not untyped `NS.NO`), and a guessed `String_stringWithUTF8String` wrapper did not exist (the source-provided `MakeConstantString` was used instead). Both were fixed before the successful run. This strengthens the recommendation to compile bindings immediately rather than trust plausible Cocoa spellings.

For actual native screens: keep NSTextView for editable text/selection/IME and NSTextField for labels/fields; use NSView subclasses for composition and Core Graphics/Core Text only for custom visuals. Register subclass/delegate callbacks with exact Objective-C type encodings and C calling conventions; keep their code and userdata alive. Use NSVisualEffectView's documented material/blending/state configuration rather than assuming its defaults produce the intended appearance. Core Text coverage and a custom `drawRect:` callback were not tested here. Speech remains a distinct blocker to investigate: the existing Swift FluidAudio API is not magically callable from Odin without Swift. Preserving the exact Parakeet model while eliminating Swift requires an independently verified C-compatible inference integration; this report does not silently substitute another model or claim that work is solved.

## How an Odin app ships

### Bundle and local signing: tested

Build the Mach-O executable and assemble:

```text
OdinProbe.app/
  Contents/Info.plist
  Contents/MacOS/OdinProbe
  Contents/Resources/
  Contents/Frameworks/       # when embedding Sparkle or another framework
```

Set executable, stable bundle identifier, APPL package type, version keys, and menu-bar-app `LSUIElement` as appropriate. Production also needs icons, minimum OS version, mic usage description, correct entitlements and resources. The research script generates its plist, signs with `codesign --force --sign -`, verifies with `codesign --verify --strict`, and the executable reads the expected bundle ID via NSBundle. This proves Odin can occupy an ordinary macOS bundle; it does **not** prove Gatekeeper distribution, permission continuity, LaunchServices behavior or notarization. [E1, S9]

### Distribution signing and notarization: documented, not performed

The language does not change Apple's pipeline. Build each required architecture (Odin has Darwin target/minimum-OS flags), combine compatible slices if shipping universal, embed frameworks preserving symlinks, verify load commands/rpaths, and sign nested code **inside out**, with the enclosing app last. Do not use `codesign --deep` as a shortcut for correct production signing; it is useful for recursive verification. Use Developer ID Application, hardened runtime, secure timestamp and only required entitlements; ad-hoc signing is not a substitute. Archive symbols per release. [S6, S9, S11]

Illustrative tail of a release pipeline, after correctly signing all nested code and the app (not executed here):

```sh
ditto -c -k --keepParent Sendpoint.app Sendpoint.zip
xcrun notarytool submit Sendpoint.zip --keychain-profile sendpoint-notary --wait
# Require Accepted; download and inspect the submission log, even on success.
xcrun stapler staple Sendpoint.app
xcrun stapler validate Sendpoint.app
# Recreate the distribution ZIP with the stapled app, then sign that final update archive.
ditto -c -k --keepParent Sendpoint.app Sendpoint-notarized.zip
```

Apple accepts ZIP/DMG/pkg submissions, uses `notarytool` rather than obsolete `altool`, and says ZIPs cannot themselves be stapled: staple the app and recreate the ZIP. Test the final download on a clean machine, including offline ticket verification, permissions, actual update replacement and relaunch. This research did not use credentials or publish a release. Existing Sendpoint publication must still go through its prescribed `release.sh`, not this illustrative sequence. [S12]

### Sparkle: feasible; prefer an audited shim

Sparkle documents programmatic integration for non-Apple UI toolkits with an Objective-C++ example. The essential object is `SPUStandardUpdaterController`, initialized with `initWithStartingUpdater:updaterDelegate:userDriverDelegate:`; retain it, call on the main thread, and wire `checkForUpdates:` plus menu validation. Therefore an Odin host can either declare a small typed ObjC wrapper using the existing runtime facilities or call a tiny ARC Objective-C shim through C. **Recommendation for the Odin-only host:** implement the few needed typed Objective-C calls in Odin, retaining the updater for application lifetime; add a tiny ARC Objective-C C-ABI shim only if delegate/observer complexity justifies it. No Swift layer or full generated Sparkle binding is necessary. The shim option makes delegate/observer lifetimes easier to audit but is optional, not a proposed app host. No Odin Sparkle end-to-end update was built here. [S3, S11]

Shipping details matter more than initialization: embed `Sparkle.framework` with its required helpers and symlinks; link it and add a self-contained `@executable_path/../Frameworks` rpath; set `SUFeedURL`, `SUPublicEDKey`, and increasing `CFBundleVersion`; serve over HTTPS; sign the final update with Sparkle's Ed25519 tools and generate its appcast. Apple code signing and Sparkle archive signatures are different checks. Test old-to-new updates with real signed/notarized builds. [S11]

For local ad-hoc development, Sparkle specifically warns that hardened-runtime library validation may reject loading its framework; use an appropriate development signature or a **debug-only** library-validation exception. Do not carry that workaround into the distribution build. Alternatives are manual signed/notarized downloads (less integration, no automatic updates) or a custom updater (far more security/rollback/relaunch work, not recommended). [S11, design recommendation]

## Next decision gate and remaining unknowns

The language/UI decision is now made by the user: **proceed with Odin + AppKit**. The following are implementation acceptance gates, not a request to reconsider web or Swift alternatives:

1. Establish an Odin agent task suite with behavior specs and hidden tests; measure correction cycles, human review time and memory/lifecycle defects. Include native binding work, not only reducers. Current evidence does not justify promising an agent-productivity improvement.
2. Complete CaptureState parity traces including save/retry and both speech gestures, plus actual native cancellation and callback-after-teardown tests.
3. Build a real nonactivating panel + AX selection + Odin-compatible Parakeet inference spike; measure latency, idle CPU and RSS. Explicitly resolve the no-Swift speech dependency rather than assuming the old FluidAudio integration transfers.
4. Add native screenshot fixtures: render NSView trees with fixed sizes/content/appearance on the main thread, save light/dark images, and review diffs. Separately test activation policy, key-window transitions, focus restoration, text selection, IME, keyboard navigation, VoiceOver and Retina scaling in an actual running app. Offscreen screenshots alone cannot validate those behaviors.
5. Complete a clean-machine, signed/notarized old-to-new Sparkle update with permission continuity and failure handling. Build a research-to-production Odin check/test/bundle pipeline before replacing the existing app scripts.

Not confirmed: disclosed model training composition; comparative agent win rate; production compile time; OLS reliability in this project; live hot reload with native callbacks; Intel/universal execution; complete Darwin API coverage; notarization acceptance; Sparkle update success; accessibility/microphone permission stability. These remain separate gates, not hidden assumptions.

## Sources

- **E1 — Local executable evidence:** [runner](odin-agents/run.py), [results](odin-agents/results.json), [capture source](odin-agents/capture/capture.odin), [tests](odin-agents/capture/capture_test.odin), [Foundation bundle probe](odin-agents/native/main.odin).
- **S1 — Odin language semantics:** [official overview](https://odin-lang.org/docs/overview/), especially tagged unions, procedure calling conventions, strings, foreign system and defer.
- **S2 — Pinned Darwin core tree:** [Odin core/sys/darwin](https://github.com/odin-lang/Odin/tree/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/core/sys/darwin).
- **S3 — Pinned ObjC/AppKit bindings:** [objc.odin](https://github.com/odin-lang/Odin/blob/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/core/sys/darwin/Foundation/objc.odin), [NSApplication.odin](https://github.com/odin-lang/Odin/blob/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/core/sys/darwin/Foundation/NSApplication.odin), [NSPanel.odin](https://github.com/odin-lang/Odin/blob/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/core/sys/darwin/Foundation/NSPanel.odin).
- **S4 — Pinned vendor migration:** [vendor/darwin](https://github.com/odin-lang/Odin/tree/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/vendor/darwin), [Foundation/dummy.odin](https://github.com/odin-lang/Odin/blob/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/vendor/darwin/Foundation/dummy.odin).
- **S5 — Official testing contract:** [Running Tests](https://odin-lang.org/docs/testing/), [pinned testing implementation](https://github.com/odin-lang/Odin/tree/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/core/testing).
- **S6 — Compiler interface:** local `odin build -help` at the pinned revision; [compiler source](https://github.com/odin-lang/Odin/tree/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/src).
- **S7 — OLS own documentation:** [README at 0e24b657](https://github.com/DanielGavin/ols/blob/0e24b657bd1d923d2d9b862b6d2d92fa411153fe/README.md).
- **S8 — Working-project hot-reload design:** [Karl Zylinski template README](https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template/blob/901bb85274b76272fce317a5b7b136d592b77ea6/README.md), [macOS/Linux build script](https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template/blob/901bb85274b76272fce317a5b7b136d592b77ea6/build_hot_reload.sh). Source-reviewed, not executed in this task.
- **S9 — Apple signing rules:** [TN2206, macOS Code Signing In Depth](https://developer.apple.com/library/archive/technotes/tn2206/_index.html), particularly nested code and correct use of `--deep`.
- **S10 — OdinEval authors' report:** [arXiv:2608.18595v1](https://arxiv.org/html/2608.18595v1), protocol, Table 2 and threats to validity; not independently reproduced here.
- **S11 — Sparkle's own integration/shipping requirements:** [basic setup](https://sparkle-project.org/documentation/), [programmatic setup, including Qt/ObjC++ and API expectations](https://sparkle-project.org/documentation/programmatic-setup/).
- **S12 — Apple notarization:** [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) (read through its [Apple documentation JSON](https://developer.apple.com/tutorials/data/documentation/security/customizing-the-notarization-workflow.json)).
