import Foundation
import SendpointDomain

final class VoiceNoteService {
    private enum Work: Hashable { case micWarmUp, modelWarmUp, start, stop, stream, finish, settle }

    static let streamOpenAttempts = 5
    private static let microphoneDenied = "Microphone access is off. Turn it on in Settings › Voice."

    private(set) var machine = VoiceMachine()
    private let transcriber: any VoiceTranscribing
    private let microphone: Microphone
    private let modelReady: () -> Bool
    private let now: () -> Date
    private var tasks: [Work: Task<Void, Never>] = [:]
    private var stopGeneration = 0
    private var teardownTask: Task<Void, Never>?
    private var queue: VoiceAudioQueue?
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
        case .stopMic: stopMicrophone()
        case let .finish(take): finish(take)
        case .abandon: abandon()
        case .tearDown: tearDown()
        case let .emit(output): onOutput?(output)
        }
    }

    private func prepare() {
        let order = microphones
        if tasks[.micWarmUp] == nil {
            let stopped = tasks[.stop]
            tasks[.micWarmUp] = Task { [weak self, microphone] in
                await stopped?.value
                guard !Task.isCancelled else { return }
                await microphone.prepare(order)
                guard !Task.isCancelled else { return }
                self?.tasks[.micWarmUp] = nil
            }
        }
        if tasks[.modelWarmUp] == nil, modelReady() {
            tasks[.modelWarmUp] = Task { [weak self, transcriber] in
                await transcriber.prepareIfNeeded()
                guard !Task.isCancelled else { return }
                self?.tasks[.modelWarmUp] = nil
            }
        }
    }

    private func startMicrophone(_ take: UUID) {
        tasks[.start]?.cancel()
        let warming = tasks.removeValue(forKey: .micWarmUp)
        let stopped = tasks[.stop]
        tasks[.start] = Task { [weak self, microphone] in
            await stopped?.value
            await warming?.value
            guard !Task.isCancelled else { return }
            let allowed = await microphone.requestAccess()
            guard !Task.isCancelled, let self, self.machine.phase == .starting(take) else { return }
            guard allowed else {
                self.tasks[.start] = nil
                self.send(.micFailed(take, Self.microphoneDenied))
                return
            }
            let order = self.microphones
            do {
                let queue = try await microphone.start(order)
                guard !Task.isCancelled, self.machine.phase == .starting(take) else { return }
                if self.microphones != order {
                    self.stopMicrophone()
                    self.startMicrophone(take)
                    return
                }
                self.tasks[.start] = nil
                self.queue = queue
                self.stream(queue, take: take)
                self.send(.micStarted(take, self.now()))
            } catch {
                guard !Task.isCancelled, self.machine.phase == .starting(take) else { return }
                if self.microphones != order {
                    self.stopMicrophone()
                    self.startMicrophone(take)
                    return
                }
                self.tasks[.start] = nil
                self.send(.micFailed(take, error.localizedDescription))
            }
        }
    }

    private func stopMicrophone() {
        let starting = tasks.removeValue(forKey: .start)
        starting?.cancel()
        let previousStop = tasks.removeValue(forKey: .stop)
        stopGeneration += 1
        let current = stopGeneration
        tasks[.stop] = Task { [weak self, microphone] in
            await starting?.value
            await previousStop?.value
            await microphone.stop()
            guard let self, self.stopGeneration == current else { return }
            self.tasks[.stop] = nil
        }
    }

    private func stream(_ queue: VoiceAudioQueue, take: UUID) {
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
        let stopped = tasks[.stop]
        let queue = queue
        self.queue = nil
        tasks[.finish] = Task { [weak self, transcriber] in
            await stopped?.value
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
        teardownTask = Task { [transcriber, microphone] in
            await transcriber.teardown()
            for task in running { await task.value }
            await microphone.teardown()
        }
    }
}
