import SwiftUI

/// Ink on paper for the floating overlays, chosen against the system
/// appearance: a near-black capsule with white ink over light desktops, a
/// translucent white capsule with black ink over dark ones, so an overlay
/// never sinks into a same-coloured desktop.
struct OverlayPalette {
    let ink: Color
    let paper: Color
    let amber: Color
    /// What the overlay's own contents render as, the opposite of the system.
    let contentScheme: ColorScheme

    static func against(_ system: ColorScheme) -> OverlayPalette {
        switch system {
        case .dark:
            OverlayPalette(
                ink: .black,
                paper: Color(white: 0.98).opacity(0.9),
                amber: Color(red: 0.76, green: 0.42, blue: 0.0),
                contentScheme: .light
            )
        default:
            OverlayPalette(
                ink: .white,
                paper: Color(white: 0.06).opacity(0.94),
                amber: Color(red: 1.0, green: 0.72, blue: 0.38),
                contentScheme: .dark
            )
        }
    }
}
