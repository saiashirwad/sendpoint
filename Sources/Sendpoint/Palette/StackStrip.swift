import SwiftUI

struct StackStrip: View {
    let stacks: [StackItemFacts]
    var size: CGFloat = 11
    var accent: Color
    var onSelect: ((Int) -> Void)?

    private static let hitPadding: CGFloat = 6

    var body: some View {
        HStack(spacing: onSelect == nil ? size * 0.75 : 0) {
            ForEach(stacks) { stack in
                numeral(stack)
            }
        }
        .padding(.trailing, onSelect == nil ? 0 : -Self.hitPadding)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func numeral(_ stack: StackItemFacts) -> some View {
        let label = Text("\(stack.number)")
            .font(.ui(size, weight: stack.isCurrent ? .semibold : .medium).monospacedDigit())
            .foregroundStyle(color(stack))
            .accessibilityLabel("\(stack.name), \(stack.countLabel)\(stack.isCurrent ? ", current" : "")")
        if let onSelect {
            Button { onSelect(stack.number) } label: {
                label
                    .padding(.horizontal, Self.hitPadding)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(stack.name) · \(stack.countLabel)")
        } else {
            label
        }
    }

    private func color(_ stack: StackItemFacts) -> AnyShapeStyle {
        if stack.isCurrent { return AnyShapeStyle(accent) }
        return stack.isEmpty ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.primary)
    }
}

struct StackReadoutLabel: View {
    let stack: StackItemFacts
    var numeralSize: CGFloat
    var detailSize: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: numeralSize * 0.4) {
            Text("\(stack.number)")
                .font(.ui(numeralSize, weight: .semibold).monospacedDigit())
                .frame(width: numeralSize * 0.8)
            Text(stack.isEmpty ? "Empty" : stack.countLabel)
                .font(.ui(detailSize).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(stack.noteCount)))
                .frame(width: detailSize * 5.2, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stack.name), \(stack.countLabel)")
    }
}
