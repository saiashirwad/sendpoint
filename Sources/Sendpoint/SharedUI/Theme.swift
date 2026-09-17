import AppKit
import SwiftUI

// MARK: - Type

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

nonisolated enum Ink {
    static let cornerRadius: CGFloat = 14

    static func paper(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(white: 0.07)
            : Color.white
    }

    static func well(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(white: 0.04)
            : Color(white: 0.965)
    }

    static func raised(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.15) : .white
    }

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

    static let hairline = Color.primary.opacity(0.09)
    static let fill = Color.primary.opacity(0.055)
    static let selection = Color.primary.opacity(0.08)
    static let hover = Color.primary.opacity(0.03)

    static func wash(highlighted: Bool) -> Color {
        highlighted ? selection : .clear
    }

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

struct OverlayPalette {
    let ink: Color
    let paper: Color
    let amber: Color
    let accent: Color

    static let dark = OverlayPalette(
        ink: .white,
        paper: Color(white: 0.06).opacity(0.94),
        amber: Ink.amber(.dark),
        accent: Ink.accent(.dark)
    )

    var rim: LinearGradient {
        LinearGradient(
            colors: [ink.opacity(0.14), ink.opacity(0.03)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Shaders

nonisolated enum Shaders {
    static let isAvailable = Bundle.main.url(forResource: "default", withExtension: "metallib") != nil
}

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

struct WordmarkPill: View {
    var mode: VoiceOrb.Mode = .idle
    var animates = false

    var body: some View {
        let palette = OverlayPalette.dark
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
        .overlay(Capsule().strokeBorder(palette.rim, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 7)
        .environment(\.colorScheme, .dark)
        .contentShape(Capsule())
    }
}

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

struct Aurora: View {
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
