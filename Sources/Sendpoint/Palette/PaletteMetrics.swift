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
