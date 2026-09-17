import SwiftUI

/// The palette's layout numbers, named once (following the
/// `VoiceCaptureLayout`/`SettingsMetrics` precedent) so rows, cards, and
/// the overlay menus stay the same size. A rename, not a redesign: every
/// value is the long-standing literal it replaces.
enum PaletteMetrics {
    /// Outer horizontal padding used by the header, rows, and footers.
    static let horizontalPadding: CGFloat = 18
    /// Height of the single-line bars: the new-stack/create rows, the
    /// footers, and the overlay filter field. (Note rows use the view's
    /// `rowHeight`.)
    static let barHeight: CGFloat = 40
    /// Width of the floating overlay menus.
    static let overlayWidth: CGFloat = 320
    /// Corner radius of the row highlight pills.
    static let pillRadius: CGFloat = 7
    /// Corner radius of the note highlight pills and the editing ring.
    static let cardRadius: CGFloat = 10
    /// Corner radius of the floating overlay panel.
    static let overlayRadius: CGFloat = 12
}

/// The floating menu surface, named once for the palette's overlay menus:
/// one rounded fill, one rim, one shadow. Palette-local only; a shared
/// cross-file modifier is follow-up work, so Theme.swift/SettingsChrome.swift are untouched.
struct OverlaySurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: PaletteMetrics.overlayRadius, style: .continuous)
                    .fill(Ink.raised(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PaletteMetrics.overlayRadius, style: .continuous)
                    .strokeBorder(Ink.rim(scheme), lineWidth: 1)
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.14), radius: 24, y: 10)
    }
}
