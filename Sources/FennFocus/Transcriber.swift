import AVFoundation
import Speech

enum SpeechPermission {
    /// Speech recognition always; microphone only when recording live.
    static func request(microphone: Bool) async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return microphone ? await AVCaptureDevice.requestAccess(for: .audio) : true
    }
}

enum TranscriberError: LocalizedError {
    case notAllowed
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notAllowed:
            return tr("Spracherkennung nicht erlaubt – Systemeinstellungen › Datenschutz & Sicherheit.",
                      "Speech recognition not allowed – System Settings › Privacy & Security.")
        case .unavailable:
            return tr("Spracherkennung ist gerade nicht verfügbar.", "Speech recognition is unavailable right now.")
        }
    }
}

/// Transcribes an audio file (voice memo, meeting recording) — on-device when the Mac supports it.
enum Transcriber {
    static func transcribe(_ url: URL) async throws -> String {
        guard await SpeechPermission.request(microphone: false) else { throw TranscriberError.notAllowed }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: tr("de-DE", "en-US"))),
              recognizer.isAvailable else { throw TranscriberError.unavailable }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        final class Once: @unchecked Sendable {
            var done = false
            var task: SFSpeechRecognitionTask?
        }
        let once = Once()
        return try await withCheckedThrowingContinuation { continuation in
            once.task = recognizer.recognitionTask(with: request) { result, error in
                guard !once.done else { return }
                if let error {
                    once.done = true
                    continuation.resume(throwing: error)
                } else if let result, result.isFinal {
                    once.done = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}
