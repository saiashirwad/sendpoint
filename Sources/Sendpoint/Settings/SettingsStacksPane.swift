import SendpointDomain
import SwiftUI

/// Every stack change the settings stacks page can make. Both entry points —
/// the chips and the new-stack popover — funnel through `send(to:)`, so the
/// views own no store transaction. The mutation sequence is unchanged:
/// creating a stack selects it too, and the explicit switch after a create is
/// kept as the harmless no-op it already was.
enum StackSettingsIntent: Equatable {
    case switchTo(stackID: UUID)
    case createAndSwitch(Stack)

    func send(to store: StackStore) {
        switch self {
        case .switchTo(let stackID):
            guard stackID != store.currentStackID else { return }
            store.mutate(.switchStack(stackID: stackID))
        case .createAndSwitch(let stack):
            store.mutate(.createStack(stack))
            store.mutate(.switchStack(stackID: stack.id))
        }
    }
}

struct SettingsStacksPane: View {
    @Bindable var shortcuts: ShortcutSettings
    let storeHandle: SettingsStoreHandle
    let hotKeyRegistrar: HotKeyRegistrar
    let onSettingsChanged: () -> Void

    @State private var newStack: NameDraft?

    private struct NameDraft: Equatable {
        var name: String
        var problem: String?
    }

    var body: some View {
        SettingsPage {
            if let store = storeHandle.store {
                SettingsSection("Active stack", footnote: "New notes land here. Pasting uses only this stack.") {
                    SettingsStackedRow {
                        StackChips(store: store, onNew: { newStack = NameDraft(name: "") })
                            .popover(
                                isPresented: Binding(
                                    get: { newStack != nil },
                                    set: { if !$0 { newStack = nil } }
                                ),
                                arrowEdge: .bottom
                            ) {
                                NamePopover(
                                    prompt: "Name the new stack",
                                    placeholder: "Stack name",
                                    name: Binding(
                                        get: { newStack?.name ?? "" },
                                        set: { newStack?.name = $0; newStack?.problem = nil }
                                    ),
                                    problem: newStack?.problem,
                                    onCommit: { create(in: store) }
                                )
                            }
                    }
                }
            }
            SettingsSection("Shortcuts") {
                ShortcutRows(
                    specs: [
                        ShortcutSpec(title: "Show the stack", slot: .stack),
                        ShortcutSpec(title: "Switch stack", hint: "Hold to pick with ↑↓", slot: .switchStack),
                        ShortcutSpec(title: "Next stack", slot: .nextStack),
                        ShortcutSpec(title: "Previous stack", slot: .previousStack),
                        ShortcutSpec(title: "Clear stack", hint: "⌘Z undoes", slot: .clear),
                    ],
                    shortcuts: shortcuts,
                    hotKeyRegistrar: hotKeyRegistrar,
                    onSettingsChanged: onSettingsChanged
                )
            }
        }
    }

    private func create(in store: StackStore) {
        guard let draft = newStack else { return }
        let validation = StackNameDraft(text: draft.name, excludedStackID: nil).validation(stacks: store.stacks)
        switch validation {
        case let .invalid(problem):
            newStack?.problem = problem
            NSSound.beep()
        case let .valid(name):
            let stack = Stack(name: name)
            StackSettingsIntent.createAndSwitch(stack).send(to: store)
            newStack = nil
        }
    }
}

/// Every stack as a chip; the current one in ink. Clicking one makes it
/// current, the same as switching in the palette.
private struct StackChips: View {
    let store: StackStore
    let onNew: () -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(store.stacks) { stack in
                Chip(
                    title: stack.name,
                    count: stack.notes.count,
                    isSelected: stack.id == store.currentStackID
                ) {
                    StackSettingsIntent.switchTo(stackID: stack.id).send(to: store)
                }
            }
            AddChip(label: "New stack", action: onNew)
        }
    }
}
