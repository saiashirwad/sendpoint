import SendpointDomain
import SwiftUI

struct SettingsStacksPane: View {
    @Bindable var shortcuts: ShortcutSettings
    let storeHandle: SettingsStoreHandle
    let hotKeyRegistrar: HotKeyRegistrar
    let onSettingsChanged: () -> Void

    var body: some View {
        let store = storeHandle.store
        let facts = store.map(StackUIFacts.init(store:))
        SettingsPage {
            SettingsSection("Stacks") {
                ShortcutRows(
                    specs: ShortcutSlot.selectStackCases.map { ShortcutSpec(title: $0.title, slot: $0) },
                    shortcuts: shortcuts,
                    hotKeyRegistrar: hotKeyRegistrar,
                    onSettingsChanged: onSettingsChanged
                ) { spec in
                    StackShortcutLabel(title: spec.title, stack: facts?.stack(for: spec.slot)) { id in
                        store?.mutate(.switchStack(stackID: id))
                    }
                }
            }
            SettingsSection("Current stack") {
                ShortcutRows(
                    specs: [
                        ShortcutSpec(title: "Show the stack", slot: .stack),
                        ShortcutSpec(title: "Clear stack", hint: "⌘Z undoes", slot: .clear),
                    ],
                    shortcuts: shortcuts,
                    hotKeyRegistrar: hotKeyRegistrar,
                    onSettingsChanged: onSettingsChanged
                )
            }
        }
    }
}

private struct StackShortcutLabel: View {
    let title: String
    let stack: StackItemFacts?
    let onSelect: (UUID) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let stack {
            Button { onSelect(stack.id) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("\(stack.number)")
                        .font(.ui(14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(stack.isCurrent ? AnyShapeStyle(Ink.accent(scheme)) : AnyShapeStyle(.primary))
                        .frame(width: 12)
                    Text(stack.isEmpty ? "Empty" : stack.countLabel)
                        .font(.ui(14, weight: .medium))
                        .foregroundStyle(stack.isEmpty ? .secondary : .primary)
                        .frame(width: 84, alignment: .leading)
                    if stack.isCurrent {
                        SettingsLabel("Current")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(stack.name), \(stack.countLabel)\(stack.isCurrent ? ", current" : "")")
            .accessibilityHint(stack.isCurrent ? "" : "Makes this the current stack")
        } else {
            ShortcutTitle(spec: ShortcutSpec(title: title, slot: .stack))
        }
    }
}

private extension StackUIFacts {
    func stack(for slot: ShortcutSlot) -> StackItemFacts? {
        guard case let .selectStack(number) = slot else { return nil }
        return stack(number: number)
    }
}
