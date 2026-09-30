# Which Odin UI library draws Sendpoint's panels most simply?

Research for [Which Odin UI library draws Sendpoint's panels most simply?](https://github.com/saiashirwad/sendpoint/issues/57), within [Map: Sendpoint's experience on the simplest Odin stack](https://github.com/saiashirwad/sendpoint/issues/56). Inspected 30 September 2026. Recommendations below are engineering judgments, not benchmark results.

## Recommendation

1. **For the capture-panel prototype: Odin + a non-activating NSPanel + a plain, layer-backed NSView drawing Core Graphics and Core Text.** Keep layout as a few procedures over rectangles. Use `core:text/edit` only when actual editing enters the prototype. This is my first choice because it avoids a third-party UI runtime, a C/C++ build, GPU pipelines, and a font atlas while retaining system text layout and event-driven drawing. AppKit owns the window and event loop, not the application model. This is custom drawing, not a return to a hierarchy of native controls. [A1–A4, O1–O3]
2. **If layout becomes the problem: add upstream Clay's Odin bindings to that same host and Core Graphics/Core Text renderer.** Clay is a layout engine, not a windowing system, editor, or renderer. It adds wrapping, sizing, scrolling, and render commands without changing the native shell. Do not introduce Metal just to use Clay; move to Metal only if measured animation/paint cost calls for it. Clay + Metal + Core Text is a credible later variant, with public macOS panel source to study, but more machinery than the capture prototype needs. [C1–C2, H1–H3]

If ready-made editing widgets turn out to matter more than minimal dependencies, **Dear ImGui + its OSX/Metal backends** is the strongest alternative—not microui or raygui. It has both single-line and multiline editors and existing backends that accept host-owned native objects. Its Odin/C++ binding and build chain is the trade-off. [I1–I4]

**Do not pick a renderer to fix focus.** Nonactivation is an NSPanel/window policy; returning keyboard focus after capture must still be proved. The public Clay example becomes the key window even though it does not activate its application. “Non-activating” is not synonymous with “never takes keyboard focus.” [A1, H2]

## What was and was not verified

- Read upstream source, READMEs, Odin's installed `vendor/` and `core/`, and Apple's documentation. Sources below pin code revisions where possible.
- Ran the committed [text-edit probe](odin-ui-lib/text-edit-probe.odin) with Odin `dev-2026-09:a2fb372b7`, targeting macOS 13. It passed; details below.
- **No GUI integration or performance benchmark was run.** No idle CPU, RSS/physical-footprint, focus-return, hotkey-to-paint, or release-to-text number is claimed here. “Can idle” below means its API permits an event-driven host, not that the completed application has measured 0% CPU.
- No Swift app changes, build/install/release scripts, or dependency installations were needed.

## Side-by-side comparison

The rank is for this small macOS capture panel, not a general-purpose GUI toolkit ranking. “Host-owned” means Sendpoint creates the NSPanel and decides when to process events and paint.

| Rank / approach | Host-owned panel and loop | Event-only rendering / idle | Retina text | Editing without IME |
|---|---|---|---|---|
| **1. Core Graphics + Core Text** | Directly in NSView drawing callbacks. AppKit hosts it. | Invalidate the view when data changes; no application frame loop is needed. | Core Text provides shaping, kerning and fallback; AppKit layer backing handles scale. | No widget supplied. Adapt `core:text/edit`, with application-owned hit testing, selection painting and wrapped-line navigation. [A2–A4, O1] |
| **2. Clay + Core Graphics/Core Text** | Yes: Clay returns drawing commands, knows nothing about the window. Same answer for a custom Metal renderer. | Call layout/render only on input, new partials, resize, or an active transition/scroll. Stop animation wakeups when settled. | Determined by the renderer and measurement callback; use Core Text for both. Clay itself rasterizes no text. | No ready-made editor in the inspected layout API; same editor work as hand drawing. [C1–C2, O1] |
| **3. Dear ImGui + OSX + Metal** | Yes: OSX backend accepts NSView; Metal backend accepts device, pass, command buffer and encoder. Keep multi-viewport window creation off. | Host can skip frames; must wake for input and timed UI behavior (cursor, tooltips, repeats). Integration work, not a built-in 0%-idle guarantee. | Default stb_truetype atlas; optional FreeType. Current font/backend APIs support DPI-scaled/dynamic textures; not Core Text by default. | `InputText` and `InputTextMultiline` already supplied. [I1–I4] |
| **4. `vendor:microui` + Core Graphics/Core Text** | Yes: consumes input and emits rectangles, clips, text and icons. No window/renderer ownership. | Host calls begin/end on demand; it has no autonomous display loop. | Callback-defined font measurement and host rendering; not inherently tied to its bundled atlas. | Odin's port has a single-line textbox using `core:text/edit`; Return submits, one-line selection/caret. Multiline requires a custom control. [M1–M2] |
| **5. SDL3 + custom UI** | Can wrap our NSWindow or NSView via creation properties. It is a platform/rendering layer, not a widget toolkit. Native-loop coexistence is less direct than using AppKit alone: SDL still needs event pumping. | `SDL_WaitEvent`/timeout can block; do not introduce a permanent PollEvent loop. Coexistence with AppKit and worker wakeups needs testing. | SDL alone is not a complete text stack. Use Core Text yourself, or add SDL_ttf (FreeType + HarfBuzz and other dependencies). | Text events are not an editor. Add `core:text/edit` or another UI library. [S1–S3, O1] |
| **6. raylib/raygui** | Standard desktop path creates its own GLFW window. No supported existing-NSPanel adoption entry point was found in the inspected public API. Custom backend/standalone raygui is possible, but loses its plug-and-play advantage. | raylib has `EnableEventWaiting`, backed by `glfwWaitEvents`; it need not spin continuously. A partial arriving from a worker needs a wakeup route. | raylib TTF rasterization uses stb_truetype; supply a suitable font and pixel scale rather than magnifying a small atlas. | raygui supplies a textbox, not a supported multiline editor in the inspected source. The `GuiTextBoxMulti` code is commented out and says read-only. [R1–R3] |
| **Hand-written Metal (not recommended initially)** | Yes: CAMetalLayer or MTKView inside our panel. | MTKView supports a paused, invalidation-driven mode. | Metal does not supply text layout: retain Core Text and build a glyph/bitmap texture path, or supply another font stack. | Same custom editing as the first two options; Metal removes none of it. [A3, H3] |

### Why microui does not win despite being tiny

Its README describes roughly 1,200 source lines, fixed-region operation, built-in controls and a simple layout system. That is genuinely attractive. But it explicitly leaves drawing and input to the host, so it does not save the native host or renderer. The Odin textbox is better than a minimal append/backspace field: it has selection, movement, cut/copy/paste and mouse positioning. Nevertheless, its source is single-line, uses integer text widths, binds editing conventions to its CTRL bit, and submits on Return. Sendpoint would still own multiline editing and macOS key mapping. For a capture preview, a small layout procedure saves more than adopting its window/control conventions. This ranking is a judgment based on those responsibilities, not a claim that microui is slow. [M1–M2]

### Why SDL3 is feasible but redundant here

`SDL_CreateWindowWithProperties` has explicit Cocoa window/view pointer properties. The Cocoa implementation uses those objects and marks an external window instead of constructing its normal SDL window. Thus “SDL must own the NSWindow” is false. However, adopting a window is not proof of preserving every NSPanel activation/key-window behavior: SDL still installs platform handling and expects its event machinery to run. Its bindings expose Metal view creation and event waiting. For a macOS-only app that already needs AppKit, I would avoid the second platform abstraction unless another requirement needs SDL. [S1–S2]

### Why raylib is the awkward fit, not an idle-CPU disqualification

The inspected GLFW backend actually calls `glfwWaitEvents` when event waiting is enabled. Rejecting it because all raylib applications must run at 60 Hz would be wrong. The friction is window ownership and editing: its ordinary `InitWindow`/GLFW route creates a window; raygui's standalone mode expects the host to reimplement drawing/input/font functions. At that point we are already writing an adapter and still lack a supported multiline editor. [R1–R3]

## Size, dependencies, maintenance, and macOS evidence

These are **source/dependency observations**, not comparisons of optimized executable size or application RAM. Those numbers need identical builds and workloads. In particular, a fixed UI context or layout arena is not total app memory; fonts, drawables, audio and the speech model sit outside it.

| Approach | What we would carry and maintain | macOS shipping evidence found |
|---|---|---|
| Hand-drawn Core Graphics/Core Text | No third-party GUI library; system frameworks plus a small Odin/Objective-C bridge and Core Text foreign declarations. Odin already has Foundation, CoreFoundation and CoreGraphics packages; the inspected toolchain has no corresponding CoreText package. We maintain our small layout/editor integration. [O2–O3, H3] | Apple's APIs are documented for this use; no directly comparable shipped **Odin** capture-panel app was established in this research. |
| Clay | Upstream advertises one ~4.8k-LOC dependency-free C header and ~3.5 MB arena for 8,192 elements, not a minimum for every app. Official Odin bindings and a C-library build script live upstream. Pin the C header and bindings together; maintain our renderer/editor. [C1–C2] | `hw_activity_monitor` publishes a macOS app ZIP; its current source uses **hw_clay**, not necessarily the exact upstream Clay revision/API. The current source and latest release were inspected separately; the release binary was not audited to prove it matches that source. [H1–H4] |
| microui | Native Odin vendor port; no extra C library. README's fixed-region claim applies to the UI core; the current source also uses builders/text-edit state, so do not interpret it as a no-allocation guarantee for every extension. Probe measured `size_of(Context)` as **271,672 bytes**, excluding external buffers/rendering. Toolchain-pinned maintenance; README warns about nightly-compiler compatibility. [M1–M2, probe] | No comparable shipped macOS product verified. The README's browser demo is not macOS shipping evidence. [M1] |
| Dear ImGui | C++ core, generated C/Odin API and OSX/Metal backend code. Capati's binding README targets **1.92.9b-docking**, lists OSX/Metal support, and documents Premake/Python/native compilation. Pin bindings with their matching ImGui version; do not mix with arbitrary upstream HEAD. More build pieces, but fewer editor features to implement. [I1–I4] | Official OSX/Metal example is integration evidence, not proof of a shipped non-activating Odin app. No comparable shipped product verified here. [I5] |
| SDL3 | Odin vendor bindings + native SDL library; font library/editor/layout still separate. SDL_ttf adds FreeType/HarfBuzz and documented additional dependencies. Broader platform surface than this prototype needs; pin binding/native library versions. [S1–S3] | No comparable shipped SDL3 non-activating Odin panel verified. Do not use the history of SDL2 games as evidence for this particular integration. |
| raylib/raygui | Native raylib (graphics/input and other modules), Odin vendor bindings, raygui header/binding. Ordinary desktop path adds GLFW/OpenGL machinery; standalone raygui shifts adapters back to us. Multiline editor remains ours. [R1–R3, O4] | No comparable shipped non-activating panel verified. General raylib examples do not establish the NSPanel path. |
| Hand-written Metal | System Metal/MetalKit/QuartzCore frameworks and Odin vendor bindings; own pipelines/shaders, geometry, resource lifetime and text textures. More rendering code to maintain than NSView/Core Graphics. [A3, H2–H3, O4] | `hw_activity_monitor` is the concrete public example, subject to the release/source distinction above. [H1–H4] |

I did not infer maintenance quality from stars or promise future support. The actionable maintenance distinction is where version coupling lives: Odin toolchain for microui; header + bindings for Clay; generated bindings + C++ core + backends for ImGui; bindings + native platform libraries for SDL/raylib; our bridge and editor for direct Apple drawing. The sources above expose those boundaries.

## What the public Clay panel proves—and does not

The strongest matching example is `hw_activity_monitor`:

- It constructs an NSPanel subclass with `.NonactivatingPanel`, overrides `canBecomeKeyWindow`, installs a plain NSView, then attaches a CAMetalLayer. Input goes through AppKit methods. This demonstrates the desired ownership split in source. [H2]
- It draws on state/input events and pauses its display link when scrolling settles. This is evidence for an event-driven design, **not a measured 0%-CPU claim**: the application also samples processes periodically. [H1–H2]
- Its show path calls `makeKeyAndOrderFront:` and makes the view first responder. Do not copy that unquestioningly into a hold-to-record preview. Keeping the frontmost application unchanged and keeping its keyboard focus unchanged are separate checks. [H2, A1]
- Its build expects sibling collections `hw_clay`, `hw_odin_ui_framework`, `hw_odin_ui_components`, and an `hw-odin` command. I found the public framework but did not establish a self-contained, version-pinned public `hw_clay` checkout from this build. It is not a one-command dependency to adopt as-is. [H4]
- The public framework's `Display_Link` wraps an **NSView API requiring macOS 14**. A macOS-13 deployment target does not make that API available. Use a compatible clock or MTKView's invalidation mode rather than importing that helper unchanged. Its framework also owns substantially more UI machinery and precompiled Metal shaders than the small renderer the prototype needs. [H3, A3]

## Editing: the part no layout engine removes

`core:text/edit` is useful buffer machinery, not a finished text view. Its state has selection, undo/redo, clipboard callbacks, optional grapheme movement, and host-supplied `up_index`, `down_index`, `line_start`, `line_end`. Up/down and soft-line movement consume those supplied indices; they do not calculate wrapped line geometry. The host must map pointer positions to text indices, render selection/caret, scroll the caret into view, and provide macOS shortcut behavior. Use Core Text's layout/index APIs as the measurement authority rather than character-count estimates. [O1, A4, H3]

**Important source trap:** `begin` is commented as per-frame, but it selects the whole buffer and clears undo/redo. Do not blindly call it on every repaint if selection/history must persist. `setup_once` plus retained state and `update_time` is a better starting point; confirm the lifetime contract with tests. IME/CJK composition is excluded by the map, but Unicode indices and multiline positioning are still work. [O1]

Probe command (from repository root):

```sh
odin run docs/research/odin-ui-lib/text-edit-probe.odin -file -minimum-os-version:13.0 -out:/private/var/folders/_f/yb2trsh50c1gv2dpybhtbw7r0000gn/T/opencode/odin-ui-text-edit-probe
```

Observed output:

```text
PASS: multiline buffer, host-supplied Up, begin selects all; microui Context=271672 bytes
```

This verifies import/build compatibility, a newline-bearing buffer, host-directed vertical movement, and the selection reset. It does **not** test an on-screen editor, glyph quality, focus or idle performance. [Probe source](odin-ui-lib/text-edit-probe.odin)

## Suggested prototype contract and acceptance checks

This is a proposed next step, not completed implementation:

1. **Own one AppKit host.** Create the non-activating panel once. During hold-to-record, initially show a non-key preview rather than explicitly making it key. Keep selected-text capture, global hold/release, speech work, and updater outside the drawing code. None of the candidates implements those must-keeps for us. This preserves the map's separation of concerns. [Map](https://github.com/saiashirwad/sendpoint/issues/56)
2. **Draw only on change.** Coalesce partial-text updates onto the UI thread, invalidate the view, and paint the current snapshot. Animate only while visible and actually transitioning. Disable unnecessary caret blinking in a read-only preview. For a Metal variant, use `paused = true` and `enableSetNeedsDisplay = true`; do not inherit a sample's permanent rendering loop. [A2–A3]
3. **Use one text authority.** Measure and draw with Core Text. Test 1×/2× displays and moving between them; custom bitmap/Metal caches need correct backing scale and rebuilding. Ordinary AppKit layer backing reduces this bookkeeping. [A4]
4. **Prove focus independently.** Log frontmost application and key-window behavior before hold, during partials, after release and after cancellation. Test another app's editable text, Spaces/fullscreen and clicking the panel. Displayed text is not permission to activate the app. [A1, H2]
5. **Measure like-for-like.** Compare the Swift app and prototype on the same machine/workload: hidden idle, visible static, recording with partials, repeated show/hide. Collect process CPU-time deltas over a fixed interval, physical footprint/RSS with the same metric, wakeups, and hotkey-to-first-paint/release-to-final-text distributions. Separate cold initialization from warm interaction and speech-model memory from UI memory. Zero frame callbacks while static is a useful check, but not a substitute for CPU measurement.
6. **Add Clay only after a layout pain point appears.** If a growing panel/settings layout needs it, keep the same shell, renderer and editor; add a pinned upstream Clay adapter. If drawing itself is the bottleneck, compare a Metal renderer then. This avoids committing the entire port to a framework before the hard path has passed.

## Primary sources

**Apple**

- **A1:** [NSWindow.StyleMask.nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel): owning app does not activate. Does not promise no key-window focus.
- **A2:** [NSView.setNeedsDisplay](https://developer.apple.com/documentation/appkit/nsview/setneedsdisplay(_:)): invalidation and automatic redisplay through the application event loop.
- **A3:** [MTKView.enableSetNeedsDisplay](https://developer.apple.com/documentation/metalkit/mtkview/enablesetneedsdisplay): together with `isPaused`, makes updates event-driven.
- **A4:** [Core Text overview](https://developer.apple.com/documentation/coretext) and [High Resolution Guidelines: layer backing, layer hosting and bitmap scaling](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/CapturingScreenContents/CapturingScreenContents.html).

**Odin** — inspected compiler revision `a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924`

- **O1:** [`core/text/edit/text_edit.odin`](https://github.com/odin-lang/Odin/blob/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/core/text/edit/text_edit.odin), especially `State`, `begin`, `setup_once`, `translate` and edit commands.
- **O2:** [`core/sys/darwin`](https://github.com/odin-lang/Odin/tree/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/core/sys/darwin): Foundation/CoreFoundation/CoreGraphics.
- **O3:** [old Foundation import migration stub](https://github.com/odin-lang/Odin/blob/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/vendor/darwin/Foundation/dummy.odin). Use `core:sys/darwin/Foundation`.
- **O4:** [`vendor`](https://github.com/odin-lang/Odin/tree/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/vendor), including darwin Metal/MetalKit/QuartzCore, raylib and sdl3.

**Clay and microui**

- **C1:** [Clay README](https://github.com/nicbarker/clay/blob/e6cc36941ab2af5d81107617039d6f527a1c660b/README.md): ownership, arena sizing, render commands, measurement, transitions.
- **C2:** [Official Odin binding README and build files](https://github.com/nicbarker/clay/tree/e6cc36941ab2af5d81107617039d6f527a1c660b/bindings/odin).
- **M1:** [Odin microui README](https://github.com/odin-lang/Odin/blob/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/vendor/microui/README.md).
- **M2:** [Odin microui source](https://github.com/odin-lang/Odin/blob/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/vendor/microui/microui.odin), particularly `Context`, `next_command`, and `textbox_raw` at lines 991–1137.

**Concrete macOS panel**

- **H1:** [hw_activity_monitor README](https://github.com/MartinMikusat/hw_activity_monitor/blob/d5783c65c3fe14c768baff2898ab59cd64c567a4/README.md), UI and sampling descriptions; [v1.3.0 release](https://github.com/MartinMikusat/hw_activity_monitor/releases/tag/v1.3.0) with macOS app archive.
- **H2:** [`panel_window.odin`](https://github.com/MartinMikusat/hw_activity_monitor/blob/d5783c65c3fe14c768baff2898ab59cd64c567a4/panel_window.odin), initialization, show/hide, `panel_tick`.
- **H3:** [Odin UI Framework README](https://github.com/MartinMikusat/hw_odin_ui_framework/blob/93c94057b64d157d33913c82526d37cf42d2b83a/README.md), including display-link availability, frame contract and shader build; [Core Text implementation](https://github.com/MartinMikusat/hw_odin_ui_framework/blob/93c94057b64d157d33913c82526d37cf42d2b83a/coretext/coretext.odin), including foreign declarations and atlas/cache machinery.
- **H4:** [Application build script](https://github.com/MartinMikusat/hw_activity_monitor/blob/d5783c65c3fe14c768baff2898ab59cd64c567a4/build.sh).

**Dear ImGui**

- **I1:** [OSX backend](https://github.com/ocornut/imgui/blob/46ff5a7aab3c091fe8e4e427fea2cabffcf0478d/backends/imgui_impl_osx.mm): NSView initialization and event integration.
- **I2:** [Metal backend API](https://github.com/ocornut/imgui/blob/46ff5a7aab3c091fe8e4e427fea2cabffcf0478d/backends/imgui_impl_metal.h): caller-owned command objects; [font documentation](https://github.com/ocornut/imgui/blob/46ff5a7aab3c091fe8e4e427fea2cabffcf0478d/docs/FONTS.md).
- **I3:** [`imgui.h`](https://github.com/ocornut/imgui/blob/46ff5a7aab3c091fe8e4e427fea2cabffcf0478d/imgui.h): `NewFrame`, `Render`, `InputText`, `InputTextMultiline` and viewport configuration.
- **I4:** [Capati Odin bindings README](https://github.com/Capati/odin-imgui/blob/5402a803e04966bbaf1c3a4632ed44e1a59f9af8/README.md).
- **I5:** [Official Apple Metal example](https://github.com/ocornut/imgui/tree/46ff5a7aab3c091fe8e4e427fea2cabffcf0478d/examples/example_apple_metal).

**SDL and raylib/raygui**

- **S1:** [SDL Cocoa window implementation](https://github.com/libsdl-org/SDL/blob/a72ad266e2551899e8919793384a3f431e0b2857/src/video/cocoa/SDL_cocoawindow.m), `Cocoa_CreateWindow`, and [event API](https://github.com/libsdl-org/SDL/blob/a72ad266e2551899e8919793384a3f431e0b2857/include/SDL3/SDL_events.h).
- **S2:** [Odin SDL3 bindings](https://github.com/odin-lang/Odin/tree/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/vendor/sdl3): `sdl3_video.odin`, `sdl3_events.odin`, `sdl3_metal.odin`.
- **S3:** [SDL_ttf 3 overview](https://wiki.libsdl.org/SDL3_ttf/FrontPage), dependencies and text rendering scope.
- **R1:** [raylib public header](https://github.com/raysan5/raylib/blob/6ecf21f700642c797dd0f2f3d4b1f2c91b71711d/src/raylib.h), [core](https://github.com/raysan5/raylib/blob/6ecf21f700642c797dd0f2f3d4b1f2c91b71711d/src/rcore.c) and [GLFW platform implementation](https://github.com/raysan5/raylib/blob/6ecf21f700642c797dd0f2f3d4b1f2c91b71711d/src/platforms/rcore_desktop_glfw.c).
- **R2:** [raylib text implementation](https://github.com/raysan5/raylib/blob/6ecf21f700642c797dd0f2f3d4b1f2c91b71711d/src/rtext.c): font loading/rasterization.
- **R3:** [raygui header](https://github.com/raysan5/raygui/blob/580961b63be9afa76cf78b7d1ad090768108b5ca/src/raygui.h): standalone requirements, `GuiTextBox`, commented-out `GuiTextBoxMulti`.
