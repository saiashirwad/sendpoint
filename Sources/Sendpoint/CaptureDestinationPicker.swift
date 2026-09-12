import AppKit
import SwiftUI

/// The capture destination is an explicit click selection. Both presentations
/// keep the normal event loop running while the recording shortcut is held.
struct CaptureDestinationButton: View {
    @Bindable var model: CaptureController
    let mode: CaptureMode
    var showsIcon = false
    var fontSize: CGFloat = 12
    var arrowEdge: Edge = .bottom

    @ViewBuilder
    var body: some View {
        // Both hosting windows are retained. Only the active capture's button
        // may own a picker, even when the other window is ordered out.
        if let session = model.state.session, session.mode == mode {
            let context = session.context
            let name = model.targetStack?.name ?? "Choose stack"
            let isPresented = Binding(
                get: {
                    model.state.session?.context == context
                        && model.state.session?.destinationPicker == .open
                },
                set: { if !$0 { model.send(.dismissDestinations(context)) } }
            )

            if mode == .voice {
                destinationButton(name: name, context: context, enabled: session.canChooseDestination)
                    .frame(height: VoiceCaptureLayout.pillHeight)
                    .background {
                        CaptureDestinationPanelAnchor(
                            isPresented: isPresented,
                            rows: model.destinationStacks,
                            selectedID: session.destinationStackID,
                            onSelect: { model.chooseDestination($0, context: context) }
                        )
                    }
            } else {
                destinationButton(name: name, context: context, enabled: session.canChooseDestination)
                    .popover(isPresented: isPresented, arrowEdge: arrowEdge) {
                        if let current = model.state.session, current.context == context {
                            CaptureDestinationList(
                                rows: model.destinationStacks,
                                selectedID: current.destinationStackID,
                                onSelect: { model.chooseDestination($0, context: context) }
                            )
                        }
                    }
            }
        }
    }

