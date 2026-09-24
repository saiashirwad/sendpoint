import AppKit
import SendpointDomain
import SwiftUI
import XCTest
@testable import Sendpoint

@MainActor
final class SetupRenderTests: XCTestCase {
    func testRenderEverySetupStage() async throws {
        guard let directory = ProcessInfo.processInfo.environment["SENDPOINT_RENDER_DIR"] else {
            throw XCTSkip("Set SENDPOINT_RENDER_DIR to produce manual review images.")
        }
        struct Fixture {
            let name: String
            let accessibility: AccessibilityPermissionState
            let microphone: MicrophonePermissionState
            let modelExists: Bool
            let download: (@Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void)?
            var tourStep: Int? = nil
        }
        struct Failed: LocalizedError { var errorDescription: String? { "boom" } }
        let fixtures: [Fixture] = [
            .init(name: "accessibility", accessibility: .notGranted, microphone: .notDetermined, modelExists: false, download: nil),
            .init(name: "microphone", accessibility: .granted, microphone: .notDetermined, modelExists: false, download: nil),
            .init(name: "microphone-settings", accessibility: .granted, microphone: .denied, modelExists: false, download: nil),
            .init(name: "voice-model", accessibility: .granted, microphone: .granted, modelExists: false, download: nil),
            .init(name: "downloading", accessibility: .granted, microphone: .granted, modelExists: false, download: { report in
                report(0.42)
                try await Task.sleep(for: .seconds(60))
            }),
            .init(name: "failed", accessibility: .granted, microphone: .granted, modelExists: false, download: { _ in
                throw Failed()
            }),
            .init(name: "tour-voice", accessibility: .granted, microphone: .granted, modelExists: true, download: nil, tourStep: 0),
            .init(name: "tour-text", accessibility: .granted, microphone: .granted, modelExists: true, download: nil, tourStep: 1),
            .init(name: "tour-send", accessibility: .granted, microphone: .granted, modelExists: true, download: nil, tourStep: 2),
        ]
        for fixture in fixtures {
            let defaults = UserDefaults(suiteName: "SetupRenderTests.\(UUID().uuidString)")!
            let state = PermissionController(services: PermissionServices(
                accessibilityStatus: { fixture.accessibility },
                requestAccessibility: { true },
                microphoneStatus: { fixture.microphone },
                requestMicrophone: { true },
                voiceModelFilesExist: { fixture.modelExists },
                downloadVoiceModel: { report in try await fixture.download?(report) },
                openAccessibilitySettings: {},
                openMicrophoneSettings: {}
            ))
            if fixture.download != nil {
                state.downloadModel()
                try await Task.sleep(for: .milliseconds(150))
            }
            let tour = SetupTour()
            for _ in 0..<(fixture.tourStep ?? 0) { tour.send(.skip) }
            let hosting = NSHostingView(rootView: SetupView(
                settings: AppSettings(defaults: defaults),
                permissionState: state,
                tour: tour,
                shortcuts: ShortcutSettings(defaults: defaults),
                voiceSettings: VoiceSettings(defaults: defaults),
                onComplete: {},
                onDismiss: {}
            ))
            hosting.frame = NSRect(origin: .zero, size: SetupView.size)
            let window = NSWindow(
                contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(250))
            hosting.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: directory).appendingPathComponent("setup-\(fixture.name).png")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            window.contentView = nil
            window.close()
            state.teardown()
        }
    }
}
