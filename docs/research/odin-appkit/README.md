# Odin → native AppKit research spikes

These are disposable research programs, **not Sendpoint implementation code**. They use native AppKit; there is no Swift, Objective-C source, or webview. Findings and source citations are in [the report](../odin-appkit.md).

## Reproduce

Requires macOS, Xcode command-line tools, Odin, and an interactive logged-in GUI session. Tested on arm64 macOS 27.0 (26A428), Odin `dev-2026-09:a2fb372b7`.

From the repository root:

```sh
mkdir -p .build/odin-research
odin build docs/research/odin-appkit -minimum-os-version:13.0 -min-link-libs -out:.build/odin-research/native
.build/odin-research/native
odin run docs/research/odin-appkit/attributes -minimum-os-version:13.0 -out:.build/odin-research/attributes
odin run docs/research/odin-appkit/boundaries -minimum-os-version:13.0 -out:.build/odin-research/boundaries
vtool -show-build .build/odin-research/native
```

The UI program displays an accessory app's status button and a non-activating panel for five seconds, then tears down. It asserts native launch, custom drawing (Core Graphics + Core Text), a programmatically triggered text-edit delegate callback, main-queue dispatch, copied timer blocks, animation completion, and effective-appearance callbacks. It constructs an NSVisualEffectView, an NSStackView, native editable NSTextField/NSTextView, and NSLayoutAnchor constraints. `--manual` keeps it running for interactive editing/focus/IME exploration; stop that mode with Ctrl-C (that force-stop does not exercise orderly teardown). Default mode does not synthesize keyboard input or request any permissions.

The attribute probe separately proves `@(objc_implement, objc_superclass=...)` works. The boundary probe allocates an AVAudioEngine without starting it, reads microphone authorization/login-item status without changing either, creates/releases a system AX object, and queries the default CoreAudio input device without recording.

**Do not interpret this as an end-to-end microphone/hotkey/selected-text test.** AX trust was false; audio authorization was denied. There is no permission prompt, capture, login registration, or install step here.

## Optional generated-binding probe

Clone [harold-b/darwodin](https://github.com/harold-b/darwodin) at `08a4e282715db944e390ab4cc3d81da9971741bc` outside the repository; no vendored dependency is committed. Substitute its absolute path below:

```sh
odin run docs/research/odin-appkit/darwodin -collection:darwodin=/path/to/darwodin/darwodin-macos/darwodin -minimum-os-version:13.0 -out:.build/odin-research/darwodin
```

This creates an NSTextField using generated typed bindings across package imports. It passed; it does not validate every generated framework.

## Observed output (2026-09-30)

Native UI (the final Core Graphics/Core Text version passed twice, once with explicit deployment target):

```text
panel visible: true app active: false
NSTextViewDelegate textDidChange:
dispatch_async_f: main queue callback
NSAnimationContext completion
NSTimer copied block; appearance callbacks: 3
PASS launch/dispatch/block/draw/edit/animation: true true true true true true
Auto Layout root ambiguous: false
teardown complete
```

Other probes:

```text
objc_implement answer: 47
AVAudioEngine running: false
AVCaptureDevice audio authorization status: 2
SMAppService status (unbundled): 3
AX trusted: false
CoreAudio default input query OSStatus: 0 has device: true
darwodin native text field created
```

**Packaging surprise:** the default compiler/linker invocation emitted Mach-O `minos 28.0`, SDK `27.0`, despite this program running locally on 27.0. Building with `-minimum-os-version:13.0` emitted `minos 13.0`, SDK `27.0` and passed the same run. This only verifies the load command, not compatibility with macOS 13. `-min-link-libs` removes a duplicate `-lobjc` warning.

## Limits

One machine/architecture, short runs, no memory/latency/idle-CPU benchmark, no leak/sanitizer run, no signed/notarized bundle. Root `hasAmbiguousLayout=false` is not a recursive visual-layout audit. Text change is triggered with `setString:`/`didChangeText`, not a real keystroke. Dark/light appearances are explicitly applied to this view and reset to inheritance; system-wide appearance changes are not simulated. Interactive panel focus, IME, undo, accessibility navigation, Spaces/fullscreen, Retina changes, and appearance rendering still need manual/product tests. Hardcoded SDK enum values/attribute-key strings and wide `Obj` pointers keep the spike small; use reviewed typed bindings in production.
