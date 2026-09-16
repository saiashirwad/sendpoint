import AppKit
import SwiftUI

// MARK: - Type
//
// Two faces. Geist for the interface. Martian Mono, in its narrow width,
// for everything that is a record rather than a sentence: captured
// passages, timestamps, counts, keys, and the small labels over sections.

nonisolated enum Typeface {
    static func sans(_ weight: Font.Weight) -> String {
        switch weight {
        case .semibold, .bold, .heavy, .black: "Geist-SemiBold"
        case .medium: "Geist-Medium"
        default: "Geist-Regular"
        }
    }

    static func mono(_ weight: Font.Weight) -> String {
        switch weight {
        case .medium, .semibold, .bold, .heavy, .black: "MartianMono-NrMd"
        default: "MartianMono-NrRg"
        }
    }
}

extension Font {
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(Typeface.sans(weight), size: size)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(Typeface.mono(weight), size: size)
    }

    static let uiBody = ui(13)
    static let uiCallout = ui(12)
    static let uiCaption = ui(11)
}

extension NSFont {
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> NSFont {
        NSFont(name: Typeface.sans(weight), size: size) ?? .systemFont(ofSize: size)
    }
}

// MARK: - Ink
//
// White paper by day, black by night, one raspberry accent, and every state drawn
// as a wash of the text colour so it reads the same in either.

nonisolated enum Ink {
    static let cornerRadius: CGFloat = 14

    /// The content sheet.
    static func paper(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(white: 0.07)
            : Color.white
    }

    /// Sidebars sit a shade lower than the paper.
    static func well(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(white: 0.04)
            : Color(white: 0.965)
    }

    /// Anything lifted off the paper: the selected sidebar pill, keycaps,
    /// menus.
    static func raised(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.15) : .white
    }

    /// A hairline edge so a sheet separates from whatever sits behind it.
    static func rim(_ scheme: ColorScheme) -> Color {
        Color.primary.opacity(scheme == .dark ? 0.11 : 0.08)
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.98, green: 0.36, blue: 0.60)
            : Color(red: 0.86, green: 0.10, blue: 0.40)
    }

    static func amber(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.98, green: 0.72, blue: 0.36)
            : Color(red: 0.76, green: 0.48, blue: 0.08)
    }

    static func green(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.42, green: 0.80, blue: 0.56)
            : Color(red: 0.18, green: 0.62, blue: 0.40)
    }

    /// Rules between rows.
    static let hairline = Color.primary.opacity(0.09)
    /// Unselected chips and inset fields.
    static let fill = Color.primary.opacity(0.055)
    /// Highlighted row or menu item, in the pane that has the keyboard.
    static let selection = Color.primary.opacity(0.08)
    /// The other pane keeps its selection, fainter, so depth alone says
    /// which pane has the keyboard. It still sits above a hover.
    static let inactiveSelection = Color.primary.opacity(0.045)
    /// Pointer resting on a row.
    static let hover = Color.primary.opacity(0.03)

    static func wash(highlighted: Bool, dimmed: Bool = false, hovering: Bool = false) -> Color {
        guard highlighted else { return hovering ? hover : .clear }
        return dimmed ? inactiveSelection : selection
    }

    // AppKit needs the same colours for the views it draws itself.

    @MainActor static let nsPaper = NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(white: 0.07, alpha: 1)
            : NSColor.white
    }

    @MainActor static let nsRaised = NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 0.15, alpha: 1) : .white
    }

    @MainActor static let nsAccent = NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(red: 0.98, green: 0.36, blue: 0.60, alpha: 1)
            : NSColor(red: 0.86, green: 0.10, blue: 0.40, alpha: 1)
    }

    @MainActor static let nsHairline = NSColor(name: nil) { appearance in
        NSColor.labelColor.withAlphaComponent(appearance.isDark ? 0.12 : 0.10)
    }

    /// A short accent rule at the leading edge: keyboard focus. Dimmed to
    /// grey when the other pane owns the keys.
    /// The highlight behind a list row: inset from the row's edges and
    /// rounded, so a full-bleed row reads as a pill without moving its text.
    struct Pill: View {
        static let inset: CGFloat = 8
        var radius: CGFloat
        var fill: Color

        var body: some View {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .padding(.horizontal, Self.inset)
        }
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

// MARK: - Shaders

nonisolated enum Shaders {
    /// build.sh compiles Resources/Shaders into the bundle. A bare
    /// `swift run` has no bundle, so the surfaces fall back to flat colour.
    static let isAvailable = Bundle.main.url(forResource: "default", withExtension: "metallib") != nil
}

/// The paper every window is drawn on. Grain and a soft light, both
/// too faint to name, so a flat sheet stops looking like a flat fill.
struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if Shaders.isAvailable {
            let dark = scheme == .dark
            let paper = Ink.paper(scheme)
            let tint = Color(white: dark ? 0.32 : 1.0)
            let glow: Float = dark ? 0.08 : 0
            let depth: Float = dark ? 0.025 : 0.014
            let grain: Float = dark ? 0.016 : 0.010
            Rectangle()
                .fill(paper)
                .visualEffect { content, proxy in
                    content.colorEffect(ShaderLibrary.paper(
                        .float2(proxy.size), .color(tint),
                        .float(glow), .float(depth), .float(grain)
                    ))
                }
        } else {
            Rectangle().fill(Ink.paper(scheme))
        }
    }
}

