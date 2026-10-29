import AVFoundation
import Speech

/// Push-to-talk into Fenn: on-device speech recognition when the Mac supports it.
/// Keeps listening through pauses: the recognizer closes a segment at every pause, so each finished segment is kept
/// and a new one starts. Ends on the stop button, after `silenceTimeout` without new words, or at `maxDuration`.
@MainActor
final class DictationController: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    /// 0…1 microphone level for the waveform.
    @Published private(set) var level: Float = 0
    @Published private(set) var errorMessage: String?

    var onFinish: (String) -> Void = { _ in }

    /// Coach requests stop after five minutes; voice notes may run for ten.
    private let maxDuration: Duration
    private let silenceTimeout: TimeInterval

    init(maxDuration: Duration = .seconds(300), silenceTimeout: TimeInterval = 6) {
        self.maxDuration = maxDuration
        self.silenceTimeout = silenceTimeout
    }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: tr("de-DE", "en-US")))
    private let audioEngine = AVAudioEngine()
    private let sink = SpeechSink()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var session = 0
    private var generation = 0
    private var committed = ""
    private var segment = ""
    private var failures = 0
    private var lastWords = Date()

    func toggle() {
        if isListening {
            stop()
        } else {
            Task { await start() }
        }
    }

    func start() async {
        guard !isListening else { return }
        errorMessage = nil
        guard await SpeechPermission.request(microphone: true) else {
            errorMessage = tr("Mikrofon oder Spracherkennung nicht erlaubt – Systemeinstellungen › Datenschutz & Sicherheit.",
                              "Microphone or speech recognition not allowed – System Settings › Privacy & Security.")
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = tr("Spracherkennung ist gerade nicht verfügbar.", "Speech recognition is unavailable right now.")
            return
        }

        let input = audioEngine.inputNode
        let sink = sink
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            sink.append(buffer)
            let level = Self.level(of: buffer)
            Task { @MainActor in self?.level = level }
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            errorMessage = error.localizedDescription
            return
        }

        transcript = ""
        committed = ""
        segment = ""
        failures = 0
        lastWords = Date()
        isListening = true
        session += 1
        let current = session
        startSegment()

        // Pauses to think are fine; a long silence or a forgotten dictation ends it.
        Task { @MainActor [weak self] in
            let started = ContinuousClock.now
            while let self, self.session == current, self.isListening {
                try? await Task.sleep(for: .milliseconds(500))
                guard self.session == current, self.isListening else { return }
                if Date().timeIntervalSince(self.lastWords) > self.silenceTimeout || ContinuousClock.now - started > self.maxDuration {
                    self.stop()
                    return
                }
            }
        }
    }

    func stop() {
        guard isListening else { return }
        request?.endAudio()
        stopAudio()
        // The recognizer delivers the last segment shortly after endAudio(); don't wait forever for it.
        let current = session
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            if self?.session == current { self?.finish() }
        }
    }

    private func startSegment() {
        guard let recognizer, isListening, audioEngine.isRunning else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request?.endAudio()
        self.request = request
        sink.set(request)
        generation += 1
        let current = generation
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in self?.handle(current, text: text, isFinal: isFinal, failed: failed) }
        }
    }

    private func handle(_ current: Int, text: String?, isFinal: Bool, failed: Bool) {
        guard current == generation, isListening else { return }
        if let text, !text.isEmpty {
            // Some versions start the transcription over after a pause inside the same task: keep what was said.
            if segment.count > 12, text.count < segment.count * 6 / 10 { commit() }
            segment = text
            lastWords = Date()
            failures = 0
            transcript = Self.join(committed, segment)
        }
        guard isFinal || failed else { return }
        commit()
        if failed && (text ?? "").isEmpty { failures += 1 }
        // Stopped by the user (audio off) or repeated errors without words: done.
        if !audioEngine.isRunning || failures >= 5 { finish(); return }
        startSegment()
    }

    private func commit() {
        guard !segment.isEmpty else { return }
        committed = Self.join(committed, segment)
        segment = ""
        transcript = committed
    }

    private func finish() {
        guard isListening else { return }
        commit()
        isListening = false
        session += 1
        generation += 1
        sink.set(nil)
        stopAudio()
        task?.cancel()
        task = nil
        request = nil
        level = 0
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { onFinish(text) }
    }

    private func stopAudio() {
        guard audioEngine.isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private static func join(_ a: String, _ b: String) -> String {
        let a = a.trimmingCharacters(in: .whitespaces), b = b.trimmingCharacters(in: .whitespaces)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        let ends = a.last.map { ".!?…".contains($0) } ?? false
        return a + (ends ? " " : ". ") + b.prefix(1).uppercased() + b.dropFirst()
    }

    private nonisolated static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        return min(1, (sum / Float(buffer.frameLength)).squareRoot() * 12)
    }
}

/// The audio tap runs off the main thread; it feeds whichever request is current.
private final class SpeechSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); self.request = request; lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); let request = self.request; lock.unlock()
        request?.append(buffer)
    }
}
