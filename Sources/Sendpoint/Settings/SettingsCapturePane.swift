import SendpointDomain
import SwiftUI

struct SettingsCapturePane: View {
    @Bindable var shortcuts: ShortcutSettings
    @Bindable var voiceSettings: VoiceSettings
    let hotKeyRegistrar: HotKeyRegistrar
    let captureController: CaptureController
    let onSettingsChanged: () -> Void

    @State private var inputDevices = AudioInputDeviceList()
    @State private var preview = MicrophonePreviewOwner()
    @State private var windowIsVisible = false

    var body: some View {
        SettingsPage {
            SettingsSection("Recording", footnote: voiceSettings.voiceMode.detail) {
                SettingsStackedRow {
                    ChoiceChips(
                        values: Array(VoiceRecordingMode.allCases),
                        selection: Binding(
                            get: { voiceSettings.voiceMode },
                            set: { captureController.setVoiceMode($0) }
                        ),
                        title: { $0.title }
                    )
                }
            }
            SettingsSection("Microphones", footnote: microphones.footnote) {
                MicrophoneRows(
                    rows: microphones.rows,
                    tucked: microphones.tucked,
                    level: preview.level,
                    isListening: preview.isActive,
                    onMove: { captureController.updateMicrophones(.moveMicrophone(uid: $0, toIndex: $1)) },
                    onToggle: { captureController.updateMicrophones(.microphoneEnabled(uid: $0, $1)) },
                    onForget: { captureController.updateMicrophones(.forgetMicrophone(uid: $0)) }
                )
            }
            SettingsSection("Shortcuts") {
                ShortcutRows(
                    specs: [
                        ShortcutSpec(title: "Voice note", hint: "Saves what you say to the stack", slot: .voiceCapture),
                        ShortcutSpec(title: "Typed note", hint: "Quotes the selected text", slot: .capture),
                        ShortcutSpec(title: "Dictate", hint: "Pastes what you say at the cursor", slot: .dictate),
                    ],
                    shortcuts: shortcuts,
                    hotKeyRegistrar: hotKeyRegistrar,
                    onSettingsChanged: onSettingsChanged
                )
            }
        }
        .background(WindowVisibilityReporter(isVisible: $windowIsVisible))
        .onAppear {
            absorbDevices()
            syncPreview()
        }
        .onDisappear { preview.stop() }
        .onChange(of: inputDevices.devices) { _, _ in absorbDevices() }
        .onChange(of: activeMicrophone) { _, _ in syncPreview() }
        .onChange(of: windowIsVisible) { _, _ in syncPreview() }
    }

    private func absorbDevices() {
        captureController.updateMicrophones(
            .microphonesSeen(inputDevices.devices, systemDefault: inputDevices.systemDefault)
        )
    }

    private func syncPreview() {
        if windowIsVisible {
            preview.start(voiceSettings.microphones)
        } else {
            preview.stop()
        }
    }

    private var microphones: MicrophoneListFacts {
        MicrophoneListFacts(
            order: voiceSettings.microphones,
            devices: inputDevices.devices,
            systemDefault: inputDevices.systemDefault
        )
    }

    private var activeMicrophone: String? {
        microphones.rows.first(where: \.isActive)?.id
    }
}

struct MicrophoneRows: View {
    let rows: [MicrophoneListFacts.Row]
    let tucked: [MicrophoneListFacts.Row]
    let level: Float
    let isListening: Bool
    let onMove: (String, Int) -> Void
    let onToggle: (String, Bool) -> Void
    let onForget: (String) -> Void

    private struct Drag: Equatable {
        let id: String
        let origin: Int
        var translation: CGFloat
    }

    private static let space = "microphones"
    private static let rowHeight: CGFloat = 40
    private static let gripWidth: CGFloat = 14

