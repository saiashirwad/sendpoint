struct ShortcutFeedback {
    struct Issue: Identifiable {
        let id: ShortcutSlot
        let text: String
    }

    let issues: [Issue]
    let feedback: String?

    init(slots: [ShortcutSlot], registrationIssues: [ShortcutRegistrationIssue], feedback: String?) {
        let includedSlots = Set(slots)
        issues = registrationIssues.filter { includedSlots.contains($0.id) }.map {
            Issue(id: $0.id, text: "\($0.id.title): \($0.message)")
        }
        self.feedback = feedback
    }

    var isVisible: Bool { !issues.isEmpty || feedback != nil }

    var announcement: String {
        let parts = issues.map(\.text) + (feedback.map { [$0] } ?? [])
        return parts.joined(separator: " ")
    }
}
