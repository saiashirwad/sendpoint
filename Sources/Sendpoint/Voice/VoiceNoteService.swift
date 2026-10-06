import Foundation
import SendpointDomain

final class VoiceNoteService {
    private enum Work: Hashable { case micWarmUp, modelWarmUp, start, stop, settle }
    private enum Settlement { case finish, abandon }
    private final class Take {
        let audio: VoiceAudioTake
        var transcription: Task<String, Error>?
        init(_ id: UUID) { audio = VoiceAudioTake(id: id) }
    }

    private static let microphoneDenied = "Microphone access is off. Turn it on in Settings › Voice."
    private(set) var machine = VoiceMachine()
    private let transcriber: any VoiceTranscribing
    private let microphone: Microphone
    private let modelReady: () -> Bool
    private let now: () -> Date
    private var tasks: [Work: Task<Void, Never>] = [:]
    private var stopGeneration = 0
    private var teardownTask: Task<Void, Never>?
    private var take: Take?
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
    func waitForTeardown() async { await teardownTask?.value }

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
        case .finish: settle(.finish)
        case .abandon: settle(.abandon)
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

    private func startMicrophone(_ id: UUID) {
        tasks[.start]?.cancel()
        let warming = tasks[.micWarmUp]
        let stopped = tasks[.stop]
        let owner = Take(id)
        take = owner
        tasks[.start] = Task { [weak self, microphone] in
            await stopped?.value
            await warming?.value
            guard !Task.isCancelled else { return }
            let allowed = await microphone.requestAccess()
            guard !Task.isCancelled, let self, self.take === owner,
                  self.machine.phase == .starting(id) else { return }
            guard allowed else {
                self.tasks[.start] = nil
                self.send(.micFailed(id, Self.microphoneDenied))
                return
            }
            let order = self.microphones
            do {
                try await microphone.start(order, owner.audio)
                guard !Task.isCancelled, self.take === owner,
                      self.machine.phase == .starting(id) else { return }
                if self.restartIfMicrophoneOrderChanged(order, take: id) { return }
                self.tasks[.start] = nil
                self.transcribe(owner)
                self.send(.micStarted(id, self.now()))
            } catch {
                guard !Task.isCancelled, self.take === owner,
                      self.machine.phase == .starting(id) else { return }
                if self.restartIfMicrophoneOrderChanged(order, take: id) { return }
                self.tasks[.start] = nil
                self.send(.micFailed(id, error.localizedDescription))
            }
        }
    }

    private func restartIfMicrophoneOrderChanged(_ order: MicrophoneOrder, take: UUID) -> Bool {
        guard microphones != order else { return false }
        stopMicrophone()
        startMicrophone(take)
        return true
    }

    private func stopMicrophone() {
        let starting = tasks.removeValue(forKey: .start)
        starting?.cancel()
        let previousStop = tasks.removeValue(forKey: .stop)
        let owner = take
        stopGeneration += 1
        let current = stopGeneration
        tasks[.stop] = Task { [weak self, microphone] in
            await starting?.value
            await previousStop?.value
            await microphone.stop()
            owner?.audio.close()
            guard let self, self.stopGeneration == current else { return }
            if self.take === owner, owner?.transcription == nil { self.take = nil }
            self.tasks[.stop] = nil
        }
    }

    private func transcribe(_ owner: Take) {
        let partial = partials.start { [weak self] text in
            guard let self, self.take === owner, self.machine.take == owner.audio.id else { return }
            self.onOutput?(.partial(owner.audio.id, text))
        }
        owner.transcription = Task { [weak self, transcriber, audio = owner.audio] in
            do {
                try Task.checkCancellation()
                return try await transcriber.transcribe(audio, onPartial: { partial.yield($0) })
            } catch {
                if !Task.isCancelled, let self, self.take === owner, self.machine.take == audio.id {
                    self.send(.transcriptionFailed(audio.id, error.localizedDescription))
                }
                throw error
            }
        }
    }

    private func settle(_ settlement: Settlement) {
        guard let owner = take else {
            if settlement == .abandon { send(.settled) }
            return
        }
        let previous = tasks[.settle]
        previous?.cancel()
        if settlement == .abandon {
            owner.transcription?.cancel()
            partials.stop()
        }
        let stopped = tasks[.stop]
        tasks[.settle] = Task { [weak self] in
            await stopped?.value
            await previous?.value
            let outcome = await owner.transcription?.result
            guard !Task.isCancelled, let self, self.take === owner else { return }
            self.take = nil
            self.tasks[.settle] = nil
            self.partials.stop()
            if settlement == .abandon {
                self.send(.settled)
            } else if self.machine.phase == .transcribing(owner.audio.id) {
                switch outcome {
                case let .success(text): self.send(.transcribed(owner.audio.id, text.nonblank ?? ""))
                case let .failure(error): self.send(.transcriptionFailed(owner.audio.id, error.localizedDescription))
                case nil: self.send(.transcriptionFailed(owner.audio.id, "Transcription did not start."))
                }
            }
        }
    }

    private func tearDown() {
        let running = Array(tasks.values)
        running.forEach { $0.cancel() }
        tasks.removeAll()
        let transcription = take?.transcription
        transcription?.cancel()
        take?.audio.close()
        take = nil
        partials.stop()
        onOutput = nil
        teardownTask = Task { [transcriber, microphone] in
            await transcriber.teardown()
            _ = await transcription?.result
            for task in running { await task.value }
            await microphone.teardown()
        }
    }
}