/// The recording capsule wearing the wordmark: Sendpoint's emblem. Ink on
/// the opposite of the system appearance, like every overlay, with the orb
/// alive at the trailing end.
struct WordmarkPill: View {
    var mode: VoiceOrb.Mode = .idle
    var animates = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = OverlayPalette.against(colorScheme)
        HStack(spacing: 10) {
            Text("Sendpoint")
                .font(.ui(12.5, weight: .semibold))
                .foregroundStyle(palette.ink.opacity(0.92))
            VoiceOrb(mode: mode, level: 0, ink: palette.ink, amber: palette.amber, accent: palette.accent, animates: animates)
                .frame(width: 22, height: 22)
        }
        .padding(.leading, 14)
        .padding(.trailing, 9)
        .frame(height: VoiceCaptureLayout.pillHeight)
        .background(Capsule().fill(palette.paper))
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [palette.ink.opacity(0.14), palette.ink.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.5
            )
        )
        .shadow(color: .black.opacity(0.22), radius: 14, y: 7)
        .environment(\.colorScheme, palette.contentScheme)
        .contentShape(Capsule())
    }
}

/// An empty stack, drawn: three thin sheets fanned back, each one paper so
/// it hides the sheet behind it, the front one holding two lines waiting
/// for words. Stroked in a pink-to-white gradient over a faint glow.
/// Vector, so it is crisp at any size, with no idle animation work.
struct EmptyStackGlyph: View {
    @Environment(\.colorScheme) private var scheme

    private static let sheet = CGSize(width: 104, height: 66)
    private static let radius: CGFloat = 12
    private static let lift: CGFloat = 11
    private static let inset: CGFloat = 12

