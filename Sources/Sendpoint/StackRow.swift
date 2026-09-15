import SwiftUI

/// The name, its ⌘digit, and the note count in the stack palette.
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
                Text("⌘\(position + 1)")
                    .font(.mono(10.5))
                    .foregroundStyle(.quaternary)
            }

            Text("\(noteCount)")
                .font(.mono(11))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 16, alignment: .trailing)
                .contentTransition(.numericText(value: Double(noteCount)))
                .animation(.snappy(duration: 0.3), value: noteCount)
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
        showsDigit: Bool,
        dotNamespace: Namespace.ID? = nil
    ) {
        self.init(
            noteCount: noteCount,
            position: position,
            showsDigit: showsDigit
        ) {
            StackRowName(name: name, isCurrent: isCurrent, dotNamespace: dotNamespace)
        }
    }
}

/// The stack name at the leading edge of a StackRow. Every row reserves a
/// gutter for the accent dot, so names line up and only the current stack,
/// where new notes land, fills it. Given a namespace, the dot is one shared
/// mark that slides between rows when the current stack changes.
struct StackRowName: View {
    let name: String
    let isCurrent: Bool
    var dotNamespace: Namespace.ID? = nil
    @Environment(\.colorScheme) private var scheme

    static let gutter: CGFloat = 13

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if isCurrent {
                    let dot = Circle().fill(Ink.accent(scheme))
                    if let dotNamespace {
                        dot.matchedGeometryEffect(id: "currentStack", in: dotNamespace)
                    } else {
                        dot
                    }
                }
            }
            .frame(width: 5, height: 5)
            Text(name)
                .font(.ui(13.5, weight: isCurrent ? .semibold : .medium))
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isCurrent ? "\(name), current capture stack" : name)
    }
}
