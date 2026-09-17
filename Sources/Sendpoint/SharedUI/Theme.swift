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

// MARK: - Overlay

/// Ink on paper for the floating overlays, chosen against the system
/// appearance: a near-black capsule with white ink over light desktops, a
/// translucent white capsule with black ink over dark ones, so an overlay
/// never sinks into a same-coloured desktop.
struct OverlayPalette {
    let ink: Color
    let paper: Color
    let amber: Color
    /// The brand pink, for the orb while it listens and nothing else.
    let accent: Color
    /// What the overlay's own contents render as, the opposite of the system.
    let contentScheme: ColorScheme

    static func against(_ system: ColorScheme) -> OverlayPalette {
        switch system {
        case .dark:
            OverlayPalette(
                ink: .black,
                paper: Color(white: 0.98).opacity(0.9),
                amber: Ink.amber(.light),
                accent: Ink.accent(.light),
                contentScheme: .light
            )
        default:
            OverlayPalette(
                ink: .white,
                paper: Color(white: 0.06).opacity(0.94),
                amber: Ink.amber(.dark),
                accent: Ink.accent(.dark),
                contentScheme: .dark
            )
        }
    }
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