    var body: some View {
        let accent = Ink.accent(scheme)
        let faint = scheme == .dark ? Color.white.opacity(0.3) : accent.opacity(0.18)
        let stroke = LinearGradient(
            colors: [accent, accent.opacity(0.75), faint],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        ZStack {
            Circle()
                .fill(accent.opacity(scheme == .dark ? 0.12 : 0.07))
                .frame(width: 140, height: 140)
                .blur(radius: 28)
                .offset(y: 6)
            ForEach([2, 1, 0], id: \.self) { depth in
                let d = CGFloat(depth)
                let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                shape
                    .fill(Ink.paper(scheme))
                    .overlay(shape.strokeBorder(stroke, lineWidth: 1).opacity(1 - Double(depth) * 0.3))
                    .frame(width: Self.sheet.width - d * Self.inset * 2, height: Self.sheet.height)
                    .offset(y: -d * Self.lift)
            }
            VStack(alignment: .leading, spacing: 8) {
                Capsule().fill(stroke).frame(width: 40, height: 1.2)
                Capsule().fill(stroke).frame(width: 24, height: 1.2)
            }
            .frame(width: Self.sheet.width - 34, height: Self.sheet.height - 30, alignment: .topLeading)
        }
        .frame(width: 160, height: 120)
        .accessibilityHidden(true)
    }
}

/// Soft pools of pink, lavender and sky over paper: the status
/// card's background. Dark mode keeps the same hues, dimmer.
struct Aurora: View {
    /// How far the pools are allowed to tint the base. A small card takes
    /// the full amount; a large sheet wants about half.
    var strength: Double = 1
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let base = Ink.raised(scheme)
        let pink = dark ? Color(red: 0.62, green: 0.24, blue: 0.44) : Color(red: 1.00, green: 0.74, blue: 0.87)
        let lavender = dark ? Color(red: 0.42, green: 0.36, blue: 0.62) : Color(red: 0.84, green: 0.82, blue: 0.98)
        let sky = dark ? Color(red: 0.30, green: 0.42, blue: 0.56) : Color(red: 0.80, green: 0.88, blue: 0.98)
        if Shaders.isAvailable {
            Rectangle()
                .fill(base)
                .visualEffect { content, proxy in
                    content.colorEffect(ShaderLibrary.aurora(
                        .float2(proxy.size),
                        .color(pink), .color(lavender), .color(sky), .float(Float(strength))
                    ))
                }
        } else {
            ZStack {
                base
                LinearGradient(colors: [pink.opacity(0.8 * strength), lavender.opacity(0.7 * strength), .clear],
                               startPoint: .topLeading, endPoint: .bottom)
                LinearGradient(colors: [sky.opacity(0.6), .clear], startPoint: .topTrailing, endPoint: .bottomLeading)
            }
        }
    }
}

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

// MARK: - Settings chrome
//
// Every page is sections: a mono label over flat rows separated by
// hairlines. The sidebar names the page, so nothing else does. Nothing is
// boxed.

nonisolated enum SettingsMetrics {
    /// Height of a plain row.
    static let rowHeight: CGFloat = 44
    /// Gap between one section and the next.
    static let sectionSpacing: CGFloat = 28
    /// Gap between a section label and its first row.
    static let labelSpacing: CGFloat = 3
    static let contentMaxWidth: CGFloat = 640
    static let pageInset: CGFloat = 40
}

/// Small mono caps over a group of rows.
struct SettingsLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.mono(10.5, weight: .medium))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A state of the world, said the way an instrument would: small mono
/// caps, letterspaced, a step brighter than a section label.
struct Readout: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.mono(11.5, weight: .medium))
            .tracking(2.2)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

/// A label, its rows, and an optional line of small print beneath.
struct SettingsSection<Content: View>: View {
    let label: String
    var footnote: String? = nil
    @ViewBuilder let content: () -> Content

    init(_ label: String, footnote: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.footnote = footnote
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.labelSpacing) {
            SettingsLabel(label)
            VStack(spacing: 0) {
                content()
            }
            if let footnote {
                SettingsFootnote(footnote)
            }
        }
    }
}

/// One quiet sentence.
struct SettingsFootnote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.ui(12.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Title, an inline hint in a quieter voice, and the control at the
/// trailing edge. `detail` sits under the title, for a short explanation.
struct SettingsRow<Trailing: View>: View {
    let title: String
    let hint: String?
    let detail: String?
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ title: String,
        hint: String? = nil,
        detail: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.hint = hint
        self.detail = detail
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title)
                        .font(.ui(14, weight: .medium))
                    if let hint {
                        Text(hint)
                            .font(.ui(13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if let detail {
                    Text(detail)
                        .font(.ui(12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.vertical, detail == nil ? 0 : 6)
        .frame(minHeight: SettingsMetrics.rowHeight)
    }
}

/// A row whose control is not a single line: chips, a picker with a
/// meter under it. The control sits under the title, left-aligned.
struct SettingsStackedRow<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.ui(14, weight: .medium))
            }
            content()
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let hint: String?
    let detail: String?
    @Binding var isOn: Bool

    init(_ title: String, hint: String? = nil, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.hint = hint
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        SettingsRow(title, hint: hint, detail: detail) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(InkToggleStyle())
                .accessibilityHint(detail ?? "")
        }
    }
}

