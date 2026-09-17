import SwiftUI

struct StackStrip: View {
    let stacks: [StackItemFacts]
    var size: CGFloat = 11
    var accent: Color
    var onSelect: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: size * 0.75) {
            ForEach(stacks) { stack in
                numeral(stack)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func numeral(_ stack: StackItemFacts) -> some View {
        let label = Text("\(stack.number)")
            .font(.mono(size, weight: stack.isCurrent ? .medium : .regular))
            .foregroundStyle(color(stack))
            .accessibilityLabel("\(stack.name), \(stack.countLabel)\(stack.isCurrent ? ", current" : "")")
        if let onSelect {
            Button { onSelect(stack.number) } label: {
                label.frame(minWidth: size * 1.4, minHeight: size * 1.8).contentShape(Rectangle())
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
                .font(.mono(numeralSize, weight: .medium))
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
