import AVFAudio
import Foundation
import Speech

@MainActor
final class LocalSpeechTranscriptionService: NSObject, TranscriptionProviding {
    private let locale: Locale
    private let audioEngine = AVAudioEngine()

    private var liveRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var liveRecognitionTask: SFSpeechRecognitionTask?
    private var latestLiveTranscript = ""

    init(locale: Locale = .current) {
        self.locale = locale
        super.init()
    }

    func transcribeAudioFile(at url: URL) async throws -> String {
        try await requestSpeechAuthorization()
        let recognizer = try makeOnDeviceRecognizer()

        let didAccessSecurityScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        configure(request)

        return try await withCheckedThrowingContinuation { continuation in
            var latestText = ""
            var didResume = false

            func resumeOnce(_ result: Result<String, Error>) {
                guard didResume == false else { return }
                didResume = true
                continuation.resume(with: result)
            }

            recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    latestText = result.bestTranscription.formattedString

                    if result.isFinal {
                        let finalText = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if finalText.isEmpty {
                            resumeOnce(.failure(TranscriptionError.noSpeechRecognized))
                        } else {
                            resumeOnce(.success(finalText))
                        }
                    }
                }

                if let error {
                    resumeOnce(.failure(error))
                }
            }
        }
    }

    func startLiveTranscription(updateHandler: @escaping @MainActor (LiveTranscriptionUpdate) -> Void) async throws {
        try await requestSpeechAuthorization()
        let microphoneAccessGranted = await requestMicrophoneAccess()
        guard microphoneAccessGranted else {
            throw TranscriptionError.microphonePermissionDenied
        }

        let recognizer = try makeOnDeviceRecognizer()
        stopLiveRecognition(cancelTask: true)

        latestLiveTranscript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        configure(request)
        liveRecognitionRequest = request

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw TranscriptionError.microphoneFormatUnavailable
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        liveRecognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    self.latestLiveTranscript = text
                    updateHandler(LiveTranscriptionUpdate(text: text, isFinal: result.isFinal))
                }

                if error != nil {
                    self.stopLiveRecognition(cancelTask: false)
                }
            }
        }
    }

    func stopLiveTranscription() async -> String? {
        let finalText = latestLiveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopLiveRecognition(cancelTask: false)
        return finalText.isEmpty ? nil : finalText
    }

    private func stopLiveRecognition(cancelTask: Bool) {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }

        liveRecognitionRequest?.endAudio()
        liveRecognitionRequest = nil

        if cancelTask {
            liveRecognitionTask?.cancel()
        } else {
            liveRecognitionTask?.finish()
        }

        liveRecognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func configure(_ request: SFSpeechRecognitionRequest) {
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = [
            "argument",
            "assumption",
            "evidence",
            "counterargument",
            "question"
        ]
    }

    private func makeOnDeviceRecognizer() throws -> SFSpeechRecognizer {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw TranscriptionError.recognizerUnavailable(locale.identifier)
        }

        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.onDeviceRecognitionUnavailable(locale.identifier)
        }

        guard recognizer.isAvailable else {
            throw TranscriptionError.recognizerTemporarilyUnavailable
        }

        return recognizer
    }

    private func requestSpeechAuthorization() async throws {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return
        case .notDetermined:
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }

            guard status == .authorized else {
                throw TranscriptionError.speechPermissionDenied
            }
        case .denied:
            throw TranscriptionError.speechPermissionDenied
        case .restricted:
            throw TranscriptionError.speechPermissionRestricted
        @unknown default:
            throw TranscriptionError.speechPermissionDenied
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

enum TranscriptionError: LocalizedError {
    case speechPermissionDenied
    case speechPermissionRestricted
    case microphonePermissionDenied
    case recognizerUnavailable(String)
    case recognizerTemporarilyUnavailable
    case onDeviceRecognitionUnavailable(String)
    case noSpeechRecognized
    case microphoneFormatUnavailable

    var errorDescription: String? {
        switch self {
        case .speechPermissionDenied:
            "Speech recognition permission is required for local transcription."
        case .speechPermissionRestricted:
            "Speech recognition is restricted on this device."
        case .microphonePermissionDenied:
            "Microphone access is required to record a conversation."
        case let .recognizerUnavailable(locale):
            "Speech recognition is not available for \(locale)."
        case .recognizerTemporarilyUnavailable:
            "Speech recognition is temporarily unavailable on this device."
        case let .onDeviceRecognitionUnavailable(locale):
            "On-device speech recognition is not available for \(locale)."
        case .noSpeechRecognized:
            "No speech was recognized in that audio."
        case .microphoneFormatUnavailable:
            "The microphone did not provide a valid audio format."
        }
    }
}