/// A compact plus/minus control for a small closed range.
struct SettingsStepperRow: View {
    let title: String
    let valueText: String
    var accessibilityValue: String? = nil
    let canDecrement: Bool
    let canIncrement: Bool
    let decrement: () -> Void
    let increment: () -> Void

    init(
        _ title: String,
        valueText: String,
        accessibilityValue: String? = nil,
        canDecrement: Bool,
        canIncrement: Bool,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) {
        self.title = title
        self.valueText = valueText
        self.accessibilityValue = accessibilityValue
        self.canDecrement = canDecrement
        self.canIncrement = canIncrement
        self.decrement = decrement
        self.increment = increment
    }

    var body: some View {
        SettingsRow(title) {
            HStack(spacing: 8) {
                StepperGlyphButton("minus", enabled: canDecrement, action: decrement)
                Text(valueText)
                    .font(.mono(12, weight: .medium))
                    .monospacedDigit()
                    .frame(minWidth: 36)
                    .multilineTextAlignment(.center)
                StepperGlyphButton("plus", enabled: canIncrement, action: increment)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(accessibilityValue ?? valueText)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    if canIncrement { increment() }
                case .decrement:
                    if canDecrement { decrement() }
                default:
                    break
                }
            }
        }
    }
}

private struct StepperGlyphButton: View {
    let systemName: String
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    init(_ systemName: String, enabled: Bool, action: @escaping () -> Void) {
        self.systemName = systemName
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(enabled ? (hovering ? Color.primary : Color.secondary) : Color.secondary.opacity(0.35))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(hovering && enabled ? 0.09 : 0.055)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}

struct SettingsDivider: View {
    var body: some View { Hairline() }
}

/// A small anchored prompt: type a name, press Return.
struct NamePopover: View {
    let prompt: String
    let placeholder: String
    @Binding var name: String
    let problem: String?
    let onCommit: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt)
                .font(.uiCaption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $name)
                .textFieldStyle(.plain)
                .font(.ui(13))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Ink.fill))
                .focused($focused)
                .onSubmit(onCommit)
            HStack(spacing: 6) {
                if let problem {
                    Text(problem)
                        .font(.uiCaption)
                        .foregroundStyle(Ink.amber(scheme))
                } else {
                    Keycap("↩", size: 10)
                    Text("Create")
                        .font(.uiCaption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .frame(width: 250)
        .font(.uiBody)
        .onAppear {
            DispatchQueue.main.async { focused = true }
        }
    }
}

/// A page: sections down the full width, scrolling as one.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
                    content()
                }
                .frame(maxWidth: SettingsMetrics.contentMaxWidth, alignment: .topLeading)
                .padding(.horizontal, SettingsMetrics.pageInset)
                .padding(.top, 52)
                .padding(.bottom, SettingsMetrics.pageInset)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .id(Anchor.top)
            }
            .scrollIndicators(.automatic)
            // A text field that takes first responder drags the scroll view
            // to itself; a page always opens at its top.
            .onAppear {
                DispatchQueue.main.async { proxy.scrollTo(Anchor.top, anchor: .top) }
            }
        }
    }

    private enum Anchor: Hashable { case top }
}

// MARK: - Plumbing

/// Reports a view's laid-out height upward.
struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The AppKit scroll view behind a SwiftUI ScrollView, so a list can be
/// scrolled by exact offsets. ScrollViewReader's scrollTo is a no-op on the
/// palette's note list on macOS 14, whatever the timing.
final class ScrollHandle {
    weak var scrollView: NSScrollView?

    var viewportHeight: CGFloat { scrollView?.contentView.bounds.height ?? 0 }

