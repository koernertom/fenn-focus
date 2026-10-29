import Foundation
import AVFoundation

// Fenn's voice. Lines recorded ahead of time (ElevenLabs via Scripts/make_voice.py → Resources/Voice/<de|en>/<key>.mp3)
// play as audio – whole, or put together from pieces ("Kilometer" · 5 · "Schnitt" · 5 · "Minuten" · 30 · "pro Kilometer").
// Never two voices: in a language with recordings, a line without them stays unspoken; a language without any
// recordings uses the best installed Apple voice throughout.

final class FennVoice: NSObject {
    struct Style {
        /// Multiplier on Apple's default rate (recorded clips already carry their pace).
        var rate: Float = 1
        var volume: Float = 1
        var preDelay: TimeInterval = 0
        var postDelay: TimeInterval = 0

        static let cue = Style()
        static let calm = Style(rate: 0.9, volume: 0.75, preDelay: 0.3, postDelay: 0.4)
    }

    /// Called on the main thread when Fenn starts and stops talking (the background ducks meanwhile).
    var onSpeaking: (Bool) -> Void = { _ in }
    private(set) var isSpeaking = false

    private struct Line {
        let text: String
        let clips: [URL]?
        let style: Style
    }

    private let synth = AVSpeechSynthesizer()
    private let player = AVQueuePlayer()
    private var queue: [Line] = []
    private var current: Line?
    private var pending: DispatchWorkItem?
    private var lastClip: AVPlayerItem?
    private var paused = false

    override init() {
        super.init()
        synth.delegate = self
        player.actionAtItemEnd = .advance
        NotificationCenter.default.addObserver(self, selector: #selector(itemEnded(_:)), name: AVPlayerItem.didPlayToEndTimeNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: Speaking

    /// Queues a line; it plays after whatever Fenn is saying right now. False when it stays unspoken
    /// (empty, or no recording for it while this language has recordings).
    /// `set` names a session with its own voice (Voice/<lang>/<set>/) – its clips win over the shared ones.
    @discardableResult
    func say(_ text: String, style: Style = .cue, set: String? = nil) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let clips = Self.clips(for: text, set: set)
        guard clips != nil || !Self.hasRecordings else { return false }
        queue.append(Line(text: text, clips: clips, style: style))
        if current == nil { next() }
        return true
    }

    func pause() {
        guard current != nil, !paused else { return }
        paused = true
        if synth.isSpeaking { synth.pauseSpeaking(at: .word) }
        player.pause()
    }

    func resume() {
        guard paused else { return }
        paused = false
        if synth.isPaused { synth.continueSpeaking() }
        if player.currentItem != nil { player.play() }
    }

    func stop() {
        queue = []
        current = nil
        paused = false
        pending?.cancel()
        pending = nil
        synth.stopSpeaking(at: .immediate)
        player.removeAllItems()
        lastClip = nil
        setSpeaking(false)
    }

    private func next() {
        guard !queue.isEmpty else {
            current = nil
            setSpeaking(false)
            return
        }
        let line = queue.removeFirst()
        current = line
        setSpeaking(true)
        if let clips = line.clips {
            let work = DispatchWorkItem { [weak self] in self?.play(clips, volume: line.style.volume) }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + line.style.preDelay, execute: work)
        } else {
            synth.speak(Self.utterance(line.text, style: line.style))
        }
    }

    private func play(_ clips: [URL], volume: Float) {
        player.removeAllItems()
        let items = clips.map(AVPlayerItem.init(url:))
        items.forEach { player.insert($0, after: nil) }
        lastClip = items.last
        player.volume = volume
        if !paused { player.play() }
    }

