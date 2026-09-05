import SwiftUI

/// A small keyboard-key badge, for shortcut hints.
struct Keycap: View {
    let text: String
    var size: CGFloat = 10.5

    init(_ text: String, size: CGFloat = 10.5) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, size * 0.5)
            .padding(.vertical, size * 0.22)
            .background(
                // A physical key: a lighter face sitting on a darker bottom edge.
                RoundedRectangle(cornerRadius: size * 0.4, style: .continuous)
                    .fill(Color.primary.opacity(0.16))
                    .offset(y: 1)
            )
            .background(
                RoundedRectangle(cornerRadius: size * 0.4, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .foregroundStyle(.secondary)
    }
}

/// `⌘↩ Save` — a keycap followed by what it does.
struct ShortcutHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Keycap(keys)
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

extension View {
    /// Soft inset surface used for quotes and fields.
    func insetSurface(radius: CGFloat = 8, fill: Color = Color.primary.opacity(0.045)) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

/// Reports a view's laid-out height upward.
struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Forces overlay scrollers on every scroll view in the window, so a
/// connected mouse does not leave a permanent track in a tiny text box.
struct OverlayScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // The text view's scroll view is built lazily, so look more than once.
        for delay in [0.0, 0.1, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let root = nsView.window?.contentView else { return }
                for scroll in Self.scrollViews(in: root) {
                    scroll.scrollerStyle = .overlay
                    scroll.autohidesScrollers = true
                }
            }
        }
    }

    private static func scrollViews(in root: NSView) -> [NSScrollView] {
        var found: [NSScrollView] = []
        var queue: [NSView] = [root]
        while let next = queue.popLast() {
            if let scroll = next as? NSScrollView { found.append(scroll) }
            queue.append(contentsOf: next.subviews)
        }
        return found
    }
}

extension View {
    func overlayScrollers() -> some View {
        background(OverlayScrollers())
    }
}

// MARK: - Settings chrome
//
// Shared by the settings window and the setup flow so the two read as one
// surface: the same card, the same icon tile, the same row metrics.

enum SettingsMetrics {
    /// Row padding on each side.
    static let rowInset: CGFloat = 14
    /// Icon tile size in a row.
    static let iconSize: CGFloat = 30
    /// Where a divider starts when the rows above and below carry an icon.
    static let iconDividerInset: CGFloat = rowInset + iconSize + rowInset
    /// Corner radius of the template text editor.
    static let cardRadius: CGFloat = 10
    /// Vertical padding inside every row.
    static let rowPadding: CGFloat = 10
    /// Gap between a caption and its content, and between loose items.
    static let captionSpacing: CGFloat = 10
    /// Gap between one section and the next, the same on every pane.
    static let sectionSpacing: CGFloat = 28
}

/// Small uppercase label above a card.
struct SettingsCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
    }
}

/// A raised, bordered group of rows.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        // Experiment: no card chrome. Rows sit on the window background and
        // line up with the section captions.
        // Rows keep their own padding for the dividers between them; the
        // group as a whole sits flush with captions and plain content.
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, -SettingsMetrics.rowInset)
        .padding(.vertical, -SettingsMetrics.rowPadding)
    }
}

/// A divider between two rows, indented past the icon column when the
/// rows carry icons.
struct SettingsDivider: View {
    var pastIcon = true

    var body: some View {
        Divider().padding(.leading, pastIcon ? SettingsMetrics.iconDividerInset : SettingsMetrics.rowInset)
    }
}

/// A caption followed by its card, spaced the same everywhere.
struct SettingsSection<Content: View>: View {
    let caption: String
    @ViewBuilder let content: () -> Content

    init(_ caption: String, @ViewBuilder content: @escaping () -> Content) {
        self.caption = caption
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.captionSpacing) {
            SettingsCaption(caption)
            content()
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, SettingsMetrics.rowPadding)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        _isOn = isOn
    }

    var body: some View {
        SettingsRow(title, subtitle: subtitle) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                // Green reads as "on" at a glance; it is the same green as
                // a granted permission.
                .tint(.green)
        }
    }
}

/// The monochrome glyph tile at the leading edge of a row: a faint fill,
/// a hairline rim, and a glyph in the text colour.
struct SettingsIcon: View {
    let name: String

    init(_ name: String) { self.name = name }

    private let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.primary)
            .frame(width: SettingsMetrics.iconSize, height: SettingsMetrics.iconSize)
            .background(shape.fill(Color.primary.opacity(0.07)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75))
            .accessibilityHidden(true)
    }
}

/// Icon, title, one-line detail, and whatever sits at the trailing edge.
struct SettingsIconRow<Trailing: View>: View {
    let icon: String
    let title: String
    let detail: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: SettingsMetrics.rowInset) {
            SettingsIcon(icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, SettingsMetrics.rowPadding)
    }
}

/// One step of the voice how-to: a verb, what happens, and optionally the key.
struct HowToRow: View {
    let icon: String
    let lead: String
    let sentence: String
    var keycap: String? = nil

    var body: some View {
        SettingsIconRow(icon: icon, title: lead, detail: sentence) {
            if let keycap {
                Keycap(keycap)
            }
        }
    }
}

/// The macOS sidebar material, so the source list picks up window vibrancy.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // Lighter than the stock sidebar material so the selected row shows
        // in light mode; still tinted by what is behind the window.
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
