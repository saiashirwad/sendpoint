import SwiftUI

// MARK: - Lines and small controls

/// One device pixel of rule.
struct Hairline: View {
    var axis: Axis = .horizontal
    @Environment(\.displayScale) private var scale

    var body: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(
                width: axis == .vertical ? 1 / scale : nil,
                height: axis == .horizontal ? 1 / scale : nil
            )
    }
}

/// A key drawn as a key: raised, edged, mono.
struct Keycap: View {
    let text: String
    var size: CGFloat = 11
    var isMuted = false
    @Environment(\.colorScheme) private var scheme

    init(_ text: String, size: CGFloat = 11, isMuted: Bool = false) {
        self.text = text
        self.size = size
        self.isMuted = isMuted
    }

    var body: some View {
        Text(text)
            .font(.mono(size, weight: .medium))
            .tracking(size * 0.06)
            .foregroundStyle(isMuted ? Color.secondary : Color.primary.opacity(0.8))
            .padding(.horizontal, size * 0.8)
            .frame(height: size * 2.2)
            .background(
                RoundedRectangle(cornerRadius: size * 0.5, style: .continuous)
                    .fill(isMuted ? Color.clear : Ink.raised(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.5, style: .continuous)
                    .strokeBorder(Ink.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(scheme == .dark || isMuted ? 0 : 0.04), radius: 1, y: 1)
    }
}

/// A verb, optionally a key. Secondary until the pointer arrives.
struct QuietButton: View {
    let title: String
    var keys: String? = nil
    var hoverColor: Color = .primary
    let action: () -> Void
    @State private var hovering = false

    init(_ title: String, keys: String? = nil, hoverColor: Color = .primary, action: @escaping () -> Void) {
        self.title = title
        self.keys = keys
        self.hoverColor = hoverColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(title)
                    .font(.ui(12.5, weight: .medium))
                    .lineLimit(1)
                if let keys {
                    Keycap(keys, size: 10.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? hoverColor : Color.secondary)
        .onHover { hovering = $0 }
    }
}

/// Lays children out left to right, wrapping to a new line when the width
/// runs out. Chips live in one of these.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return place(in: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = place(in: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, layout.origins) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func place(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + lineHeight), origins)
    }
}

/// The one filled button: ink on paper, the same shape as a selected chip.
struct InkButton: View {
    let title: String
    var keys: String? = nil
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    init(_ title: String, keys: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.keys = keys
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.ui(12.5, weight: .medium))
                if let keys {
                    Text(keys)
                        .font(.mono(10.5, weight: .medium))
                        .opacity(0.55)
                }
            }
            .foregroundStyle(Ink.paper(scheme))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(Color.primary))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A small outlined verb, for a row's trailing action.
struct PillButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ui(12, weight: .medium))
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(Capsule().fill(hovering ? Ink.raised(scheme) : .clear))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(hovering ? 0.22 : 0.14), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Footer-weight icon: secondary until the pointer is on it.
struct QuietIconButton: View {
    let systemName: String
    var hoverColor: Color = .primary
    let action: () -> Void
    @State private var hovering = false

    init(_ systemName: String, hoverColor: Color = .primary, action: @escaping () -> Void) {
        self.systemName = systemName
        self.hoverColor = hoverColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? hoverColor : Color.secondary)
        .onHover { hovering = $0 }
    }
}

/// One option in a row of chips. The chosen one is set in ink.
struct Chip: View {
    let title: String
    var count: Int? = nil
    let isSelected: Bool
    var isDirty = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.ui(13, weight: .medium))
                    .lineLimit(1)
                if let count {
                    Text("\(count)")
                        .font(.mono(11))
                        .opacity(0.55)
                }
                if isDirty {
                    Circle()
                        .fill(Ink.accent(scheme))
                        .frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(isSelected ? Ink.paper(scheme) : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(isSelected ? Color.primary : Color.primary.opacity(hovering ? 0.09 : 0.055)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The "+" at the end of a chip row.
struct AddChip: View {
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(Color.primary.opacity(hovering ? 0.24 : 0.14), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
    }
}

/// Chips for a closed set of values.
struct ChoiceChips<Value: Hashable>: View {
    let values: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(values, id: \.self) { value in
                Chip(title: title(value), isSelected: value == selection) {
                    selection = value
                }
            }
        }
    }
}

/// An ink switch: solid when on, a hairline track when off.
struct InkToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                configuration.isOn.toggle()
            }
        } label: {
            SwitchTrack(isOn: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

private struct SwitchTrack: View {
    let isOn: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack {
            if isOn { Spacer(minLength: 0) }
            Circle()
                .fill(isOn ? Ink.paper(scheme) : Ink.raised(scheme))
                .overlay(Circle().strokeBorder(Color.primary.opacity(isOn ? 0 : 0.10), lineWidth: 0.75))
                .frame(width: 14, height: 14)
            if !isOn { Spacer(minLength: 0) }
        }
        .padding(2)
        .frame(width: 32, height: 18)
        .background(Capsule().fill(isOn ? Color.primary.opacity(0.9) : Color.primary.opacity(0.08)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(isOn ? 0 : 0.10), lineWidth: 1))
        .contentShape(Capsule())
        .animation(.snappy(duration: 0.2), value: isOn)
    }
}

/// A pill that opens a menu of choices, for a set too long or too
/// changeable for chips.
struct ChoiceMenu<ID: Hashable, Choices: View>: View {
    let title: String
    let width: CGFloat
    @ViewBuilder let choices: () -> Choices
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Menu(content: choices) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.ui(12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .frame(width: width, height: 28)
            .background(Capsule().fill(Color.primary.opacity(hovering ? 0.09 : 0.055)))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
    }
}

// MARK: - Previews

#Preview("Chip") {
    HStack(spacing: 8) {
        Chip(title: "Reading", count: 3, isSelected: true) {}
        Chip(title: "Writing", count: 12, isSelected: false) {}
        Chip(title: "Draft", isSelected: false, isDirty: true) {}
    }
    .padding()
}

#Preview("Keycap") {
    HStack(spacing: 8) {
        Keycap("⌘K")
        Keycap("esc", isMuted: true)
        Keycap("↩", size: 10)
    }
    .padding()
}
