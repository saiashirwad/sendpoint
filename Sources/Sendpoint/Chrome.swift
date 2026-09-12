import SwiftUI

extension EnvironmentValues {
    @Entry var emphasizedKeycaps = false
}

/// A small keyboard-key badge, for shortcut hints.
struct Keycap: View {
    @Environment(\.emphasizedKeycaps) private var emphasized
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
                RoundedRectangle(cornerRadius: size * 0.4, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .foregroundStyle(emphasized ? Color.primary : Color.secondary)
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
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}

    /// Restyles once it lands in a window, not on every SwiftUI update.
    final class Probe: NSView {
        override init(frame: NSRect) {
            super.init(frame: frame)
            isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("unsupported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            // The text view's scroll view is built lazily, so look more than once.
            for delay in [0.0, 0.1, 0.4] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let root = self?.window?.contentView else { return }
                    for scroll in OverlayScrollers.scrollViews(in: root) {
                        scroll.scrollerStyle = .overlay
                        scroll.autohidesScrollers = true
                    }
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
// surface: the same paper, the same row metrics, the same caption style.

enum SettingsMetrics {
    /// Row padding on each side.
    static let rowInset: CGFloat = 14
    /// Quiet leading glyph, when a row still carries one.
    static let iconSize: CGFloat = 16
    /// Where a divider starts when the rows above and below carry an icon.
    static let iconDividerInset: CGFloat = rowInset + iconSize + rowInset
    /// Corner radius of the template text editor.
    static let cardRadius: CGFloat = 8
    /// Vertical padding inside every row.
    static let rowPadding: CGFloat = 10
    /// Gap between a caption and its content, and between loose items.
    static let captionSpacing: CGFloat = 8
    /// Gap between one section and the next, the same on every pane.
    static let sectionSpacing: CGFloat = 18
}

/// Sentence-case label above a cluster of rows.
struct SettingsCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
    }
}

/// A group of settings rows. Rows carry their own padding, and the negative
/// inset cancels it so the group aligns with the section captions.
struct SettingsRowGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
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
        }
    }
}

/// A 14pt glyph with no tile, used only where a row still needs a picture.
struct SettingsIcon: View {
    let name: String

    init(_ name: String) { self.name = name }

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: SettingsMetrics.iconSize, height: SettingsMetrics.iconSize)
            .accessibilityHidden(true)
    }
}

/// Title, one-line detail, and whatever sits at the trailing edge.
struct SettingsIconRow<Trailing: View>: View {
    var icon: String? = nil
    let title: String
    let detail: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: SettingsMetrics.rowInset) {
            if let icon {
                SettingsIcon(icon)
            }
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

/// Two or more text options; the selected one takes the palette wash.
struct TextSegmentPicker<Value: Hashable>: View {
    let values: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(values, id: \.self) { value in
                let isSelected = value == selection
                Button {
                    selection = value
                } label: {
                    Text(title(value))
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(isSelected ? PaletteTint.selection : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
        }
    }
}
