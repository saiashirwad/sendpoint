import SendpointDomain
import SwiftUI

struct StackStrip: View {
    let stacks: [StackItemFacts]
    var size: CGFloat = 11
    var accent: Color
    var onSelect: ((Int) -> Void)?

    private static let hitPadding: CGFloat = Spacing.sm

    var body: some View {
        HStack(spacing: onSelect == nil ? Spacing.sm : 0) {
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
                    .padding(.vertical, Spacing.sm)
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
        return stack.isEmpty ? AnyShapeStyle(Ink.quaternaryStyle) : AnyShapeStyle(Ink.primaryStyle)
    }
}

struct StackReadoutLabel: View {
    let stack: StackItemFacts
    var numeralSize: CGFloat
    var detailSize: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text("\(stack.number)")
                .font(.ui(numeralSize, weight: .semibold).monospacedDigit())
                .frame(width: numeralSize * 0.8)
            Text(stack.isEmpty ? "Empty" : stack.countLabel)
                .font(.ui(detailSize).monospacedDigit())
                .foregroundStyle(Ink.secondaryStyle)
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(stack.noteCount)))
                .frame(width: detailSize * 5.2, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stack.name), \(stack.countLabel)")
    }
}