    @GestureState(resetTransaction: Transaction(animation: .snappy(duration: 0.2))) private var drag: Drag?
    @State private var showsTucked = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            ranked
            if !tucked.isEmpty {
                if !rows.isEmpty { SettingsDivider() }
                tuckedDisclosure
                if showsTucked {
                    ForEach(tucked) { row in
                        SettingsDivider()
                        rowView(row, isRanked: false)
                            .frame(height: Self.rowHeight)
                            .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var tuckedDisclosure: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { showsTucked.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(showsTucked ? 90 : 0))
                    .frame(width: Self.gripWidth)
                Text(MicrophoneListFacts.tuckedLabel(count: tucked.count))
                    .font(.ui(13))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(showsTucked ? "Expanded" : "Collapsed")
    }

    private var ranked: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                let isDragged = drag?.id == row.id
                rowView(row, isRanked: true)
                    .frame(height: Self.rowHeight)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Ink.raised(scheme))
                            .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                            .padding(.horizontal, -10)
                            .opacity(isDragged ? 1 : 0)
                    }
                    .offset(y: offset(at: index))
                    .zIndex(isDragged ? 1 : 0)
                    .animation(isDragged ? nil : .snappy(duration: 0.2), value: target)
                    .contentShape(Rectangle())
                    .gesture(reorder(row, from: index))
                    .accessibilityElement(children: .combine)
                    .accessibilityAction(named: "Move up") { onMove(row.id, index - 1) }
                    .accessibilityAction(named: "Move down") { onMove(row.id, index + 1) }
            }
        }
        .background(alignment: .top) {
            ForEach(rows.indices.dropFirst(), id: \.self) { index in
                SettingsDivider().offset(y: CGFloat(index) * Self.rowHeight)
            }
        }
        .coordinateSpace(name: Self.space)
    }

    private var target: Int? {
        drag.map {
            MicrophoneListFacts.dropIndex(
                from: $0.origin, translation: $0.translation, rowHeight: Self.rowHeight, count: rows.count
            )
        }
    }

    private func offset(at index: Int) -> CGFloat {
        guard let drag, let target else { return 0 }
        if index == drag.origin {
            let up = -CGFloat(drag.origin) * Self.rowHeight
            let down = CGFloat(rows.count - 1 - drag.origin) * Self.rowHeight
            return min(max(drag.translation, up), down)
        }
        if drag.origin < index, index <= target { return -Self.rowHeight }
        if target <= index, index < drag.origin { return Self.rowHeight }
        return 0
    }

    private func reorder(_ row: MicrophoneListFacts.Row, from index: Int) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .updating($drag) { value, drag, _ in
                drag = Drag(id: row.id, origin: index, translation: value.translation.height)
            }
            .onEnded { value in
                let destination = MicrophoneListFacts.dropIndex(
                    from: index, translation: value.translation.height,
                    rowHeight: Self.rowHeight, count: rows.count
                )
                guard destination != index else { return }
                withAnimation(.snappy(duration: 0.2)) { onMove(row.id, destination) }
            }
    }

    private func rowView(_ row: MicrophoneListFacts.Row, isRanked: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: Self.gripWidth)
                .opacity(isRanked ? 1 : 0)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(row.name)
                    .font(.ui(14, weight: .medium))
                    .lineLimit(1)
                    .opacity(row.isEnabled && row.isConnected ? 1 : 0.45)
                if row.isActive {
                    InputLevelBar(level: level, isActive: isListening)
                        .frame(width: 220)
                }
            }
            Spacer(minLength: 12)
            if let status = row.status {
                HStack(spacing: 6) {
                    if row.isActive {
                        Circle().fill(Ink.accent(scheme)).frame(width: 6, height: 6)
                    }
                    Text(status)
                        .font(.ui(12.5))
                        .foregroundStyle(.secondary)
                }
            }
            if !row.isConnected {
                QuietButton("Forget") {
                    withAnimation(.snappy(duration: 0.2)) { onForget(row.id) }
                }
            }
            Toggle(row.name, isOn: Binding(get: { row.isEnabled }, set: { onToggle(row.id, $0) }))
                .labelsHidden()
                .toggleStyle(InkToggleStyle())
        }
    }
}

struct InputLevelBar: View {
    let level: Float
    let isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Color.primary.opacity(0.75))
                    .frame(width: max(0, proxy.size.width * CGFloat(isActive ? min(max(level, 0), 1) : 0)))
                    .animation(.linear(duration: 0.06), value: level)
            }
        }
        .frame(height: 3)
        .opacity(isActive ? 1 : 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Input level")
        .accessibilityValue(isActive ? "\(Int(level * 100)) percent" : "Not listening")
    }
}
