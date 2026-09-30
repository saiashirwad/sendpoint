# Sendpoint's domain in TypeScript

Research for [#39](https://github.com/saiashirwad/sendpoint/issues/39), under [rewrite map #35](https://github.com/saiashirwad/sendpoint/issues/35). 2026-09-30.

## Decision in brief

Recommend **framework-independent TypeScript discriminated unions and pure reducers, an explicit app-lifetime effect owner, React as the initial UI adapter, and Vitest for domain/controller tests**. Do not introduce XState for the initial port. React is a provisional engineering choice, not a measured winner for memory, latency, or agent performance. Solid is the first alternative if the shell spike shows rendering overhead matters.

All app policy—including machines, persistence policy, store queue, prompt composition, and templates—moves to TypeScript. Swift retains native operations, not a second copy of the workflow. Keep native filesystem operations behind a small byte-oriented boundary. This follows the map's Notes; it does not choose WKWebView versus Tauri, a migration strategy, or approve the overall rewrite.

## Evidence and scope

Repository observations below refer to commit `3288cbacb3872f65845636e843319adc203b074c` ([source tree](https://github.com/saiashirwad/sendpoint/tree/3288cbacb3872f65845636e843319adc203b074c)). Counts from `wc -l Sources/SendpointDomain/*.swift Tests/SendpointDomainTests/*.swift`: **21 domain files / 3,334 lines; 20 test/fixture files / 3,553 lines**. These are physical lines, not a complexity estimate. CaptureState alone is 497 lines; a toy idle/recording/done reducer is not an adequate port.

Important correction to the shorthand “pure domain”: `StackStore` is an observable, main-actor async queue, `StorePersistence.live` performs disk I/O, and CaptureState imports CoreGraphics for `CGRect`. They need boundary separation, not just syntax translation. [S1–S3]

No app files changed, no dependencies installed, no executable spike or benchmark run. The code below is a deliberately scoped translation example, not a compiled or complete replacement. App build/install scripts were not run because this ticket is research-only.

## Framework and state choices

These are **design judgments based on documented semantics**, not evidence that agents are empirically better at one framework.

| UI | Fit with this domain | Cost/risk and verdict |
| --- | --- | --- |
| **React** | Official `useSyncExternalStore(subscribe, getSnapshot)` directly supports a domain owner outside the view tree; immutable cached snapshots and unsubscribe are explicit contracts. [W2] | Hooks and effect dependencies are another lifecycle to understand. Keep capture/STT/persistence out of component effects. Choose as baseline: the app's hardest logic remains ordinary TS, with a small documented integration seam. |
| **Solid** | Signals offer explicit getter/setter functions and tracked reads; an adapter can publish reducer snapshots with `setSnapshot(next)`. [W3] | Tracking scopes matter: reading a value outside the reactive consumer captures a value, not a future subscription. Good alternative for granular transcript/meter updates; not enough evidence here to claim lower total app RAM. |
| **Svelte 5** | `$state.raw` supports replacement of immutable snapshots without deep proxying. [W4] | Plain `$state` deeply proxies objects; cross-module rune exports have compiler-specific restrictions. Keep runes in adapters, not the domain. Attractive compact UI syntax, but an additional compilation model for agents to respect. |
| **Preact + signals** | Read-only signals can expose snapshots; computed values derive UI facts, and direct signal text binding can avoid virtual-DOM diffing. [W5] | Do not turn every workflow flag into a separately writable signal. Mixing hooks, signal effects, and domain effects creates multiple apparent owners. Viable, but no demonstrated benefit here worth adding that choice to the first spike. |

**Agent-oriented guardrails matter more than framework selection:** one exemplar machine, explicit event/effect names, exhaustive switches, no domain imports from UI libraries, no native calls in views, and deterministic tests. Prefer a short adapter over a global framework store with arbitrary public setters. A later controlled comparison could give each agent the same late-result bug and destination-picker feature, then compare test regressions and review effort; this research did not run that experiment.

### Plain reducers versus XState

Choose `update(state, event) -> { state, effects }`. It is the nearest translation of the existing single `update` function and ordered effect array, so tests can retain their intent and names. Every union uses a literal `type` discriminant; exhaustive switches end in `assertNever`. TypeScript documents both narrowing and the `never` exhaustiveness pattern. [S1, W1]

XState is a legitimate alternative, not an incompatible one: invoked actors start on state entry, stop on exit, and promise results are discarded after their state exits. It also offers reducer-style transition actors. But its actions are fire-and-forget, including `async` actions; async native work belongs in invoked actors, not actions. [W6] Adopting it now would change both language and orchestration representation, complicating parity review. Reconsider when hierarchical/parallel workflows or visualization become a concrete need. XState cannot by itself prove a native operation was canceled or a save belongs to the current destination; bridge contracts and request validation remain necessary.

## Proposed module boundary

```text
packages/domain/        # ordinary .ts, no UI, native, storage, or clock imports
  models.ts             # Subject, Note, Stack, StackDocument
  capture.ts            # state/event/effect unions + update
  machines/             # remaining pure machines, same pattern
  mutations.ts          # apply + validate document
  templates.ts          # built-ins + collection transformations
  prompt-composer.ts    # pure markdown assembly
packages/app/           # plain TS, not tied to a component tree
  capture-controller.ts # event drain, owned work, context checks
  stack-store.ts        # one serialized commit queue
  persistence.ts        # codec, version handling, quarantine policy
  ports.ts              # native/clock/ID/file boundaries
packages/ui/            # React renderers + read-only subscriptions
packages/native/        # shell-specific implementation of the ports
```

This is a proposed layout, not a folder move. Port the other machines with the same signature rather than inventing a framework per feature. Keep `PromptComposer`, `TemplateCollection`, `StackDocumentMutations`, note creation/listing, and UI facts as ordinary pure functions. [S4–S6]

### Value semantics and storage are the non-mechanical parts

- Swift structs/`Equatable` do not translate to mutable JS object identity. Use immutable records/readonly arrays and explicit equality helpers. In particular, capture context equality includes **stackID, noteID, createdAt**; save equality includes **target, destinationStackID, and note**. Checking only note ID fails the existing stale-destination test. Deep readonly typing is not runtime validation or deep freezing. [S1, S7]
- Inject ID generation and time at event construction, not inside reducers. Suggested internal date representation: epoch milliseconds with a codec at the boundary. Keep canonical UUID spelling and define date precision before parity fixtures; never compare deserialized records with `===`. Context dates must be echoed without lossy re-encoding. [S1, S4]
- Preserve `StackDocument` version 4 and the five-stack invariant. The TypeScript internal `Subject` union is **not** permission to silently change the on-disk Swift Codable shape. Read/write v4 using an explicit codec, tested against Swift-produced files, or introduce an explicitly designed version migration later. [S3, S4]
- Current persistence distinguishes missing file, unsupported version (error, not quarantine), malformed/invalid data (quarantine then empty initialization), and unavailable storage. Commits validate then atomically write. Keep those policies in TS; native exposes narrowly scoped read/write-atomically/rename operations within app storage. Do not replace durability with `localStorage`. [S3]
- `StackStore` publishes a candidate document only after a successful commit; a failed head remains queued and halts processing until retry. `selectedStackID` considers pending destination changes separately from committed `currentStackID`. Preserve both semantics and outcome distinctions (`committed`, `noOp`, `rejected`, `commitFailed`, `cancelled`). A retry resumes the queue, not a duplicate add-note mutation. [S2]
- Port Markdown byte-level structure and built-in template IDs/text exactly. Inject date formatting/day comparison functions into the composer tests. Swift currently depends on locale, calendar, and time zone; don't assume JS formatting produces identical punctuation or day boundaries. [S5, S6]
- Unicode search normalization is a compatibility task: current code folds case, diacritics, and width using `en_US_POSIX`; JS `toLowerCase()` alone is not the specified behavior. Establish golden fixtures for full-width text, combining marks, case variants, emoji, and whitespace rather than claiming a normalization recipe is equivalent without testing. [S8]

## CaptureState translated: the difficult selection/voice handshake

Below is a **self-contained type/reducer excerpt for a closed subset of events**, translated from CaptureState's begin, selection, recordingStarted, finishVoice, and teardown behavior. The subset intentionally stops at transcription: it is not the complete event union. Production must additionally port gestures (including releasePending and speech-key pairing), partial/final transcripts, editing, destination selection, save/retry/outcomes, insertion, failure handling, dismissal, and cancellation. The phase type shows the union idiom; phase payloads outside this slice are omitted rather than represented as optional fields. [S1]

```ts
type Context = Readonly<{
  stackID: string;
  noteID: string;
  createdAt: number; // epoch milliseconds, supplied by the caller
}>;
type Rect = Readonly<{ x: number; y: number; width: number; height: number }>;
type Selection = Readonly<{ text: string; screenRect: Rect | null }>;
type Target = Readonly<{ context: Context; captured: Selection }>;
type Mode = "text" | "voice" | "dictation";
type Phase =
  | Readonly<{ type: "selectingText" }>
  | Readonly<{
      type: "selectingVoice";
      recording: boolean;
      finishRequested: boolean;
    }>
  | Readonly<{ type: "startingVoice" }>
  | Readonly<{ type: "recording" }>
  | Readonly<{ type: "transcribing" }>
  | Readonly<{ type: "editing"; text: string }>;
type Session = Readonly<{
  context: Context;
  mode: Mode;
  target: Target | null;
  destinationStackID: string;
  phase: Phase;
}>;
type State =
  | Readonly<{ type: "idle" }>
  | Readonly<{ type: "active"; session: Session }>
  | Readonly<{ type: "tornDown" }>;
type Event =
  | Readonly<{ type: "begin"; mode: Mode; context: Context }>
  | Readonly<{ type: "selection"; context: Context; selection: Selection }>
  | Readonly<{ type: "recordingStarted"; context: Context }>
  | Readonly<{ type: "finishVoice" }>
  | Readonly<{ type: "teardown" }>;
type Effect =
  | Readonly<{ type: "readSelection"; context: Context; mode: Mode }>
  | Readonly<{ type: "startRecording"; context: Context }>
  | Readonly<{ type: "selectionDeadline"; context: Context }>
  | Readonly<{ type: "transcribe"; context: Context }>
  | Readonly<{ type: "show"; surface: "editor" | "voice" }>
  | Readonly<{ type: "focusEditor" }>
  | Readonly<{ type: "beep" }>
  | Readonly<{ type: "close" }>;
type Transition = Readonly<{ state: State; effects: readonly Effect[] }>;

function assertNever(value: never): never {
  throw new Error(`Unexpected variant: ${String(value)}`);
}
function sameContext(a: Context, b: Context): boolean {
  return a.stackID === b.stackID && a.noteID === b.noteID
    && a.createdAt === b.createdAt;
}
function update(state: State, event: Event): Transition {
  const stay = (): Transition => ({ state, effects: [] });
  if (state.type === "tornDown") return stay();
  if (event.type === "teardown") {
    return { state: { type: "tornDown" }, effects: [{ type: "close" }] };
  }
  if (event.type === "begin") {
    if (state.type === "active") {
      return { state, effects: [{ type:
        state.session.phase.type === "editing" ? "focusEditor" : "beep" }] };
    }
    const { context, mode } = event;
    const phase: Phase = mode === "text" ? { type: "selectingText" }
      : mode === "voice" ? {
          type: "selectingVoice", recording: false, finishRequested: false,
        } : { type: "startingVoice" };
    const effects: Effect[] = mode === "text"
      ? [{ type: "readSelection", context, mode }]
      : [{ type: "show", surface: "voice" }, { type: "startRecording", context }];
    if (mode === "voice") effects.push({ type: "readSelection", context, mode });
    return {
      state: { type: "active", session: {
        context, mode, phase, target: null, destinationStackID: context.stackID,
      } }, effects,
    };
  }
  if (state.type !== "active") return stay();
  const s = state.session;
  const set = (session: Session, effects: readonly Effect[] = []): Transition =>
    ({ state: { type: "active", session }, effects });
  switch (event.type) {
    case "selection": {
      if (!sameContext(event.context, s.context)) return stay();
      const target = { context: s.context, captured: event.selection };
      switch (s.phase.type) {
        case "selectingText":
          return set({ ...s, target, phase: { type: "editing", text: "" } },
            [{ type: "show", surface: "editor" }]);
        case "selectingVoice": {
          const p = s.phase;
          const phase: Phase = !p.recording ? { type: "startingVoice" }
            : p.finishRequested ? { type: "transcribing" } : { type: "recording" };
          return set({ ...s, target, phase }, p.recording && p.finishRequested
            ? [{ type: "transcribe", context: s.context }] : []);
        }
        default: return stay(); // legal event, invalid for this subset's phase
      }
    }
    case "recordingStarted":
      if (!sameContext(event.context, s.context)) return stay();
      if (s.phase.type === "selectingVoice") {
        return set({ ...s, phase: { ...s.phase, recording: true } });
      }
      return s.phase.type === "startingVoice"
        ? set({ ...s, phase: { type: "recording" } }) : stay();
    case "finishVoice":
      if (s.phase.type === "selectingVoice" && s.phase.recording) {
        if (s.phase.finishRequested) return stay();
        return set({ ...s, phase: { ...s.phase, finishRequested: true } },
          [{ type: "selectionDeadline", context: s.context }]);
      }
      if (s.phase.type === "selectingVoice" || s.phase.type === "startingVoice") {
        return { state: { type: "idle" }, effects: [{ type: "close" }] };
      }
      return s.phase.type === "recording"
        ? set({ ...s, phase: { type: "transcribing" } },
            [{ type: "transcribe", context: s.context }]) : stay();
    default: return assertNever(event);
  }
}
```

Why this slice matters: native selection and recorder startup race. Releasing while recording has started but selection is pending requests a deadline, **not immediate transcription**. The current controller's deadline is 600 ms and supplies an empty selection if necessary. Releasing before startup finishes instead closes the capture. Repeated finish and all events after teardown are inert. Preserve these distinctions before optimizing anything. [S1, S9]

The complete port keeps `voice: VoiceGesture` alongside `lifecycle`, exactly as Swift does. Add the other phase members as independent union members, e.g. `{ type: "saving"; request: SaveRequest }` and `{ type: "saveFailed"; request: SaveRequest; message: string; retryable: boolean }`, not `isSaving`, `error?`, and `request?` on a single bag of optional fields.

### Test idiom (Vitest)

This directly exercises the excerpt; the real port should retain Swift test names/scenarios and assert both state and ordered effects:

```ts
import { expect, test } from "vitest";

test("release waits for selection; teardown is terminal and idempotent", () => {
  const context = { stackID: "stack-1", noteID: "note-1", createdAt: 123000 };
  let state: State = update({ type: "idle" },
    { type: "begin", mode: "voice", context }).state;
  state = update(state, { type: "recordingStarted", context }).state;
  const finish = update(state, { type: "finishVoice" });
  expect(finish.effects).toEqual([{ type: "selectionDeadline", context }]);
  expect(update(finish.state, { type: "finishVoice" }).effects).toEqual([]);
  const stale = update(finish.state, {
    type: "selection", context: { ...context, createdAt: 124000 },
    selection: { text: "wrong", screenRect: null },
  });
  expect(stale.state).toBe(finish.state);
  expect(stale.effects).toEqual([]);
  const arrived = update(finish.state, {
    type: "selection", context, selection: { text: "quote", screenRect: null },
  });
  expect(arrived.effects).toEqual([{ type: "transcribe", context }]);
  const stopped = update(arrived.state, { type: "teardown" });
  expect(stopped.effects).toEqual([{ type: "close" }]);
  expect(update(stopped.state, { type: "teardown" }).effects).toEqual([]);
  expect(update(stopped.state, { type: "begin", mode: "voice", context }).state)
    .toEqual({ type: "tornDown" });
});
```

## Effect ownership, cancellation, and native results

The reducer describes effects but never starts them. Port the existing controller's pending-event queue and drain guard: publish each next state before running its ordered effects; synchronous callbacks enqueue events rather than recursively running the controller. [S9]

Recommended controller contract:

1. An app/bootstrap owner creates the controller once, independent of panel mount/hide. Each work slot (`selection`, `selectionDeadline`, `insertion`, `failure`) retains `{token, context, abortController, promise}`. Replacing a slot aborts its predecessor. Recorder ownership is explicit too. [S9; proposed TS adaptation]
2. Check cancellation before calling a port and after awaiting it. Apply an event only if the slot token is still current, the complete context matches, the runtime generation matches, and the reducer still accepts the phase. In `finally`, clear a slot **only if its token still matches**; an old promise must not clear the new task's handle. Catch rejected promises rather than dropping them.
3. `AbortController` is cooperative signaling, not magical cancellation of arbitrary promises or Swift tasks. The bridge must map an operation ID to a native cancellation handle and acknowledge/settle canceled work; also drop stale callbacks even when native cancellation loses a race. The DOM specification explicitly says promises have no built-in abort mechanism. [W7]
4. Make `close` cancel session work/discard recording and close the panel. Make terminal `teardown` take that same path once, then unsubscribe streams, discard surfaces, and release store references. Hiding a React component is not app shutdown. React Strict Mode deliberately repeats effect setup/cleanup in development; UI cleanup should unsubscribe, not permanently tear down a singleton controller. [S9, W8]
5. Save ownership remains with the serialized store queue, not the panel's selection task. Dismissing capture drops late UI outcomes but does not pretend an already-enqueued durable write was undone. Native cancellation cannot roll back an atomic write that already completed. Require an explicit commit acknowledgement; after runtime death/reload, reconcile by reloading storage before retrying. [S2, S7; proposed bridge recovery rule]
6. Use one authoritative TS runtime for app logic and persistence. If the shell creates multiple webviews, they must not each instantiate independent stores writing `store.json`. Route their events to the owner and publish snapshots. Owner-runtime lifetime and crash recovery are shell-spike requirements, still unproven here.

Validate incoming bridge values at runtime before constructing domain events: `unknown` is not `CaptureEvent` merely because of a TypeScript cast. Include protocol version, runtime generation, request/stream ID, and relevant context. Keep raw transcript/selection text out of routine diagnostics.

## How the Swift tests port

Recommend **Vitest in Node for domain and controller behavior**, with a separate static `tsc --noEmit` gate. Vitest integrates Vite config, supports single-run `vitest run`, and has explicit type-test support (`expectTypeOf`/`assertType`); use type checks in addition to runtime tests. With Bun as package manager, use `bun run test`, not `bun test` (the latter invokes Bun's runner). [W9, W10]

| Existing coverage | Port strategy / acceptance criterion |
| --- | --- |
| Capture save and voice gesture tests | Keep the event sequences and exact effect order. `XCTAssertEqual` becomes `expect(...).toEqual(...)`; unwrap helpers should throw/fail, not skip. Keep destination/source separation, frozen drafts, retry using the same request, wrong-key release, and early-release permutations. [S7, S10] |
| Other pure machine tests | Fresh initial state per test, fixed IDs/dates, assert illegal events leave state and effects unchanged. Table-test context mismatches one field at a time and every event after terminal teardown. [S11] |
| Store tests | Replace actor/continuation fakes with injected deferred promises. Resolve commits in controlled order; assert no optimistic publication, halt/retry, queue order, teardown cancellation, and stale success/error after teardown. Do not use arbitrary sleeps to make races pass. [S2, S12] |
| Persistence tests | Keep an in-memory port suite plus real temporary-directory native integration tests. Cover missing, corrupt, invalid, future-version, failed atomic writes, quarantine name collisions, and concurrent requests. The TS codec and native file operation must be tested together against v4 fixtures. [S3, S13] |
| Composer/templates/mutations | Exact expected strings and documents, no broad auto-updated snapshots. Fix locale/time zone/calendar through injected formatting; test empty stacks, multi-day stacks, blank quote lines, built-in IDs, normalized name collisions, and undo/clear semantics. [S5, S6, S11] |
| Swift controller tests | Move policy scenarios to TS using fake native ports; retain Swift tests for actual native boundaries. Add cancellation-before-call, cancellation-during-call, stale completion after slot replacement, teardown twice, and bridge disconnect/reload. [S9] |

Parity gate: maintain a checklist mapping every existing test method to a TS test or a documented native-only test. Run identical serialized event traces and v4 fixture cases against Swift and TS during the later migration; do not silently “improve” behavior while translating. The exact screenshot/DOM test stack remains the map's separate tooling decision; Node tests cannot prove WebKit focus, panel ordering, Accessibility permissions, microphone cancellation, or shell latency.

## Unconfirmed / follow-up gates

- No framework bundle, resident memory, idle CPU, transcript-to-paint latency, or agent productivity measurements were made. Do not treat this recommendation as a performance result.
- No full CaptureState translation has been compiled or differential-tested. The excerpt demonstrates the idiom and a consequential race, not port completion.
- The single authoritative TS runtime's survival while windows are hidden, native cancellation settlement, multi-window routing, and recovery after web-content process termination need the shell spike.
- Exact Codable v4 interoperability, Unicode folding parity, localized date parity, and date precision need fixtures. These are compatibility risks, not reasons to retain app policy in Swift indefinitely.
- Framework-specific minimum WebKit support and final package versions must be pinned and verified on Sendpoint's minimum supported macOS in the implementation spike. No blanket compatibility claim is made here.

## Primary sources

Repository links are pinned to the investigated commit; external documentation was consulted on 2026-09-30.

- **S1** [CaptureState.swift](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Sources/SendpointDomain/CaptureState.swift): phases 57–68; events/effects 112–163; transitions 184–389; begin/gesture helpers 391–458; context/target 461–497.
- **S2** [StackStore.swift](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Sources/SendpointDomain/StackStore.swift): selected versus committed stack 54–66; load 88–111; teardown 163–172; queue/commit 174–253.
- **S3** [StorePersistence.swift](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Sources/SendpointDomain/StorePersistence.swift): injected operations 20–60; codec/load/quarantine/atomic write 63–160.
- **S4** [Models.swift](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Sources/SendpointDomain/Models.swift): value models, v4, five stacks.
- **S5** [PromptComposer.swift](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Sources/SendpointDomain/PromptComposer.swift): date policies, ordered Markdown blocks, empty quote lines.
- **S6** [Template.swift](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Sources/SendpointDomain/Template.swift): built-in IDs and content.
- **S7** [CaptureSaveLifecycleTests.swift](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Tests/SendpointDomainTests/CaptureSaveLifecycleTests.swift): source/destination, deferred selection, retries, stale outcomes, dismissal.
- **S8** [TextNormalization.swift](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Sources/SendpointDomain/TextNormalization.swift).
- **S9** [CaptureController.swift](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Sources/Sendpoint/Capture/CaptureController.swift): pending drain 196–204; effects 206–262; task ownership/cancellation/teardown 264–297.
- **S10** [CaptureVoiceGestureTests.swift](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Tests/SendpointDomainTests/CaptureVoiceGestureTests.swift).
- **S11** [Domain tests directory](https://github.com/saiashirwad/sendpoint/tree/3288cbacb3872f65845636e843319adc203b074c/Tests/SendpointDomainTests).
- **S12** [StackStoreTests.swift](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Tests/SendpointDomainTests/StackStoreTests.swift).
- **S13** [StorePersistenceTests.swift](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/Tests/SendpointDomainTests/StorePersistenceTests.swift).
- **W1** [TypeScript handbook: discriminated unions and exhaustiveness](https://www.typescriptlang.org/docs/handbook/2/narrowing.html#discriminated-unions).
- **W2** [React: useSyncExternalStore](https://react.dev/reference/react/useSyncExternalStore).
- **W3** [Solid: signals](https://docs.solidjs.com/concepts/signals).
- **W4** [Svelte: $state, $state.raw, cross-module restrictions](https://svelte.dev/docs/svelte/$state).
- **W5** [Preact: signals, readonly exposure, disposal, direct DOM text binding](https://preactjs.com/guide/v10/signals/).
- **W6** [XState: invocation, actor lifecycle, actions versus actors](https://stately.ai/docs/invoke).
- **W7** [WHATWG DOM: aborting ongoing activities](https://dom.spec.whatwg.org/#aborting-ongoing-activities).
- **W8** [React: StrictMode](https://react.dev/reference/react/StrictMode).
- **W9** [Vitest: getting started and execution commands](https://vitest.dev/guide/).
- **W10** [Vitest: testing types](https://vitest.dev/guide/testing-types).
