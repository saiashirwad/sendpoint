import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class VoiceModelWatchOwnershipTests: XCTestCase {
    private func services(
        modelFilesExist: (@Sendable () -> Bool)? = nil,
        downloadModel: @escaping @Sendable (
            _ onProgress: @escaping @Sendable (Double) -> Void
        ) async throws -> Void = { _ in }
    ) -> PermissionServices {
        PermissionServices(
            accessibilityStatus: { .granted },
            requestAccessibility: { true },
            microphoneStatus: { .granted },
            requestMicrophone: { true },
            voiceModelFilesExist: modelFilesExist ?? { true },
            downloadVoiceModel: downloadModel,
            openAccessibilitySettings: {},
            openMicrophoneSettings: {}
        )
    }

    private func order(_ uid: String) -> MicrophoneOrder {
        var order = MicrophoneOrder()
        order.absorb([AudioInputDevice(id: 1, uid: uid, name: uid, transport: .other)], systemDefault: nil)
        return order
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () async -> Bool
    ) async {
        for _ in 0..<1_000 {
            if await predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for asynchronous test work")
    }

    func testRedundantStartsShareOneLoopAndOneStopEndsIt() async {
        let files = Locked(false)
        let state = PermissionController(services: services(
            modelFilesExist: { files.value }
        ))
        XCTAssertFalse(state.isWatchingVoiceModel)

        state.startWatchingVoiceModel(interval: .milliseconds(5))
        state.startWatchingVoiceModel(interval: .milliseconds(5))
        XCTAssertTrue(state.isWatchingVoiceModel)

        files.value = true
        await waitUntil { state.localVoiceModel == .ready }

        state.stopWatchingVoiceModel()
        state.stopWatchingVoiceModel()
        XCTAssertFalse(state.isWatchingVoiceModel)

        files.value = false
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(state.localVoiceModel, .ready, "no loop is left to pick up the removal")
        state.teardown()
    }

    func testStopWatchingIsNarrowerThanTeardown() async {
        let state = PermissionController(services: services(
            modelFilesExist: { false },
            downloadModel: { _ in try? await Task.sleep(for: .milliseconds(50)) }
        ))

        state.downloadModel()
        XCTAssertEqual(state.localVoiceModel, .downloading(progress: nil))

        state.startWatchingVoiceModel(interval: .milliseconds(5))
        XCTAssertTrue(state.isWatchingVoiceModel)
        state.stopWatchingVoiceModel()
        XCTAssertFalse(state.isWatchingVoiceModel)
        XCTAssertEqual(state.localVoiceModel, .downloading(progress: nil), "releasing the poll leaves the download alone")

        await state.waitForIdle()
        XCTAssertEqual(state.localVoiceModel, .ready)
        state.teardown()
    }

    func testTeardownStopsTheWatchAndIgnoresUnbalancedStops() {
        let state = PermissionController(services: services())
        state.startWatchingVoiceModel()
        XCTAssertTrue(state.isWatchingVoiceModel)

        state.teardown()
        XCTAssertFalse(state.isWatchingVoiceModel)

        state.startWatchingVoiceModel()
        XCTAssertFalse(state.isWatchingVoiceModel, "no watch starts after teardown")
        state.stopWatchingVoiceModel()
        state.teardown()
    }
}
