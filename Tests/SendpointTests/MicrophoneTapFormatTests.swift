import AVFoundation
import XCTest
@testable import Sendpoint

final class MicrophoneTapFormatTests: XCTestCase {
    private func format(_ rate: Double, channels: AVAudioChannelCount = 1) -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
    }

    func testMatchingRatesKeepTheOutputFormat() {
        let output = format(48_000)
        XCTAssertIdentical(MicrophoneTapFormat.valid(output: output, hardware: format(48_000, channels: 2)), output)
    }

    func testAHardwareRateChangeRejectsTheTap() {
        XCTAssertNil(MicrophoneTapFormat.valid(output: format(48_000), hardware: format(24_000)))
    }
}
