import SwiftUI

// MARK: - Lines and small controls

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

struct QuietButton: View {
    let title: String
    var keys: String? = nil
    let action: () -> Void
    @State private var hovering = false

    init(_ title: String, keys: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.keys = keys
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
        .foregroundStyle(hovering ? Color.primary : Color.secondary)
        .onHover { hovering = $0 }
    }
}

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

struct InkButton: View {
    let title: String
    var keys: String? = nil
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

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
            .foregroundStyle(isEnabled ? AnyShapeStyle(Ink.paper(scheme)) : AnyShapeStyle(.primary))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(isEnabled ? Color.primary : Color.primary.opacity(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct PillButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ui(12, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .foregroundStyle(.primary)
                .background(Capsule().fill(hovering && isEnabled ? Ink.raised(scheme) : .clear))
                .overlay(Capsule().strokeBorder(
                    Color.primary.opacity(hovering && isEnabled ? 0.22 : 0.14), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct GlyphButton<Glyph: View>: View {
    let label: String
    var isProminent = false
    let action: () -> Void
    @ViewBuilder let glyph: () -> Glyph
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            glyph()
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(isProminent || hovering ? Color.primary : Color.secondary)
                .opacity(isEnabled ? 1 : 0.35)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
    }
}

extension GlyphButton where Glyph == Image {
    init(systemName: String, label: String, action: @escaping () -> Void) {
        self.init(label: label, action: action) { Image(systemName: systemName) }
    }
}

struct FloppyGlyph: View {
    var body: some View {
        FloppyOutline()
            .stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            .frame(width: 15, height: 15)
    }
}

private struct FloppyOutline: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        let radius = 0.14 * rect.width
        var path = Path()
        path.move(to: point(0.14, 0))
        path.addLine(to: point(0.74, 0))
        path.addLine(to: point(1, 0.26))
        path.addArc(tangent1End: point(1, 1), tangent2End: point(0, 1), radius: radius)
        path.addArc(tangent1End: point(0, 1), tangent2End: point(0, 0), radius: radius)
        path.addArc(tangent1End: point(0, 0), tangent2End: point(1, 0), radius: radius)
        path.closeSubpath()
        path.move(to: point(0.3, 0))
        path.addLine(to: point(0.3, 0.3))
        path.addLine(to: point(0.66, 0.3))
        path.addLine(to: point(0.66, 0))
        path.move(to: point(0.24, 1))
        path.addLine(to: point(0.24, 0.58))
        path.addLine(to: point(0.76, 0.58))
        path.addLine(to: point(0.76, 1))
        return path
    }
}

struct Chip: View {
    let title: String
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

struct ChoiceMenu<Choices: View>: View {
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
        Chip(title: "Reading", isSelected: true) {}
        Chip(title: "Writing", isSelected: false) {}
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
