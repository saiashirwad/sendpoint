import Foundation
import SendpointDomain

final class VoiceNoteService {
    private enum Work: Hashable { case warmUp, start, stream, finish, settle }

    static let streamOpenAttempts = 5
    private static let microphoneDenied = "Microphone access is off. Turn it on in Settings › Voice."

    private(set) var machine = VoiceMachine()
    private let transcriber: any VoiceTranscribing
    private let microphone: Microphone
    private let modelReady: () -> Bool
    private let now: () -> Date
    private var tasks: [Work: Task<Void, Never>] = [:]
    private var teardownTask: Task<Void, Never>?
    private var queue: PreviewAudioQueue?
    private let partials = LatestValuePump<String>()
    private var pending: [VoiceEvent] = []
    private var isDraining = false

    let levelMeter: VoiceLevelMeter
    var microphones = MicrophoneOrder()
    var onOutput: ((VoiceOutput) -> Void)?

    init(
        transcriber: any VoiceTranscribing,
        levelMeter: VoiceLevelMeter = VoiceLevelMeter(),
        microphone: Microphone? = nil,
        modelReady: @escaping () -> Bool = { LocalVoiceModelFiles.exist() },
        now: @escaping () -> Date = { Date() }
    ) {
        self.transcriber = transcriber
        self.levelMeter = levelMeter
        self.microphone = microphone ?? .live(meter: levelMeter)
        self.modelReady = modelReady
        self.now = now
    }

    func warmUp() { send(.warmUp) }
    func start(_ take: UUID) { send(.start(take, modelReady: modelReady())) }
    func stop(_ take: UUID) { send(.stop(take, now: now())) }
    func discard() { send(.discard) }
    func teardown() { send(.teardown) }

    func waitForTeardown() async {
        await teardownTask?.value
    }

    private func send(_ event: VoiceEvent) {
        pending.append(event)
        guard !isDraining else { return }
        isDraining = true
        while !pending.isEmpty {
            for effect in machine.update(pending.removeFirst()) { run(effect) }
        }
        isDraining = false
    }

    private func run(_ effect: VoiceEffect) {
        switch effect {
        case .prepare: prepare()
        case let .startMic(take): startMicrophone(take)
        case .stopMic:
            tasks.removeValue(forKey: .start)?.cancel()
            microphone.stop()
        case let .finish(take): finish(take)
        case .abandon: abandon()
        case .tearDown: tearDown()
        case let .emit(output): onOutput?(output)
        }
    }

    private func prepare() {
        microphone.prepare()
        guard tasks[.warmUp] == nil, modelReady() else { return }
        tasks[.warmUp] = Task { [weak self, transcriber] in
            await transcriber.prepareIfNeeded()
            guard !Task.isCancelled else { return }
            self?.tasks[.warmUp] = nil
        }
    }

    private func startMicrophone(_ take: UUID) {
        tasks[.start]?.cancel()
        tasks[.start] = Task { [weak self, microphone] in
            let allowed = await microphone.requestAccess()
            guard !Task.isCancelled, let self, self.machine.phase == .starting(take) else { return }
            self.tasks[.start] = nil
            guard allowed else {
                self.send(.micFailed(take, Self.microphoneDenied))
                return
            }
            do {
                let queue = try microphone.start(self.microphones)
                self.queue = queue
                self.stream(queue, take: take)
                self.send(.micStarted(take, self.now()))
            } catch {
                self.send(.micFailed(take, error.localizedDescription))
            }
        }
    }

    private func stream(_ queue: PreviewAudioQueue, take: UUID) {
        let partial = partials.start { [weak self] text in
            guard let self, self.machine.take == take else { return }
            self.onOutput?(.partial(take, text))
        }
        tasks[.stream]?.cancel()
        tasks[.stream] = Task { [transcriber] in
            var isOpen = false
            for _ in 0..<Self.streamOpenAttempts where !Task.isCancelled && !isOpen {
                isOpen = await transcriber.begin(take, onPartial: { partial.yield($0) })
                if !isOpen { try? await Task.sleep(for: .milliseconds(50)) }
            }
            guard isOpen else { return }
            while !Task.isCancelled {
                let frames = queue.drain()
                if frames.isEmpty {
                    try? await Task.sleep(for: .milliseconds(5))
                    continue
                }
                await transcriber.feed(frames, take: take)
            }
        }
    }

    private func finish(_ take: UUID) {
        let pump = tasks.removeValue(forKey: .stream)
        pump?.cancel()
        let queue = queue
        self.queue = nil
        tasks[.finish] = Task { [weak self, transcriber] in
            await pump?.value
            guard !Task.isCancelled else { return }
            Diag.log("voice transcription finishing")
            do {
                let transcript = try await transcriber.finish(take, leftover: queue?.drain() ?? [])
                guard !Task.isCancelled, let self else { return }
                self.tasks[.finish] = nil
                self.partials.stop()
                self.send(.transcribed(take, transcript.nonblank ?? ""))
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.tasks[.finish] = nil
                self.partials.stop()
                self.send(.transcriptionFailed(take, error.localizedDescription))
            }
        }
    }

    private func abandon() {
        let pump = tasks.removeValue(forKey: .stream)
        pump?.cancel()
        tasks.removeValue(forKey: .finish)?.cancel()
        queue = nil
        partials.stop()
        Diag.log("voice recording discarded")
        tasks[.settle] = Task { [weak self, transcriber] in
            await pump?.value
            await transcriber.abandon()
            guard !Task.isCancelled, let self else { return }
            self.tasks[.settle] = nil
            self.send(.settled)
        }
    }

    private func tearDown() {
        let running = Array(tasks.values)
        running.forEach { $0.cancel() }
        tasks.removeAll()
        queue = nil
        partials.stop()
        onOutput = nil
        teardownTask = Task { [transcriber] in
            await transcriber.teardown()
            for task in running { await task.value }
        }
    }
}
