import AVFoundation
import Dispatch
import FluidAudio
import Foundation

// Research-only blocking API. Do not call on an app UI thread.
// UTF-8 pointer is borrowed for the duration of the callback; no Swift values cross ABI.
public typealias Event = @convention(c) @Sendable (Int32, UnsafePointer<CChar>?) -> Void

@_cdecl("odin_fluid_probe")
public func odinFluidProbe(_ cache: UnsafePointer<CChar>, _ wav: UnsafePointer<CChar>, _ event: Event) {
    let cachePath = String(cString: cache)
    let wavPath = String(cString: wav)
    let done = DispatchSemaphore(value: 0)
    let task = Task {
        defer { done.signal() }
        let manager = StreamingUnifiedAsrManager(config: UnifiedConfig(leftFrames: 70, chunkFrames: 2, rightFrames: 2))
        func emit(_ kind: Int32, _ text: String) { text.withCString { event(kind, $0) } }
        do {
            let start = DispatchTime.now().uptimeNanoseconds
            try Task.checkCancellation()
            try await manager.loadModels(from: URL(fileURLWithPath: cachePath))
            try Task.checkCancellation()
            emit(0, "load_ms=\(Double(DispatchTime.now().uptimeNanoseconds-start)/1e6)")
            await manager.setPartialTranscriptCallback { text in text.withCString { event(1, $0) } }
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: wavPath))
            let step = AVAudioFrameCount(file.processingFormat.sampleRate / 50)
            let decodeStart = DispatchTime.now().uptimeNanoseconds
            while file.framePosition < file.length {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: step) else {
                    throw NSError(domain: "probe", code: 1)
                }
                try file.read(into: buffer, frameCount: step)
                try Task.checkCancellation()
                try await manager.appendAudio(buffer)
                try await manager.processBufferedAudio()
                try Task.checkCancellation()
            }
            let tailStart = DispatchTime.now().uptimeNanoseconds
            let result = try await manager.finish()
            try Task.checkCancellation()
            emit(2, result)
            emit(0, "tail_ms=\(Double(DispatchTime.now().uptimeNanoseconds-tailStart)/1e6) decode_ms=\(Double(DispatchTime.now().uptimeNanoseconds-decodeStart)/1e6)")
            try await manager.reset()
        } catch {
            emit(3, String(describing: error))
        }
        await manager.cleanup()
    }
    done.wait()
    withExtendedLifetime(task) {}
}
