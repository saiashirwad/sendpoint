import SwiftUI

/// The name, command-digit, and note-count row in the stack palette.
/// Callers supply the surrounding chrome.
struct StackRow<Name: View>: View {
    let noteCount: Int
    let position: Int
    let showsDigit: Bool
    @ViewBuilder let name: () -> Name

    var body: some View {
        HStack(spacing: 10) {
            name()

            Spacer(minLength: 8)

            if showsDigit, position < 9 {
                Keycap("⌘\(position + 1)")
            }

            Text("\(noteCount)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 18, alignment: .trailing)
                .accessibilityLabel(countLabel)
        }
        .foregroundStyle(Color.primary)
    }

    private var countLabel: String { noteCountLabel(noteCount) }
}

extension StackRow where Name == StackRowName {
    /// The common case: a plain stack name, styled and labelled for the row.
    init(
        name: String,
        noteCount: Int,
        isCurrent: Bool,
        position: Int,
        showsDigit: Bool
    ) {
        self.init(
            noteCount: noteCount,
            position: position,
            showsDigit: showsDigit
        ) {
            StackRowName(name: name, isCurrent: isCurrent)
        }
    }
}

/// The stack name at the leading edge of a StackRow.
struct StackRowName: View {
    let name: String
    let isCurrent: Bool

    var body: some View {
        Text(name)
            .font(.system(size: 14, weight: isCurrent ? .semibold : .medium))
            .lineLimit(1)
            .accessibilityLabel(isCurrent ? "\(name), current capture stack" : name)
    }
}
