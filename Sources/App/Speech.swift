import AVFoundation
import Core
import Speech

/// Microphone + on-device transcription. Reports back only through `send`,
/// tagged with the take number, so a late result for an old take is inert.
final class Speech {
    private(set) var status = "Preparing speech…"
    private let engine = AVAudioEngine()
    private var locale = Locale.current
    private var format: AVAudioFormat?
    /// A prepared transcriber + analyzer, so a take starts without loading anything.
    private var spare: (SpeechTranscriber, SpeechAnalyzer)?
    private var current: (take: Int, input: AsyncStream<AnalyzerInput>.Continuation, analyzer: SpeechAnalyzer)?

    func prewarm() {
        Task {
            guard await AVCaptureDevice.requestAccess(for: .audio) else { return report("Microphone access denied") }
            guard SpeechTranscriber.isAvailable else { return report("Speech unavailable on this Mac") }
            locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) ?? Locale(identifier: "en-US")
            let probe = makeTranscriber()
            do {
                if let install = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
                    report("Downloading speech model…")
                    try await install.downloadAndInstall()
                }
            } catch { return report("Speech model unavailable: \(error.localizedDescription)") }
            format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [probe])
            await prepareSpare()
            report(format == nil ? "Speech unavailable" : "")
        }
    }

    func start(take: Int) {
        guard let format else { return send(.final(take: take, "")) }
        let (transcriber, analyzer) = spare ?? fresh()
        spare = nil
        let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let mic = engine.inputNode.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: mic, to: format) else { return send(.final(take: take, "")) }
        let tap = Tap(converter: converter, output: format, input: input)
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: mic) { @Sendable buffer, _ in tap.feed(buffer) }
        do { try engine.start() } catch {
            engine.inputNode.removeTap(onBus: 0)
            return send(.final(take: take, ""))
        }
        current = (take, input, analyzer)

        let results = Task {
            var text = ""
            for try await result in transcriber.results {
                let piece = String(result.text.characters)
                if result.isFinal { text = Self.append(text, piece) }
                send(.partial(take: take, result.isFinal ? text : Self.append(text, piece)))
            }
            return text
        }
        Task {
            do {
                if let end = try await analyzer.analyzeSequence(stream) {
                    try await analyzer.finalizeAndFinish(through: end)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
                send(.final(take: take, try await results.value))
            } catch {
                results.cancel()
                send(.final(take: take, ""))
            }
            await prepareSpare()
        }
    }

    /// Ends the audio; the take's task finalizes and sends `.final`.
    func stop(take: Int) {
        guard let current, current.take == take else { return }
        stopMic()
        current.input.finish()
        self.current = nil
    }

    func cancel() {
        guard let current else { return }
        stopMic()
        current.input.finish()
        self.current = nil
        Task { await current.analyzer.cancelAndFinishNow() }
    }

    private func stopMic() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func prepareSpare() async {
        guard spare == nil, let format else { return }
        let pair = fresh()
        try? await pair.1.prepareToAnalyze(in: format)
        if spare == nil { spare = pair }
    }

    private func fresh() -> (SpeechTranscriber, SpeechAnalyzer) {
        let transcriber = makeTranscriber()
        let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
        return (transcriber, SpeechAnalyzer(modules: [transcriber], options: options))
    }

    private func makeTranscriber() -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    }

    private func report(_ message: String) {
        status = message
        render()
    }

    private static func append(_ text: String, _ piece: String) -> String {
        if text.isEmpty || piece.isEmpty || text.last!.isWhitespace || piece.first!.isWhitespace { return text + piece }
        return text + " " + piece
    }
}

/// Runs on the audio thread: converts mic buffers to the analyzer's format.
nonisolated final class Tap: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let output: AVAudioFormat
    private let input: AsyncStream<AnalyzerInput>.Continuation

    init(converter: AVAudioConverter, output: AVAudioFormat, input: AsyncStream<AnalyzerInput>.Continuation) {
        self.converter = converter
        self.output = output
        self.input = input
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        let ratio = output.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return }
        nonisolated(unsafe) var supplied = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, converted.frameLength > 0 { input.yield(AnalyzerInput(buffer: converted)) }
    }
}
