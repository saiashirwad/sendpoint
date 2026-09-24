import AppKit
import SwiftUI

// MARK: - Settings chrome

nonisolated enum SettingsMetrics {
    static let rowHeight: CGFloat = 44
    static let contentMaxWidth: CGFloat = 640
}

struct SettingsLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.mono(10.5, weight: .medium))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(Ink.tertiaryStyle)
            .accessibilityAddTraits(.isHeader)
    }
}

struct Readout: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.mono(11.5, weight: .medium))
            .tracking(2.2)
            .textCase(.uppercase)
            .foregroundStyle(Ink.secondaryStyle)
            .multilineTextAlignment(.center)
    }
}

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
        VStack(alignment: .leading, spacing: Spacing.xs) {
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

struct SettingsFootnote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.ui(12.5))
            .foregroundStyle(Ink.secondaryStyle)
            .fixedSize(horizontal: false, vertical: true)
    }
}

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
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                    Text(title)
                        .font(.ui(14, weight: .medium))
                    if let hint {
                        Text(hint)
                            .font(.ui(13))
                            .foregroundStyle(Ink.secondaryStyle)
                            .lineLimit(1)
                    }
                }
                if let detail {
                    Text(detail)
                        .font(.ui(12.5))
                        .foregroundStyle(Ink.secondaryStyle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.vertical, detail == nil ? 0 : Spacing.sm)
        .frame(minHeight: SettingsMetrics.rowHeight)
    }
}

struct SettingsStackedRow<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let title {
                Text(title)
                    .font(.ui(14, weight: .medium))
            }
            content()
        }
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
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
            HStack(spacing: Spacing.sm) {
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
                .font(.symbol(10, weight: .semibold))
                .foregroundStyle(enabled ? (hovering ? Ink.primary : Ink.secondary) : Ink.secondary.opacity(0.35))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Ink.primary.opacity(hovering && enabled ? 0.09 : 0.055)))
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

@MainActor
func announcePolitely(_ message: String) {
    guard !message.isEmpty, let window = NSApp.keyWindow else { return }
    NSAccessibility.post(
        element: window,
        notification: .announcementRequested,
        userInfo: [.announcement: message]
    )
}

struct NamePopover: View {
    let prompt: String
    let placeholder: String
    @Binding var name: String
    let problem: String?
    let onCommit: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(prompt)
                .font(.uiCaption)
                .foregroundStyle(Ink.secondaryStyle)
            TextField(placeholder, text: $name)
                .textFieldStyle(.plain)
                .font(.ui(13))
                .padding(.horizontal, Spacing.md)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).fill(Ink.fill))
                .focused($focused)
                .onSubmit(onCommit)
            HStack(spacing: Spacing.sm) {
                if let problem {
                    Text(problem)
                        .font(.uiCaption)
                        .foregroundStyle(Ink.amber(scheme))
                } else {
                    Keycap("↩", size: 10)
                    Text("Create")
                        .font(.uiCaption)
                        .foregroundStyle(Ink.tertiaryStyle)
                }
            }
        }
        .padding(Spacing.lg)
        .frame(width: 250)
        .font(.uiBody)
        .onAppear {
            DispatchQueue.main.async { focused = true }
        }
    }
}

struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    content()
                }
                .frame(maxWidth: SettingsMetrics.contentMaxWidth, alignment: .topLeading)
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.xxl)
                .padding(.bottom, Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .id(Anchor.top)
            }
            .scrollIndicators(.automatic)
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
    .padding(Spacing.lg)
}
