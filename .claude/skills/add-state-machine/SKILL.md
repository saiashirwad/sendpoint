---
name: add-state-machine
description: How to add a new Sendpoint state machine and its controller by copying CaptureState/CaptureController. Use before adding a workflow, machine, or controller.
---

# Adding a new state machine

Copy Capture. Do not add a base type. Put the Event / Effect / State / `update` file in SendpointDomain. Mark the types public. Keep AppKit and SwiftUI out of that file. Put the XController in the app. Put transition tests in SendpointDomainTests.

1. Add the machine file in `Sources/SendpointDomain`. Import Foundation, and CoreGraphics only when a value needs it. No AppKit. Add a closed event enum, a closed effect enum, and a state value whose lifecycle includes `tornDown`. `CaptureState.Lifecycle` is `idle`, `active`, or `tornDown`. One `mutating func update(_ event:) -> [Effect]` is the only transition. Once `tornDown`, `update` returns no effects. Mark the types `public`. Mark properties, methods, and initializers `public` when the app or the tests call them. Write a public init when another module constructs the value.
2. Add an XController in the app folder that owns the workflow. It owns the state, a pending event queue, and the task handles. `send` appends and drains, as `CaptureController.send` does. One method performs the effects. Store each async `Task` on the controller and cancel it from that owner. Check cancellation around the external call. Apply the result only when its full context still matches, as `CaptureController.launch` requires `state.session?.context == context` after the await. `teardown()` sends `.teardown`, then drops surfaces, the store, and callbacks. A second call returns without sending.
3. Inject the system boundary as a small struct of closures, the way `CaptureController` takes `VoiceRecorder` and `CaptureSurfaces`. Tests pass fakes and do not open AppKit windows.
4. Test the controller in `Tests/SendpointTests`, using `CaptureControllerTests` as the model. Cover cancellation (`testModeChangeMidCaptureCancelsIt`), a stale result (`testDismissBeforeTheSelectionArrivesRejectsTheLateResult`), an invalid transition (`testRejectedDestinationChoicesDoNotChangeTheCurrentStack`: the wrong context or an unknown stack does nothing), and teardown (`testTeardownClosesDiscardsAndIgnoresEverythingAfter`: a second teardown is a no-op and later events do nothing). Put transition tests that only drive `update` in `Tests/SendpointDomainTests`. `CaptureSaveLifecycleTests` drives `CaptureState.update` directly for ignored events (`testStaleOutcomesAreIgnored`; a second `.selection` returns `[]`).
5. Construct a controller that does not need the store in `AppEnvironment.init`, where `captureController` is created. Read it from `AppDelegate` the way `captureController` is read. A controller that needs `StackStore` cannot be built there. `AppDelegate.bootstrapStore` creates `StackSelector` only after the store has loaded. Follow that call site.

# The shape to copy

Copy `CaptureState` and `CaptureController`. There is no shared generic runtime. The machines differ, so copy this shape instead of adding a base type. The pure machines and the action catalog live in SendpointDomain. Controllers stay in the app folders.

The vocabulary is Event, `update`, Effect, and an XController.

`CaptureEvent` comes in. `CaptureEffect` goes out. `CaptureState` is a value. Its lifecycle is `idle`, `active`, or `tornDown`. `update(_ event:) -> [CaptureEffect]` is the only transition. Teardown is idempotent: `.teardown` sets `tornDown` and returns `[.close]`; once `tornDown`, `update` returns no effects.

`CaptureController` owns the state, a pending event queue, and the task handles. `send` appends and drains. `run` performs effects. Async work is a `Task` stored on the controller. `launch` checks cancellation around the call and applies the event only when `state.session?.context` still matches. `teardown()` returns if the state is already torn down. Otherwise it sends `.teardown`, then drops the surfaces, the store, and `onAccessibilityRequired`.

`VoiceMachine` (driven by `VoiceNoteService`), `StackSelectMachine` (driven by `StackSelector`), and `ExportController` (`ExportState` in the same file) already follow this shape. `PaletteWorkflow` is the palette's own machine. Its transition is `PaletteUpdate.update`, which returns `Bool` and appends `PaletteEffect`. Copy Capture for a new machine.

The permission machine and the latest-note machine live in SendpointDomain. `PermissionController` and `LatestNoteEditor` are the controllers.

`TemplateEditorState`, `SurfaceState`, and `AutomaticSelectionTracker` live in SendpointDomain. `TemplateEditorController`, `SurfaceCoordinator`, and `AutomaticSelectionMonitor` are the controllers.