    /// Whether a subview's frame, in the viewport's coordinates, ends at the
    /// bottom edge, or above it when the content is too short to scroll.
    func isAtBottomEdge(_ frame: CGRect, margin: CGFloat = 6) -> Bool {
        frame.maxY + margin <= viewportHeight + 0.5
    }

    /// Scrolls so `frame`, a subview's frame in the viewport's coordinates,
    /// sits at the edge named by `anchor`. Returns false when the content
    /// was too short to get there: its height lags the layout by a turn.
    @discardableResult
    func reveal(_ frame: CGRect, anchor: UnitPoint, animated: Bool) -> Bool {
        guard let scrollView, let document = scrollView.documentView else { return false }
        let clip = scrollView.contentView
        let viewport = clip.bounds.height
        let content = document.bounds.height
        // AppKit measures from the bottom unless the document is flipped.
        let currentTop = document.isFlipped
            ? clip.bounds.origin.y
            : content - viewport - clip.bounds.origin.y
        let top = revealedScrollOffset(
            currentTop: currentTop, frame: frame, viewportHeight: viewport,
            contentHeight: content, anchor: anchor
        )
        let unclamped = revealedScrollOffset(
            currentTop: currentTop, frame: frame, viewportHeight: viewport,
            contentHeight: .infinity, anchor: anchor
        )
        var origin = clip.bounds.origin
        origin.y = document.isFlipped ? top : content - viewport - top
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.allowsImplicitAnimation = true
                clip.animator().setBoundsOrigin(origin)
            }
        } else {
            clip.setBoundsOrigin(origin)
        }
        scrollView.reflectScrolledClipView(clip)
        return abs(top - unclamped) < 0.5
    }
}

/// Placed inside a ScrollView's content, hands the enclosing scroll view
/// to a ScrollHandle.
struct ScrollProbe: NSViewRepresentable {
    let handle: ScrollHandle

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.handle = handle
        return probe
    }

    func updateNSView(_ nsView: Probe, context: Context) {
        nsView.handle = handle
        nsView.attach()
    }

    final class Probe: NSView {
        var handle: ScrollHandle?

        override init(frame: NSRect) {
            super.init(frame: frame)
            isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("unsupported") }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            attach()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach()
        }

        func attach() {
            if let scrollView = enclosingScrollView { handle?.scrollView = scrollView }
        }
    }
}

/// Tells SwiftUI whether the window it lives in is actually on screen, so
/// live work like the level meter stops when the window is hidden.
struct WindowVisibilityReporter: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> ReporterView {
        let view = ReporterView()
        view.onChange = { isVisible = $0 }
        return view
    }

    func updateNSView(_ nsView: ReporterView, context: Context) {
        nsView.onChange = { isVisible = $0 }
    }

    static func dismantleNSView(_ nsView: ReporterView, coordinator: ()) {
        nsView.teardown()
    }

    final class ReporterView: NSView {
        var onChange: ((Bool) -> Void)?
        private var reportTask: Task<Void, Never>?

        deinit { reportTask?.cancel() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            reportTask?.cancel()
            guard let window else { report(false); return }
            NotificationCenter.default.addObserver(
                self, selector: #selector(reportCurrent),
                name: NSWindow.didChangeOcclusionStateNotification, object: window
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowWillClose),
                name: NSWindow.willCloseNotification, object: window
            )
            reportCurrent()
        }

        @objc private func reportCurrent() {
            guard let window else { report(false); return }
            report(window.isVisible && window.occlusionState.contains(.visible))
        }

        private func report(_ visible: Bool) {
            reportTask?.cancel()
            reportTask = Task { @MainActor [weak self] in
                // Deliver outside the AppKit/SwiftUI attachment update. A newer
                // visibility event or teardown cancels this pending delivery.
                await Task.yield()
                guard !Task.isCancelled, let self else { return }
                self.reportTask = nil
                self.onChange?(visible)
            }
        }

        @objc private func windowWillClose() { report(false) }

        func teardown() {
            NotificationCenter.default.removeObserver(self)
            reportTask?.cancel()
            reportTask = nil
            onChange = nil
        }
    }
}