    @objc private func itemEnded(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let item = note.object as? AVPlayerItem, item === self.lastClip, let line = self.current else { return }
            self.lastClip = nil
            self.finish(after: line.style.postDelay)
        }
    }

    private func finish(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in self?.next() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func setSpeaking(_ speaking: Bool) {
        guard speaking != isSpeaking else { return }
        isSpeaking = speaking
        onSpeaking(speaking)
    }

    // MARK: Apple voice

    private static func utterance(_ text: String, style: Style) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = bestVoice
        // Compact voices sound rushed when slowed only a little – calm lines drop a bit further with them.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * style.rate * (style.rate < 1 && !hasNaturalVoice ? 0.9 : 1)
        utterance.volume = style.volume
        utterance.preUtteranceDelay = style.preDelay
        utterance.postUtteranceDelay = style.postDelay
        return utterance
    }

    /// The best installed voice: Premium, then Enhanced, then the default.
    static var bestVoice: AVSpeechSynthesisVoice? {
        let language = tr("de-DE", "en-US")
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        return voices.first { $0.quality == .premium } ?? voices.first { $0.quality == .enhanced } ?? AVSpeechSynthesisVoice(language: language)
    }

    static var hasNaturalVoice: Bool { (bestVoice?.quality ?? .default) != .default }

    // MARK: Recorded clips

    /// The bundled clips for the current language – only once all of them were recorded (the script writes the manifest last).
    static var folder: URL? {
        guard let url = Bundle.main.url(forResource: "Voice", withExtension: nil)?.appendingPathComponent(tr("de", "en")),
              FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path) else { return nil }
        return url
    }

    static var hasRecordings: Bool { folder != nil }

    /// The clips for a whole line, or nil when there are no recordings or any piece is missing.
    /// Same rules as `pieces` in Scripts/make_voice.py.
    static func clips(for text: String, set: String? = nil) -> [URL]? {
        guard let folder else { return nil }
        // A set with its own folder never falls back to the shared voice – one voice per session.
        let own = set.map { folder.appendingPathComponent($0, isDirectory: true) }.flatMap {
            FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
        }
        func file(_ key: String) -> URL? {
            let url = (own ?? folder).appendingPathComponent(key + ".mp3")
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if let whole = file(textKey(text)) { return [whole] }
        var urls: [URL] = []
        for key in pieces(text) {
            guard let url = file(key) else {
                #if DEBUG
                print("FennVoice: no clip for “\(text)” – stays unspoken")
                #endif
                return nil
            }
            urls.append(url)
        }
        return urls.isEmpty ? nil : urls
    }

    /// Numbers become n<value>; a decimal reads "5 Komma 2"; the words between numbers are one clip each.
    static func pieces(_ text: String) -> [String] {
        var keys: [String] = []
        var words = ""
        func flushWords() {
            if !normalize(words).isEmpty { keys.append(textKey(words)) }
            words = ""
        }
        let scalars = Array(text)
        var i = 0
        while i < scalars.count {
            guard scalars[i].isASCII, scalars[i].isNumber else {
                words.append(scalars[i])
                i += 1
                continue
            }
            flushWords()
            var whole = ""
            while i < scalars.count, scalars[i].isASCII, scalars[i].isNumber { whole.append(scalars[i]); i += 1 }
            keys.append("n" + String(Int(whole) ?? 0))
            // "5,2" / "5.2" – a separator followed by a digit.
            if i + 1 < scalars.count, scalars[i] == "," || scalars[i] == ".", scalars[i + 1].isASCII, scalars[i + 1].isNumber {
                i += 1
                keys.append(textKey(tr("Komma", "point")))
                while i < scalars.count, scalars[i].isASCII, scalars[i].isNumber { keys.append("n" + String(scalars[i])); i += 1 }
            }
        }
        flushWords()
        return keys
    }

    static func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n.,:;!?–-\"„“"))
        return trimmed.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// "t" + FNV-1a 64 of the normalised text – stable across launches and identical in Python.
    static func textKey(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in normalize(text).utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return "t" + String(format: "%016llx", hash)
    }
}

extension FennVoice: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.current != nil else { return }
            self.next()
        }
    }
}

/// How cues say numbers out loud – the same words the recorded pieces use.
enum SpokenNumber {
    /// "5 Minuten 30", "1 Minute", "45 Sekunden".
    static func duration(_ seconds: Int) -> String {
        let minutes = seconds / 60, rest = seconds % 60
        if minutes == 0 { return tr("\(rest) Sekunden", "\(rest) seconds") }
        let unit = minutes == 1 ? tr("Minute", "minute") : tr("Minuten", "minutes")
        return rest == 0 ? "\(minutes) \(unit)" : "\(minutes) \(unit) \(rest)"
    }

    /// "400 Meter" (to 10 m below 220, else to 50 m), "1,2 Kilometer" from 1 km – numbers the recordings have.
    static func distance(_ meters: Double) -> String {
        if meters >= 1000 { return km(meters) + tr(" Kilometer", " kilometres") }
        let step = meters < 220 ? 10.0 : 50.0
        return tr("\(Int((meters / step).rounded() * step)) Meter", "\(Int((meters / step).rounded() * step)) metres")
    }

    /// "5,2" (German) / "5.2" – one decimal.
    static func km(_ meters: Double) -> String {
        let text = String(format: "%.1f", meters / 1000)
        return tr(text.replacingOccurrences(of: ".", with: ","), text)
    }
}
