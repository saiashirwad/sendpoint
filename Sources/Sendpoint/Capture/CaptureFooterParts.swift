import SwiftUI

struct CaptureStackLabel: View {
    @Bindable var model: CaptureController
    let mode: CaptureMode
    let ink: Color
    var rowHeight: CGFloat = VoiceCaptureLayout.cardFooterHeight
    var anchorHeight: CGFloat = VoiceCaptureLayout.cardFooterHeight

    var body: some View {
        CaptureDestinationButton(
            model: model, mode: mode, fontSize: 11.5,
            rowHeight: rowHeight, anchorHeight: anchorHeight
        )
        .foregroundStyle(ink.opacity(0.9))
        .frame(maxWidth: 180, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        if let stack = model.targetStack {
            Text("\(stack.noteCount)")
                .font(.mono(11))
                .foregroundStyle(ink.opacity(0.5))
                .padding(.leading, -4)
        }
    }
}

struct CaptureTether: View {
    let text: String?
    let ink: Color

    var body: some View {
        if let text {
            Rectangle()
                .fill(ink.opacity(0.12))
                .frame(width: 1, height: 12)
                .transition(.opacity)
            Text(text)
                .font(.mono(11))
                .foregroundStyle(ink.opacity(0.55))
                .lineLimit(1)
                .fixedSize()
                .transition(.opacity.combined(with: .offset(x: 6)))
        }
    }
}