    private func destinationButton(
        name: String, context: NoteCaptureContext, enabled: Bool
    ) -> some View {
        Button {
            model.send(.toggleDestinations(context))
        } label: {
            HStack(spacing: 6) {
                if showsIcon {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .opacity(0.6)
            }
            .font(.system(size: fontSize, weight: .medium))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help("Choose the destination for this note")
        .accessibilityLabel("Destination stack, \(name)")
        .accessibilityValue(
            model.state.session?.destinationPicker == .open ? "Expanded" : "Collapsed"
        )
    }
}

/// The visible list sits above the full pill height, excluding shadow margins.
enum CaptureDestinationPanelLayout {
    static let bodyWidth: CGFloat = 250
    static let rowHeight: CGFloat = 32
    static let maximumVisibleRows = 8
    static let bodyVerticalPadding: CGFloat = 6
    static let shadowPadding: CGFloat = 10
    static let anchorGap: CGFloat = 8

    static func bodyHeight(rowCount: Int) -> CGFloat {
        CGFloat(min(max(rowCount, 1), maximumVisibleRows)) * rowHeight
            + bodyVerticalPadding * 2
    }

    static func panelSize(rowCount: Int) -> NSSize {
        NSSize(
            width: bodyWidth + shadowPadding * 2,
            height: bodyHeight(rowCount: rowCount) + shadowPadding * 2
        )
    }

    static func panelOrigin(
        anchor: NSRect, rowCount: Int, visibleFrame: NSRect
    ) -> NSPoint {
        let size = panelSize(rowCount: rowCount)
        let idealX = anchor.midX - size.width / 2
        return NSPoint(
            x: min(max(idealX, visibleFrame.minX), visibleFrame.maxX - size.width),
            // The anchor spans the pill; the margin is outside the visible list.
            y: anchor.maxY + anchorGap - shadowPadding
        )
    }
}

/// An AppKit anchor spanning the destination button and the pill's full height.
/// Owns a nonmodal panel so recording shortcuts keep receiving events.
private struct CaptureDestinationPanelAnchor: NSViewRepresentable {
    @Binding var isPresented: Bool
    let rows: [StackItemFacts]
    let selectedID: UUID
    let onSelect: (UUID) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ anchor: NSView, context: Context) {
        context.coordinator.update(
            anchor: anchor,
            isPresented: isPresented,
            rows: rows,
            selectedID: selectedID,
            onSelect: onSelect,
            onDismiss: { isPresented = false }
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator {
        private var panel: NSPanel?
        private var hosting: CaptureHostingView<CaptureDestinationPanelSurface>?
        private weak var anchor: NSView?
        private weak var parentWindow: NSWindow?
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private var onDismiss: (() -> Void)?
        private var tornDown = false

        func update(
            anchor: NSView,
            isPresented: Bool,
            rows: [StackItemFacts],
            selectedID: UUID,
            onSelect: @escaping (UUID) -> Void,
            onDismiss: @escaping () -> Void
        ) {
            guard !tornDown else { return }
            self.anchor = anchor
            self.onDismiss = onDismiss
            guard isPresented else {
                hide()
                return
            }
            guard let parent = anchor.window else { return }

            let surface = CaptureDestinationPanelSurface(
                rows: rows, selectedID: selectedID, onSelect: onSelect
            )
            let panel = self.panel ?? makePanel(surface: surface)
            hosting?.rootView = surface
            let size = CaptureDestinationPanelLayout.panelSize(rowCount: rows.count)
            panel.setContentSize(size)
            place(panel, from: anchor, parent: parent, rowCount: rows.count)
            attach(panel, to: parent)
            installMonitorsIfNeeded()
            panel.orderFrontRegardless()
        }

        private func makePanel(surface: CaptureDestinationPanelSurface) -> NSPanel {
            let size = CaptureDestinationPanelLayout.panelSize(rowCount: surface.rows.count)
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.animationBehavior = .none

            let hosting = CaptureHostingView(rootView: surface)
            hosting.sizingOptions = []
            panel.contentView = hosting
            self.hosting = hosting
            self.panel = panel
            return panel
        }

        private func place(
            _ panel: NSPanel, from anchor: NSView, parent: NSWindow, rowCount: Int
        ) {
            let anchorInWindow = anchor.convert(anchor.bounds, to: nil)
            let anchorOnScreen = parent.convertToScreen(anchorInWindow)
            let screen = NSScreen.screens.first { $0.frame.intersects(anchorOnScreen) } ?? parent.screen
            guard let visibleFrame = screen?.visibleFrame else { return }
            panel.setFrameOrigin(CaptureDestinationPanelLayout.panelOrigin(
                anchor: anchorOnScreen, rowCount: rowCount, visibleFrame: visibleFrame
            ))
        }

        private func attach(_ panel: NSPanel, to parent: NSWindow) {
            guard parentWindow !== parent else { return }
            if let parentWindow { parentWindow.removeChildWindow(panel) }
            parent.addChildWindow(panel, ordered: .above)
            parentWindow = parent
        }

        private func installMonitorsIfNeeded() {
            guard localMonitor == nil, globalMonitor == nil else { return }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
                [weak self] event in
                guard let self, self.isOutsidePanelAndAnchor(event) else { return event }
                self.onDismiss?()
                return event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.onDismiss?() }
            }
        }

        private func isOutsidePanelAndAnchor(_ event: NSEvent) -> Bool {
            guard let eventWindow = event.window else { return true }
            let point = eventWindow.convertPoint(toScreen: event.locationInWindow)
            if panel?.frame.contains(point) == true { return false }
            guard let anchor, let parent = anchor.window else { return true }
            return !parent.convertToScreen(anchor.convert(anchor.bounds, to: nil)).contains(point)
        }

        private func hide() {
            guard let panel else { return }
            removeMonitors()
            if let parentWindow { parentWindow.removeChildWindow(panel) }
            parentWindow = nil
            panel.orderOut(nil)
        }

        /// The only terminal cleanup path. It is safe if SwiftUI dismantles
        /// the anchor after the model has already hidden the surface.
        func teardown() {
            guard !tornDown else { return }
            tornDown = true
            hide()
            panel?.contentView = nil
            panel?.close()
            hosting = nil
            panel = nil
            anchor = nil
            onDismiss = nil
        }

        private func removeMonitors() {
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            localMonitor = nil
            globalMonitor = nil
        }
    }
}

struct CaptureDestinationPanelSurface: View {
    let rows: [StackItemFacts]
    let selectedID: UUID
    let onSelect: (UUID) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        CaptureDestinationList(rows: rows, selectedID: selectedID, onSelect: onSelect)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(PaletteTint.rim(colorScheme), lineWidth: 0.5)
            }
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .padding(CaptureDestinationPanelLayout.shadowPadding)
        .frame(
            width: CaptureDestinationPanelLayout.panelSize(rowCount: rows.count).width,
            height: CaptureDestinationPanelLayout.panelSize(rowCount: rows.count).height
        )
    }
}

/// Mouse hover only changes the row's background. The checkmark always
/// reflects the destination already chosen for this capture.
struct CaptureDestinationList: View {
    let rows: [StackItemFacts]
    let selectedID: UUID
    let onSelect: (UUID) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        CaptureDestinationRow(
                            row: row, selected: row.id == selectedID,
                            onSelect: { onSelect(row.id) }
                        )
                        .frame(height: CaptureDestinationPanelLayout.rowHeight)
                        .id(row.id)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(
                height: CGFloat(min(
                    max(rows.count, 1), CaptureDestinationPanelLayout.maximumVisibleRows
                )) * CaptureDestinationPanelLayout.rowHeight
            )
            .onAppear { proxy.scrollTo(selectedID) }
        }
        .padding(.vertical, CaptureDestinationPanelLayout.bodyVerticalPadding)
        .frame(width: CaptureDestinationPanelLayout.bodyWidth)
        .background(PaletteTint.surface(colorScheme))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Destination stacks")
    }
}

private struct CaptureDestinationRow: View {
    let row: StackItemFacts
    let selected: Bool
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 12)
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
                Text(row.name)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(row.noteCount)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(hovering ? PaletteTint.hover : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(row.name), \(row.countLabel)")
        .accessibilityValue(selected ? "Selected destination" : "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
