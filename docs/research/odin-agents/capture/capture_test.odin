package capture
import "core:testing"

A :: Capture_Context{1, 2, 3}
@(test)
release_before_selection :: proc(t: ^testing.T) {
    s: Capture_State
    testing.expect_value(t, update(&s, Begin{A}).count, 3)
    update(&s, Recording_Started{A})
    testing.expect_value(t, update(&s, Finish_Voice{}), emit(.Selection_Deadline))
    testing.expect_value(t, update(&s, Finish_Voice{}).count, 0)
    testing.expect_value(t, update(&s, Selection{A, "selected"}), emit(.Transcribe))
    update(&s, Transcript{A, "spoken"})
    active := s.lifecycle.(Session)
    testing.expect_value(t, active.phase.(Editing).text, "spoken")
}
@(test)
selection_before_recording :: proc(t: ^testing.T) {
    s: Capture_State
    update(&s, Begin{A})
    update(&s, Selection{A, "selected"})
    active := s.lifecycle.(Session)
    _, starting := active.phase.(Starting_Voice)
    testing.expect(t, starting)
    update(&s, Recording_Started{A})
    testing.expect_value(t, update(&s, Finish_Voice{}), emit(.Transcribe))
}
@(test)
stale_full_context_and_invalid_transition :: proc(t: ^testing.T) {
    s: Capture_State
    update(&s, Begin{A})
    before := s
    // Same note ID alone must not match a different timestamp or stack.
    stale_contexts := []Capture_Context{{1, 2, 4}, {9, 2, 3}, {1, 8, 3}}
    for stale in stale_contexts {
        testing.expect_value(t, update(&s, Selection{stale, "bad"}).count, 0)
        testing.expect_value(t, s, before)
    }
    update(&s, Transcript{A, "too early"})
    testing.expect_value(t, s, before)
    testing.expect_value(t, update(&s, Begin{A}), emit(.Beep))
}
@(test)
finish_before_start_closes :: proc(t: ^testing.T) {
    s: Capture_State
    update(&s, Begin{A})
    testing.expect_value(t, update(&s, Finish_Voice{}), emit(.Close))
    before := s
    update(&s, Recording_Started{A})
    testing.expect_value(t, s, before)
}
Fake :: struct { cancellations: int, last_handle: u64 }
cancel_fake :: proc(data: rawptr, handle: u64) {
    fake := cast(^Fake)data
    fake.cancellations += 1
    fake.last_handle = handle
}
@(test)
cancel_late_result_and_idempotent_teardown :: proc(t: ^testing.T) {
    fake: Fake
    owner := Owner{boundary = Boundary{&fake, cancel_fake}}
    send(&owner, Begin{A})
    owner.handle = 42
    send(&owner, Dismiss{})
    testing.expect_value(t, fake.cancellations, 1)
    testing.expect_value(t, fake.last_handle, u64(42))
    before := owner.state
    send(&owner, Selection{A, "late"})
    testing.expect_value(t, owner.state, before)
    send(&owner, Teardown{})
    testing.expect_value(t, send(&owner, Teardown{}).count, 0)
    testing.expect_value(t, send(&owner, Begin{A}).count, 0)
    testing.expect_value(t, fake.cancellations, 1)
}
@(test)
teardown_active_cancels_once :: proc(t: ^testing.T) {
    fake: Fake
    owner := Owner{boundary = Boundary{&fake, cancel_fake}}
    send(&owner, Begin{A})
    owner.handle = 77
    testing.expect_value(t, send(&owner, Teardown{}), emit(.Close))
    send(&owner, Teardown{})
    send(&owner, Recording_Started{A})
    testing.expect_value(t, fake.cancellations, 1)
    testing.expect_value(t, owner.handle, u64(0))
}
