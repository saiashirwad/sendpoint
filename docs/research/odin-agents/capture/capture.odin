package capture

// Executable translation of CaptureState's voice/selection rendezvous, not a full port.
// Text is borrowed: caller must keep buffers alive through session termination.
Capture_Context :: struct { stack_id, note_id: u64, created_at: i64 }
Selecting_Voice :: struct { recording, finish_requested: bool }
Starting_Voice :: struct {}
Recording :: struct {}
Transcribing :: struct {}
Editing :: struct { text: string }
Phase :: union #no_nil {Selecting_Voice, Starting_Voice, Recording, Transcribing, Editing}
Session :: struct { capture_context: Capture_Context, phase: Phase, selection: string }
Idle :: struct {}
Torn_Down :: struct {}
Lifecycle :: union #no_nil {Idle, Session, Torn_Down}
Capture_State :: struct { lifecycle: Lifecycle }
Begin :: struct { capture_context: Capture_Context }
Selection :: struct { capture_context: Capture_Context, text: string }
Recording_Started :: struct { capture_context: Capture_Context }
Transcript :: struct { capture_context: Capture_Context, text: string }
Finish_Voice :: struct {}
Dismiss :: struct {}
Teardown :: struct {}
Event :: union #no_nil {Begin, Selection, Recording_Started, Transcript, Finish_Voice, Dismiss, Teardown}
Effect :: enum {Show_Voice, Start_Recording, Read_Selection, Selection_Deadline, Transcribe, Close, Beep}
// Fixed capacity avoids allocator ownership in the pure transition result.
Effects :: struct { values: [3]Effect, count: int }
emit :: proc(values: ..Effect) -> Effects {
    result: Effects
    assert(len(values) <= len(result.values))
    for value, i in values { result.values[i] = value }
    result.count = len(values)
    return result
}

update :: proc(state: ^Capture_State, event: Event) -> Effects {
    if _, dead := state.lifecycle.(Torn_Down); dead { return {} }
    switch e in event {
    case Teardown:
        state.lifecycle = Torn_Down{}
        return emit(.Close)
    case Begin:
        if _, idle := state.lifecycle.(Idle); !idle { return emit(.Beep) }
        state.lifecycle = Session{e.capture_context, Selecting_Voice{}, ""}
        return emit(.Show_Voice, .Start_Recording, .Read_Selection)
    case Dismiss:
        if _, active := state.lifecycle.(Session); active {
            state.lifecycle = Idle{}
            return emit(.Close)
        }
    case Selection, Recording_Started, Transcript, Finish_Voice:
        session, active := state.lifecycle.(Session)
        if !active { return {} }
        effects: Effects
        switch value in event {
        case Selection:
            if value.capture_context != session.capture_context { return {} }
            phase, ok := session.phase.(Selecting_Voice)
            if !ok { return {} }
            session.selection = value.text
            if !phase.recording { session.phase = Starting_Voice{} }
            else if phase.finish_requested {
                session.phase = Transcribing{}
                effects = emit(.Transcribe)
            } else { session.phase = Recording{} }
        case Recording_Started:
            if value.capture_context != session.capture_context { return {} }
            switch phase in session.phase {
            case Selecting_Voice:
                session.phase = Selecting_Voice{true, phase.finish_requested}
            case Starting_Voice: session.phase = Recording{}
            case Recording, Transcribing, Editing: return {}
            }
        case Finish_Voice:
            switch phase in session.phase {
            case Selecting_Voice:
                if !phase.recording {
                    state.lifecycle = Idle{}
                    return emit(.Close)
                }
                if phase.finish_requested { return {} }
                session.phase = Selecting_Voice{true, true}
                effects = emit(.Selection_Deadline)
            case Starting_Voice:
                state.lifecycle = Idle{}
                return emit(.Close)
            case Recording:
                session.phase = Transcribing{}
                effects = emit(.Transcribe)
            case Transcribing, Editing: return {}
            }
        case Transcript:
            if value.capture_context != session.capture_context { return {} }
            if _, ok := session.phase.(Transcribing); !ok { return {} }
            // Deliberate spike endpoint: production commits a CaptureSaveRequest here.
            session.phase = Editing{value.text}
        case Begin, Dismiss, Teardown: return {}
        }
        state.lifecycle = session
        return effects
    }
    return {}
}

// Injected boundary: a retained opaque handle and userdata replace capturing closures.
// This fakeable owner is single-threaded; native completions must enqueue on its thread.
Boundary :: struct {
    userdata: rawptr,
    cancel: proc(userdata: rawptr, handle: u64),
}
Owner :: struct { state: Capture_State, boundary: Boundary, handle: u64 }
send :: proc(owner: ^Owner, event: Event) -> Effects {
    effects := update(&owner.state, event)
    for effect in effects.values[:effects.count] {
        if effect == .Close && owner.handle != 0 {
            handle := owner.handle
            owner.handle = 0 // detach before cancel; cancel must not call send recursively
            owner.boundary.cancel(owner.boundary.userdata, handle)
        }
    }
    return effects
}
