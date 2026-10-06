import AVFoundation
import XCTest
@testable import Sendpoint

final class VoiceAudioFrameTests: XCTestCase {
    func testFloatFramesSelectTheLoudestChannelAndOwnTheirSamples() throws {
        for interleaved in [false, true] {
            let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                                  channels: 2, interleaved: interleaved))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3))
            buffer.frameLength = 3
            let channels = try XCTUnwrap(buffer.floatChannelData)
            let expected: [Float] = [0.8, -0.9, 1]
            for index in 0..<3 {
                channels[0][index * buffer.stride] = 0.1
                channels[interleaved ? 0 : 1][index * buffer.stride + (interleaved ? 1 : 0)] = expected[index]
            }
            let frame = try XCTUnwrap(VoiceAudioFrame(buffer: buffer))
            XCTAssertEqual(frame.samples, expected, "interleaved=\(interleaved)")
            XCTAssertEqual(frame.sampleRate, 48_000)
            channels[0][0] = 0
            channels[interleaved ? 0 : 1][interleaved ? 1 : 0] = 0
            XCTAssertEqual(frame.samples, expected)
        }
    }

    func testIntegerFramesHonorInterleavedStride() throws {
        for interleaved in [false, true] {
            let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                                  channels: 2, interleaved: interleaved))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3))
            buffer.frameLength = 3
            let channels = try XCTUnwrap(buffer.int16ChannelData)
            let loud: [Int16] = [10_000, -20_000, 30_000]
            for index in 0..<3 {
                channels[0][index * buffer.stride] = 100
                channels[interleaved ? 0 : 1][index * buffer.stride + (interleaved ? 1 : 0)] = loud[index]
            }
            let frame = try XCTUnwrap(VoiceAudioFrame(buffer: buffer))
            XCTAssertEqual(frame.samples, loud.map { Float($0) * (1 / Float(Int16.max)) }, "interleaved=\(interleaved)")
        }
    }
}
