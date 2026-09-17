import AppKit
import SwiftUI

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

/// A polite VoiceOver announcement on macOS, where SwiftUI has no
/// `.accessibilityLiveRegion` modifier. Anchored at the key window, so no
/// extra element enters the accessibility tree and layout is untouched.
/// Call it from `.onChange` when a status block's text changes. A no-op
/// when there is no key window (Previews, tests) or the message is empty.
@MainActor
func announcePolitely(_ message: String) {
    guard !message.isEmpty, let window = NSApp.keyWindow else { return }
    NSAccessibility.post(
        element: window,
        notification: .announcementRequested,
        userInfo: [.announcement: message]
    )
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

// MARK: - Previews

#Preview("SettingsRow") {
    VStack(spacing: 0) {
        SettingsSection("Preview") {
            SettingsRow("Launch at login", detail: "Opens Sendpoint when you log in.") {
                Toggle("Launch at login", isOn: .constant(true))
                    .labelsHidden()
                    .toggleStyle(InkToggleStyle())
            }
            SettingsDivider()
            SettingsRow("Version", hint: "1.0") {
                PillButton("Check for updates") {}
            }
        }
    }
    .frame(width: 480)
    .padding()
}
