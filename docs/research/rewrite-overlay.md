# Can a webview overlay feel native and instant?

Research for [#38](https://github.com/saiashirwad/sendpoint/issues/38), within [map #35](https://github.com/saiashirwad/sendpoint/issues/35). Investigated 2026-09-30. Scope follows the map: TypeScript owns UI and app logic; Swift owns native boundaries; Parakeet Unified remains on-device; Electron is excluded.

## Decision

**Conditional yes: use a retained, preloaded webview inside a native non-activating panel. Prefer Swift/AppKit hosting for the overlay spike; Tauri is not ruled out, but requires equivalent macOS panel integration, not just window flags.** Both render through WKWebView on macOS, so neither has an inherent different rendering engine advantage. [1][2][3]

This is a feasibility conclusion, **not a measured latency, memory, or visual-parity pass**. No trustworthy apples-to-apples cold/prewarmed hotkey-to-visible-pixel benchmark was found in the primary sources reviewed. No executable spike was run. The map's end-to-end spike must still establish those numbers. Do not turn “prewarmed” into an unsupported “instant” guarantee.

## Findings by requirement

| Requirement | Swift-hosted WKWebView | Tauri 2 on macOS | Confidence / consequence |
| --- | --- | --- | --- |
| Cold hotkey → first paint | Must create/load web content if not prepared; separate rendering process exists. | Same engine, plus Tauri setup and bridge. | No numerical bound established. Keep creation/navigation off the ordinary hotkey path. [1][2][8] |
| Prewarmed hidden → first paint | Retain panel and loaded document; mutate state instead of navigating. | Create hidden/unfocused once, await frontend readiness, then show. | Expected to remove initialization work, not a guarantee of retained pixels or active JS. Hidden scheduling/process loss remain risks. [2][3][8] |
| Transparent capsule | Clear native window plus transparent web content; audit the WK background mechanism. | `transparent` is documented as requiring `macOSPrivateApi`. | Private-API/distribution risk, not merely CSS. [2][3][5] |
| Native blur/material | `NSVisualEffectView` behind webview. | Window effects API exists and requires transparency. | Background material is possible; native foreground vibrancy is not automatically inherited by HTML. [4][6] |
| Non-activation | Explicit `.nonactivatingPanel` on `NSPanel`; native owner controls ordering/key status. | `focus: false` and `focusable: false` have narrower documented meanings; native handles are available. | Do not equate an unfocused ordinary window with a non-activating panel. [3][4][7] |
| Text | WebKit system font family and weights. | Identical engine on the same OS. | System font available; AppKit-identical metrics, text editing and accessibility still need testing. [1][9] |
| Smooth animation | CSS animation facilities exist; native window controls can remain native. | Same rendering capabilities. | No observed FPS or frame-time result. Validate under STT load, not in an empty page. [10] |
| Retained memory / idle CPU | Native host alone is not total cost: web content renders out of process. | Same caveat; shell/bridge also contribute. | No measured MB/CPU figure. Compare attributable process footprint, not just app RSS. [8] |

## Preserve the actual native behavior

The existing app is already a useful specification. At repository revision `3288cbacb3872f65845636e843319adc203b074c`, `CaptureWindows.swift` retains separate voice/editor panels, prepares them ahead of use, and hides via `orderOut`. The voice panel is borderless/non-activating, floating, joins all Spaces, allows full-screen auxiliary presentation, and is shown with `orderFrontRegardless()`. The editor intentionally uses `presentActivated()` instead. Escape during voice capture uses a native global registration with a fallback monitor. [11]

**Recommendation:** reproduce that split rather than making every overlay non-focusable. The passive recording capsule should not change the foreground app or steal typing. Clicking an edit action may deliberately enter an interactive editor. `focusable: false` cannot simultaneously satisfy “never take focus” and “type into the web editor.” Apple's definition of `.nonactivatingPanel` concerns app activation; key-window/first-responder behavior is a separate concern. [7][11]

For Tauri, official source exposes `ns_window()` and `with_webview()`, but that is an escape hatch, not a documented NSPanel abstraction. Budget a native panel adapter and test its ownership and shutdown. Do not simply set the non-activating style bit on an arbitrary window and assume the NSPanel contract. No maintained panel plugin was evaluated or endorsed here. [4][7]

**Focus-return policy (proposed):** passive capture should need no restoration because it never takes activation. For deliberate editor activation, capture the originating app/context before showing; restore only on an explicit finish/cancel and only if the user has not switched elsewhere. Test this policy across normal apps, full-screen windows, Spaces, multiple displays, and Stage Manager. A blanket “reactivate the previous app on every hide” would risk stealing focus back from the user's newer choice.

## Transparency is the main platform-specific wrinkle

Tauri's current configuration documents `macOSPrivateApi` as enabling transparent backgrounds, and its transparent-window documentation warns about App Store acceptance. Wry's inspected implementation uses the `drawsBackground` KVC key; its runtime background setter explicitly calls this a private API. It also sets public `underPageBackgroundColor` on supported systems, but Apple's description is specifically the area behind the active page, visible during overscroll. **Do not cite that public property alone as proof that the whole macOS webview becomes transparent.** [2][3][5]

For direct WKWebView hosting, audit the exact SDK/OS path used to suppress the default background. This investigation did not establish an all-supported-OS, public-only replacement for Wry's transparency mechanism. Direct hosting does not magically eliminate this risk. If private API is unacceptable, opaque styling or a separately validated public-only implementation is a prerequisite, not a silent fallback.

Tauri's configuration also explicitly recommends `windowEffects` as a public-API alternative when only a translucent background is needed. That may avoid requesting general transparent-window behavior; its interaction with the rounded capsule and HTML background must be tested, especially since the effects builder documentation still says it requires transparency. Do not infer that every material-only window needs private APIs, or that material-only support proves arbitrary per-pixel transparency. [3][4]

For native desktop blur, use a native `NSVisualEffectView` with the appropriate semantic material and behind-window blending under the transparent webview. Apple explicitly distinguishes behind-window from in-window blending and says that inserting a visual effect view does **not** automatically enable foreground vibrancy. Therefore native material behind HTML is feasible, but “indistinguishable native vibrant text” is unproven. Do not substitute a CSS blur and describe it as the same desktop material. [6]

Proposed visual checklist: clear root/body before initial reveal; match corner masks and hit regions; prevent a rectangular white flash; avoid clipping shadows; verify light/dark, increased contrast, reduced transparency, and reduced motion. Use an opaque contrast-safe material when the user's accessibility settings require it. These are acceptance requirements, not observed results.

## Prewarming without turning idle into busy

Proposed lifecycle:

1. At app startup, create the panel/webview and load bundled assets once. Keep network fetches and downloadable fonts off the reveal path.
2. Frontend sends a versioned `ready` message after its initial DOM and required assets are ready. Navigation completion alone is not the app-ready contract.
3. On the hotkey, update the current session snapshot and reveal the existing panel. Do not wait for Accessibility selection or the first Parakeet token to show recording status.
4. Coalesce meter/transcript updates to the visible render cadence. Do not send raw audio buffers or replay a queue of obsolete meter frames through the UI bridge.
5. On hide, stop animation loops/subscriptions and meter delivery; retain only needed state/document. One owner cancels lifecycle work; generation/session IDs reject stale replies after hide, reload or a new capture.
6. On web-content-process termination, invalidate readiness, recreate/reload, and rehydrate from authoritative TypeScript app state according to the chosen app-logic architecture. Surface a bounded recovery state rather than indefinitely showing a blank panel. Never let recovery apply the previous capture's transcript to the new one.

The basis for steps 5–6 is concrete: Tauri exposes background throttling policy, Wry gates its implementation to macOS 14+, and Apple explicitly exposes web-content-process termination because rendering occurs separately. Retention does not guarantee continuous execution or immortality. Do not disable throttling globally just to pass a reveal benchmark; test default behavior first and measure any policy change's idle cost. [2][3][8]

## Text and animation polish

WebKit documents `font-family: -apple-system` and CSS weights as the supported system-font route; avoid hard-coded private font names. Use explicit font size, line height, spacing and weights from the existing design, then compare screenshots at 1×/2× and across displays. A system font does not prove identical line breaks, baseline placement, antialiasing or native editor behavior. Check Unicode, emoji, long transcript wrapping, selection, IME composition, keyboard shortcuts, VoiceOver roles, and focus rings. [9]

For the spike, prefer a small stable DOM, animate transform/opacity rather than repeatedly relaying native window sizes, and avoid layout reads interleaved with writes. These are optimization hypotheses to profile, not a measured promise of compositor-only work. WebKit supports CSS animation and `prefers-reduced-motion`; provide a no-motion variant. At 60 Hz a frame is about 16.7 ms; at 120 Hz it is about 8.3 ms (arithmetic budgets, not achieved timings). [10]

## Required measurement in the map spike

Run identical production-built UI/assets in both shells on the same hardware/OS/WebKit version; inspector/dev server off. Record all versions and commit IDs. Include a native current-app baseline. Do not claim a Safari browser tab is a WKWebView-in-NSPanel benchmark.

| Scenario | Definition |
| --- | --- |
| App cold | Fresh process launch through first usable overlay; report separately from a hotkey in an already-running menu-bar app. |
| Webview cold | App running, overlay webview not yet created; create it on hotkey. |
| Warm | Loaded, ready panel hidden briefly, then shown without navigation. |
| Long-hidden | Same retained panel after 1 and 10 minutes hidden; repeat after sleep/wake and memory pressure. |
| Recovery | Content-process termination/reload, followed by capture; check stale-result rejection. |
| Loaded | Same tests while Parakeet Unified is transcribing and meter/text updates arrive. |

Timestamp native hotkey receipt (`t0`), native show request, frontend snapshot application, animation callbacks, and the first **visible changed pixel**. A `requestAnimationFrame` callback/bridge acknowledgement is a scheduling/IPC measurement, not proof of screen presentation; double-rAF is also only a proxy. Use synchronized screen capture or external high-frame-rate video for visible onset and record its sampling uncertainty. Measure ready-to-visible and hotkey-to-visible separately; do not subtract JavaScript and native clocks without calibration. Record transcript-token latency separately from overlay appearance.

Use at least 100 warm reveals and 20 fresh-process trials per shell; publish raw data, median/p95/max and failures. Sample whole attributable app/WebContent/GPU/network process footprint before UI creation, after one/two retained overlays, after 10 minutes idle, during STT, and after disposal. Avoid naively summing shared RSS as exclusive memory; report the tool/metric and attribution limits. Record idle CPU over a fixed 60-second window after settling, with an app-without-webview baseline and an STT-off baseline.

**Proposed acceptance gates, not user-approved budgets or measured results:** warm p95 hotkey-to-visible ≤50 ms and no more than one refresh interval worse than the native baseline; no blank/white first frame; no foreground-app changes during passive capture; no stale transcription after cancellation; no persistent idle animation work; memory/idle-CPU budgets must be agreed in the map before the final go/no-go. Cold/recovery times must be reported even if warm results pass. Inspect frame-time traces and visible hitches under STT rather than relying on average FPS.

## What remains unconfirmed

- Actual cold/warm first-visible-pixel latency, retained MB, idle CPU and animation frame-time distribution for either candidate.
- Pixel parity, foreground HTML vibrancy, accessibility/IME parity, and behavior across the supported OS/display matrix.
- A public-only transparent WKWebView path covering Sendpoint's eventual minimum macOS target.
- A production-proven Tauri native-panel ownership adapter and its focus behavior.

These are explicit inputs to the map's spike, not reasons to claim the overall rewrite is approved. This ticket resolves the source-level feasibility question and defines how to falsify it.

## Primary sources

Sources accessed 2026-09-30. GitHub implementation links are pinned to inspected repository heads; they are **not** a claim that these commits ship in a particular Tauri release. Recheck against the spike's lockfile.

1. [Tauri: Webview Versions](https://v2.tauri.app/reference/webview-versions/) — macOS uses OS WKWebView; version varies with OS.
2. [Wry WKWebView implementation, cab3eac](https://github.com/tauri-apps/wry/blob/cab3eace983007a16f132c14a34d0a220c707bea/src/wkwebview/mod.rs) — creation, background handling, scheduling policy, initialization, activation and script evaluation.
3. [Tauri configuration reference](https://v2.tauri.app/reference/config/#windowconfig) — `visible`, `focus`, `focusable`, `acceptFirstMouse`, `transparent`, `backgroundThrottling`, window effects; also [macOSPrivateApi](https://v2.tauri.app/reference/config/#macosprivateapi).
4. [Tauri WebviewWindow source, f040897](https://github.com/tauri-apps/tauri/blob/f04089769d8c6bcd1b8d31870e26390019715ebc/crates/tauri/src/webview/webview_window.rs) — builder focus settings, effects, native handle and webview access.
5. [Apple: underPageBackgroundColor](https://developer.apple.com/documentation/webkit/wkwebview/underpagebackgroundcolor) — public overscroll/background semantics; macOS 12+.
6. [Apple: NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview) — material, blending and explicit vibrancy requirements.
7. [Apple: nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel) — panel/subclass does not activate the owning app.
8. [Apple: webViewWebContentProcessDidTerminate](https://developer.apple.com/documentation/webkit/wknavigationdelegate/webviewwebcontentprocessdidterminate(_:)) — separate content process and termination notification.
9. [WebKit: Using the System Font in Web Content](https://webkit.org/blog/3709/using-the-system-font-in-web-content/) — supported system font selection and weights.
10. [WebKit: Responsive Design for Motion](https://webkit.org/blog/7551/responsive-design-for-motion/) — CSS animation background and reduced-motion support.
11. [Sendpoint: CaptureWindows.swift at research baseline](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Sources/Sendpoint/Capture/CaptureWindows.swift#L108-L265) — existing preparation, retention, voice/editor presentation and panel setup.
