# An Odin-shaped Sendpoint

Research for [How would an idiomatic Odin programmer structure Sendpoint?](https://github.com/saiashirwad/sendpoint/issues/58), under [Map: Sendpoint's experience on the simplest Odin stack](https://github.com/saiashirwad/sendpoint/issues/56). Investigated 2026-09-30. Documentation only; no Swift changes or application builds.

## Recommendation in one page

**Use one explicitly owned `App`, ordinary procedures, and small workflow states inside it. Keep the capture transition function; drop the rule that every piece of state needs a machine/controller pair.** This is my recommendation, not a claim that gingerBill has designed or endorsed Sendpoint. His stated advice is to solve the specific problem, prefer clarity to cleverness, and let useful structure emerge rather than start from a paradigm. [G1, G2]

Start with three packages, not a framework:

```text
src/app/        main.odin, app.odin, capture.odin, voice.odin,
                palette.odin, settings.odin, store.odin, ui.odin
src/model/      note.odin, stack.odin, capture.odin, prompt.odin,
                *_test.odin
src/macos/      window.odin, hotkey.odin, selection.odin,
                audio.odin, coreml.odin, objc.odin
```

These are proposed filenames, not files added by this research. `app` owns policy and resources; `model` contains data transformations and the capture transition without native dependencies; `macos` contains only the native calls actually needed. Split more only when a real boundary helps. Odin's package is a directory, not a class or a file; files already provide cheap thematic organization. [O1; layout is inference]

`App` contains the store, settings, capture state, palette state, surface state and retained worker handles. Main-thread procedures alone change user-facing state. Workers own their own buffers and native resources; they never get unrestricted mutable access to `App`. A main-thread inbox drains hotkey, UI, timer and worker events without recursive transitions, runs concrete commands, then requests a redraw. Sleep when there is no work; do not borrow a game's always-running frame loop for a menu-bar utility. [S1, H1, H2, K1; design inference]

| Workflow | Smallest useful shape proposed |
|---|---|
| Capture | Keep a closed lifecycle (`Idle`, `Session`, `Torn_Down`) and closed phase variants; `capture_update(state, event)` returns a small command list. Preserve selection/recording rendezvous, hold/tap gesture, save/retry and complete-context checks. |
| Voice | A retained audio resource owner and one serial STT worker. Commands start, finish or cancel a take; tagged whole-transcript snapshots come back. Separate worker resource status from capture's user-visible phase; do not copy a second UI workflow into the worker. |
| Stack palette | A small state struct for query, selected stable ID and scroll; an enum/union only for genuinely exclusive modes such as browsing versus editing. Pure filtering; concrete action procedures. Add request identity only where work is asynchronous. |
| Settings | Plain validated settings data, plus an editing draft if Apply/Cancel is needed. `settings_apply` validates, persists and tells affected owners what changed. A checkbox does not need a controller and effect enum of its own. Model permission/download workflows separately when their asynchronous lifecycle requires it. |

Keep **one resource owner, cancellation, rejection of stale completions, and idempotent teardown**. These solve actual Sendpoint bugs; they are not Swift ceremony. Drop Observation wrappers, object factories for every surface, forwarding setters, dependency containers, a generic effect engine and blanket machine/controller duplication. Keep a few injectable procedure pointers plus userdata for real system boundaries. Render from current state; do not recreate Swift Observation in Odin. [S1, O1, G1; recommendation]

Use memory by lifetime: persistent store allocations; per-take data; worker scratch; and per-event/render scratch. Never enqueue borrowed scratch strings. Cancellation invalidates the take immediately, but buffers and callback userdata survive until the owner acknowledges quiescence. The hardest part is this lifetime contract, not translating a Swift enum. [G3, O1, O2, S2; inference]

## What gingerBill actually says—and what he does not

- **Stated:** “Try to solve the specific problem you have, not a general problem you might have”; “Clear is better than clever”; “Make the zero value useful”; “Copying is usually better than dependency.” He also says objects can naturally arise and warns against orienting around them. This does **not** amount to banning libraries, structs with ownership, or state machines. [G1]
- **Stated:** Purpose, function and usage should constrain implementation; there is no universally best implementation independent of the problem. **Inference here:** focus behavior, voice latency and low idle use must determine the architecture, not resemblance to a game engine or today's Swift folders. [G2]
- **Stated:** think about allocation size, lifetime and usage, grouping allocations that live and die together. His criticism of ownership systems is partly their focus on single objects rather than systems. **Inference here:** group take memory and worker memory; still document which system frees each resource. “No ARC” does not mean “no ownership.” [G3]
- **Stated:** Odin's implicit `context` primarily allows interception of third-party allocation/logging behavior. He recommends allocator parameters in good APIs, but explicitly cautions that mechanically threading generic allocators everywhere can be worse than specific per-system allocators. **Inference here:** pass `^App`/specific state explicitly; do not hide the entire application in `context.user_ptr`, and do not invent a generic allocator plumbing framework. [G4]

These citations are his own articles, not second-hand interpretations. I did not verify a talk transcript or social-post quotation and do not attribute the proposed thread count, package count, reducer design or renderer to him.

## What real code supports

### A close analogue: hw_activity_monitor

At pinned revision `d5783c6`, this macOS menu-bar application uses one package with separate files for sampling, rules, settings, UI and Darwin calls. `Monitor_State` groups config, sampler, history and a mutex-protected pending config. A worker applies settings at its next tick, samples off-main, hands a completed snapshot to main and resets temporary memory. [H1, H3]

`Ui_Snapshot` records its allocator; `ui_post_snapshot` allocates rows/text for transfer and calls `dispatch_async_f`; the C callback establishes an Odin context. Main installs the new snapshot and explicitly destroys the previous one. Pure row-building procedures accept an allocator. This is concrete evidence for ordinary data/procedure organization and owned handoff, not an imagined “Odin architecture.” [H2]

**Do not copy it uncritically.** Its inspected `run_app` starts workers without retaining them, and `monitor_worker` is an infinite sleep loop without a stop/join path. That is not a sufficient lifecycle model for cancellable Sendpoint takes. Its README describes a custom panel renderer and an idle-paused display link, but this research did not run it or independently validate focus/CPU claims. Its updater is not a recommendation for Sendpoint's distribution security. [H1, H3]

### Karl Zylinski

His public hot-reload template has a `Game_Memory` struct, a pointer `g`, and ordinary init/update/draw/shutdown procedures. `game_update` clears the temporary allocator; exports allow an outer executable to retain the memory across a reload. This is useful evidence for flat state plus procedures and lifetime-based scratch. It is a **template**, not proof of a shipped Sendpoint-like app; neither its global pointer, hot reload nor frame rate is a requirement to copy. [K1]

### JangaFX: evidence boundary

Odin's official showcase lists EmberGen, LiquiGen, GeoGen and IlluGen as commercial Odin tools. That establishes real-product use, not their internal state or threading architecture. The public JangaFX organization inspected here lists an Odin fork, VectorayGen-Public, simple-vdb-writer and FMAG; I did not locate inspectable application source for those four tools. Consequently this report makes **no claim** that JangaFX uses this package layout, reducers, arenas per take, or a particular UI model. [J1, J2]

## State and event flow: one owner, not one giant state machine

Odin supplies structs, enums, tagged unions, exhaustive switches and procedure values; it does not require an object hierarchy to express a workflow. Payload-specific variants can be structs inside `union #no_nil`. The prior Sendpoint research includes an actually compiled capture slice; it is a useful starting point, not full behavioral parity. [O1, S2]

Recommended flow (design sketch, not compiled code):

```text
native callback / UI action / worker completion
  -> enqueue owned event; wake main
  -> app_drain: validate request identity; route to concrete workflow
  -> capture_update -> bounded concrete commands
  -> execute commands through retained owners
  -> render current state when dirty
```

Do not force all workflows into one combinatorial enum such as `Recording_And_Palette_Open_And_Settings_Dirty`. One `App` is an ownership root, not a single workflow. Keep capture's phase closed; keep orthogonal palette/settings data beside it. Do not allow workers to mutate the main-owned state merely because it is reachable through a pointer. [Design inference from O1, S1, H1–H2]

The current Swift `CaptureState` coordinates real races: voice can start before selection returns, release can arrive while selection is pending, and save may wait for selection. `CaptureController` queues events to avoid reentrancy, retains work by kind, checks cancellation before/after calls, compares the session context and clears work on close. Its selection deadline is 600 ms. These are semantics to preserve deliberately, not an opportunity to flatten everything into `is_recording` booleans. [S1]

For the initial port, keep `capture_update` separate from the command executor for deterministic testing; put both near each other by concern rather than create a general reducer library. Fixed-capacity command output is reasonable because this workflow emits a small known number of commands, but assert/test its capacity—never silently truncate. Settings and simple palette edits can call ordinary procedures directly. Pure prompt composition, filtering and validation stay outside drawing code. [S1, S2, G1; recommendation]

## Threads, cancellation and resource reclamation

This is a **proposed integration contract**, not an Odin runtime guarantee:

| Execution context | Owns / does | Must not do |
|---|---|---|
| Main | App state, UI/native surfaces, hotkey policy, event draining; schedules timer deadlines and persistence requests | Wait for inference or blocking AX reads while presenting the panel |
| Audio callback | Copies samples into a bounded preallocated ring; small level calculations | Allocate/grow buffers, infer, call UI, write disk, or block on a mutex |
| STT worker | Model objects, resampling/decoder state, take buffers; serial prediction and final flush | Mutate UI state or let main free an in-use model |
| Selection worker | Bounded, serial Accessibility read jobs; retained native references for the job | Share AX job data without synchronization or queue unlimited stale reads |

Use one retained `core:thread` handle for each persistent worker, a mutex/condition or native serial queue for ordinary messages, and a proven single-producer/single-consumer ring with correct atomic ordering for audio. Core's `create`/`start`/`join`/`destroy` exposes explicit thread lifetime. Avoid its self-cleaning `run` convenience for lifecycle work: the source warns not to dereference or join a self-cleaning handle. Thread cancellation is our protocol, not a magic `Task.cancel` equivalent. [O3; recommendation]

Every async operation carries a unique request generation plus the immutable capture context (stack ID, note ID, creation time), work kind and, where relevant, destination/save request, target process and result sequence. Validate when dequeuing, not only when the worker publishes. Only the matching request may clear a work slot; an old completion must not clear a newer job. Partials may replace older whole-transcript snapshots; finals, errors and stop acknowledgements must not be dropped. Queue capacity and overflow handling are explicit; audio overflow fails the take instead of silently losing words. [S1, S2, S3; proposed strengthening]

**Finish differs from cancel.** Finish stops ingress, settles callbacks, drains accepted audio, performs the final flush exactly once and saves the matching result. Cancel invalidates the take immediately, stops ingress and scheduling, and discards results. Check cancellation before and after each external read/load/prediction. A synchronous foreign call may still run to completion: wait for settlement before resetting/freeing its memory. A new take cannot reuse the same worker buffers until that acknowledgement. The direct Core ML prototype is file-fed and has no production cancellation API; its successful inference does not remove this work. [S3]

Give selection calls a native timeout where supported and coalesce pending reads. A deadline may let capture proceed without selection, but it does not prove an in-flight AX call stopped. Keep that job's memory until return, and reject its late result. Do not block main waiting for an AX worker; do not put AX and inference on the same serial worker, where one can stall the other. These are design recommendations; actual AX responsiveness still needs a native spike. [S1; inference]

`app_shutdown` should be idempotent: mark shutting down/invalidate requests; unregister hotkeys and timers; stop audio and revoke callbacks; signal workers; asynchronously wait for acknowledgements; join only once workers can finish without main-thread assistance; drain/free remaining messages; release native objects; destroy arenas. Session close follows the same owned-resource cleanup path without destroying warm models. **Ignore late events is not enough: their payloads still need freeing.** Never use force-terminate to simulate safe cancellation. [O3, S2, S3; recommendation]

## Memory: choose lifetimes, not an arena for everything

| Lifetime | Recommended storage and reset point |
|---|---|
| Store/settings | Owned heap allocations or explicit document storage; free replaced strings/records. Do not accumulate every edit in an app-lifetime arena. |
| Capture session | Session-owned text/selection allocations; reclaim after close **and** all dependent save/job references have settled. Copy committed notes into store ownership. |
| Audio/STT | Preallocated ring and reusable tensors/buffers owned by the worker; model lifetime spans takes, per-take state does not. |
| Cross-thread message | Owned payload allocated with a documented thread-safe allocator; transfer to receiver, free on apply **or rejection**. A small message arena is optional, not mandatory. |
| Formatting/filtering/render | Scratch reset at the end of the outer event/render pass after consumers finish. No pointer survives that boundary. |

This follows gingerBill's grouping-by-lifetime argument. Odin strings/slices are descriptors: copying them does not copy bytes. `strings.clone` is an explicit copy; a temporary formatted string or borrowed Objective-C UTF-8 pointer is not safe to queue. Repeated partial transcripts should replace an owned buffer, not grow a session arena indefinitely. [G3, O1; recommendations]

`core:mem/virtual.Arena` supplies growing, static and buffer arenas, resets and temporary marks. Its individual `.Free` operation is not implemented: this alone rules out treating it as a drop-in heap for indefinitely edited settings. `arena_free_all` retains the first growing block; `arena_destroy` frees all blocks. Virtual reservation is not resident RAM, and resetting an arena is not evidence of tiny process footprint. [O2]

Worker scratch is private to that worker. Do not copy a main-thread scratch allocator into a worker context, and do not reset main scratch from arbitrary reentrant callbacks. `core:thread` documents different cleanup duties when a custom `init_context` is provided. Foreign callbacks establish a valid context before using context-dependent Odin procedures. Ordinary APIs may default allocator arguments to `context.allocator`; explicitly choose an allocator at ownership-changing boundaries. [O3, G4, O1]

## Objective-C: a narrow boundary, not a second application

Use pinned `core:sys/darwin/Foundation` bindings and compiler-supported typed messaging for existing declarations. The inspected core contains ObjC runtime registration plus helpers that retain context in subclass/vtable metadata. Missing selectors deserve short typed wrappers whose ABI and ownership are checked against the Apple SDK—not a hand-built universal object system. The older `vendor:darwin/Foundation` import is obsolete at the revision used by the earlier probes. [O4, S2]

Keep ObjC types/selectors out of the pure model. Let `macos` expose concrete operations (show/hide panel, request selection, start/stop capture), native handles and plain results. Retain/release and autorelease-pool boundaries remain explicit; callbacks need the exact C ABI and stable userdata. ObjC blocks are not ordinary Odin procedure pointers. The prior audio work found that the available block helpers were not a ready two-argument audio-tap adapter; choose audited glue only if it simplifies that real boundary, not as a Swift host by default. [O4, S3; recommendation]

The UI renderer is intentionally **not selected here**. Whether controls are AppKit or custom drawn, retain a native shell for focus/window behavior and feed it state through the same procedures. Previous panel activation experiments have not proved the no-focus-steal requirement. This research must not silently reinstate the superseded native-control-only plan. [Map linked above; S2]

## Testing and the next implementation gate

Odin has `@(test)` procedures taking `^testing.T`, `odin test`, memory tracking and deterministic seed options. Imported packages' tests require `-all-packages`. Tests normally run in parallel, so injected clocks, IDs and fake system boundaries must be per test rather than shared globals. The allocator tracker does not establish that foreign Objective-C/Core ML allocations are leak-free. [O5, S2]

Recommended acceptance tests:

1. Replay capture traces: both selection/recording orders; release-before-start; pending-selection deadline; empty final; duplicate key-up; hold/tap; wrong speech key; busy gestures; destination changes; text-save waiting for selection; save failure/retry and dictation failure. Compare with today's Swift semantics before changing them. [S1; proposed tests]
2. Inject a clock and small proc-pointer/userdata boundaries for selection, recorder, surfaces and persistence. Test invalid transitions, stale full context, an old completion after a new request in the same work slot, and synchronous completion while launching. [S1, S2; proposed tests]
3. Test ownership with fake delayed completions: cancel during load/prediction; double close/teardown; callback after cancellation; shutdown while main has pending deliveries; queue overflow; freeing rejected messages; repeated cancel/restart. A fake cancel flag alone is not proof of callback quiescence. [S2, S3; proposed tests]
4. Keep pure store/prompt/filter/settings-validation tests cheap. Add native tests for mic start/stop, device loss, permissions, focus return, signed bundle behavior and screenshot fixtures after the UI choice. The hard-path spike must measure hotkey-to-paint, release-to-text, idle CPU and total memory; no style argument supplies those numbers. [Map linked above; S3]

No new executable was built for this report. The earlier tested capture slice covers only part of the workflow; its tagged-union representation is verified evidence, not a requirement to preserve every abstraction in the old report. The earlier STT probe proves file-fed direct Core ML inference, not real-time capture, safe shutdown or complete app performance. Remaining unknowns: actual renderer choice, bounded AX behavior, mic callback quiescence, focus behavior, model residency policy, screenshot tooling, storage migration and secure auto-update integration. [S2, S3]

## Sources

All claims above are either tied to primary sources here or explicitly labeled design recommendations/inferences. Repository links are pinned where inspected source matters.

- **G1:** gingerBill, [Pragmatism in Programming Proverbs](https://www.gingerbill.org/article/2020/05/31/programming-pragmatist-proverbs/) (2020).
- **G2:** gingerBill, [The Essence of Programming](https://www.gingerbill.org/article/2021/02/01/the-essence-of-programming/) (2021).
- **G3:** gingerBill, [Memory Allocation Strategies, Part 1](https://www.gingerbill.org/article/2019/02/01/memory-allocation-strategies-001/) (2019).
- **G4:** gingerBill, [context—Odin's Most Misunderstood Feature](https://www.gingerbill.org/article/2025/12/15/odins-most-misunderstood-feature-context/) (2025).
- **O1:** Odin [official overview](https://odin-lang.org/docs/overview/): packages, unions, switches, procedure conventions, strings, implicit context and foreign system.
- **O2:** Odin [`arena.odin`](https://github.com/odin-lang/Odin/blob/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/core/mem/virtual/arena.odin).
- **O3:** Odin [`thread.odin`](https://github.com/odin-lang/Odin/blob/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/core/thread/thread.odin).
- **O4:** Odin [`objc.odin`](https://github.com/odin-lang/Odin/blob/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/core/sys/darwin/Foundation/objc.odin) and [`objc_helper.odin`](https://github.com/odin-lang/Odin/blob/a2fb372b76e81ef31fbbc8a2cf2b4fdf5ac6c924/core/sys/darwin/Foundation/objc_helper.odin).
- **O5:** Odin [Running Tests](https://odin-lang.org/docs/testing/).
- **H1:** hw_activity_monitor [`main.odin`](https://github.com/MartinMikusat/hw_activity_monitor/blob/d5783c65c3fe14c768baff2898ab59cd64c567a4/main.odin).
- **H2:** hw_activity_monitor [`ui.odin`](https://github.com/MartinMikusat/hw_activity_monitor/blob/d5783c65c3fe14c768baff2898ab59cd64c567a4/ui.odin), especially `ui_post_snapshot`, `ui_apply_snapshot_c`, `ui_snapshot_destroy`.
- **H3:** hw_activity_monitor [`README`](https://github.com/MartinMikusat/hw_activity_monitor/blob/d5783c65c3fe14c768baff2898ab59cd64c567a4/README.md), [`sampler.odin`](https://github.com/MartinMikusat/hw_activity_monitor/blob/d5783c65c3fe14c768baff2898ab59cd64c567a4/sampler.odin), [source tree](https://github.com/MartinMikusat/hw_activity_monitor/tree/d5783c65c3fe14c768baff2898ab59cd64c567a4).
- **K1:** Karl Zylinski, [`game.odin`](https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template/blob/901bb85274b76272fce317a5b7b136d592b77ea6/source/game.odin).
- **J1:** Odin [official showcase](https://odin-lang.org/showcase/).
- **J2:** [JangaFX public repositories](https://github.com/orgs/JangaFX/repositories), checked via GitHub API; a discovery boundary, not evidence of private application internals.
- **S1:** Today's Swift main at `3288cba`: [`AGENTS.md`](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/AGENTS.md), [`CaptureState.swift`](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Sources/SendpointDomain/CaptureState.swift), [`CaptureController.swift`](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Sources/Sendpoint/Capture/CaptureController.swift). Local main matched fetched origin/main.
- **S2:** Earlier first-party [Odin agent findings and experiment record](https://github.com/saiashirwad/sendpoint/blob/498adcac87ecda98a7f7955b426f7463dc451236/docs/research/odin-agents.md), including linked compiled capture source/tests. Read as prior experiment evidence, not rerun here; its native-control-only recommendation is superseded by the current map.
- **S3:** Earlier first-party [Odin STT findings and experiment record](https://github.com/saiashirwad/sendpoint/blob/4b753c2c96d3b45ec2eeebcc129dcdd150161e16/docs/research/odin-stt.md), including direct Core ML source/results and documented limits. Read, not rerun here.
