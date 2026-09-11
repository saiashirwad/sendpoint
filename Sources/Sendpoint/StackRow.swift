import SwiftUI

/// The name, command-digit, and note-count row shared by the stack palette
/// and the stack switcher. Callers supply the surrounding chrome.
struct StackRow<Name: View>: View {
    let noteCount: Int
    let isHighlighted: Bool
    let position: Int
    let showsDigit: Bool
    @ViewBuilder let name: () -> Name

    var body: some View {
        HStack(spacing: 10) {
            name()

            Spacer(minLength: 8)

            if showsDigit, position < 9 {
                Text("⌘\(position + 1)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .opacity(isHighlighted ? 1 : 0.7)
            }

            Text("\(noteCount)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(noteCount == 0
                    ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.secondary))
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
        isHighlighted: Bool,
        position: Int,
        showsDigit: Bool
    ) {
        self.init(
            noteCount: noteCount,
            isHighlighted: isHighlighted,
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
            .accessibilityLabel(isCurrent ? "\(name), current" : name)
    }
}
