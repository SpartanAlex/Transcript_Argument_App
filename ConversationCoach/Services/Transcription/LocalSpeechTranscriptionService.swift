import AVFAudio
import Foundation
@preconcurrency import Speech

final class LocalSpeechTranscriptionService: TranscriptionProviding, @unchecked Sendable {
    private let locale: Locale
    private let audioEngine = AVAudioEngine()
    private let lock = NSLock()
    private let recognitionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "ConversationCoach.SpeechRecognition"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private var liveRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var liveRecognitionTask: SFSpeechRecognitionTask?
    private var liveRecognizer: SFSpeechRecognizer?
    private var latestLiveTranscript = ""

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func transcribeAudioFile(at url: URL) async throws -> String {
        try await requestSpeechAuthorization()

        let temporaryFile = try Self.temporaryLocalCopy(of: url)
        defer {
            temporaryFile.cleanup()
        }

        if #available(iOS 26.0, *), SpeechTranscriber.isAvailable {
            do {
                return try await transcribeAudioFileWithAnalyzer(at: temporaryFile.url)
            } catch {
                // Fall back to the legacy recognizer path; some locales may not have SpeechAnalyzer assets installed yet.
            }
        }

        return try await transcribeAudioFileWithLegacyRecognizer(at: temporaryFile.url)
    }

    private func transcribeAudioFileWithLegacyRecognizer(at url: URL) async throws -> String {
        let recognizer = try makeOnDeviceRecognizer()
        recognizer.queue = recognitionQueue

        let request = SFSpeechAudioBufferRecognitionRequest()
        configure(request)

        return try await withCheckedThrowingContinuation { continuation in
            var latestText = ""
            var didResume = false
            let resumeLock = NSLock()
            var recognitionTask: SFSpeechRecognitionTask?

            func resumeOnce(_ result: Result<String, Error>) {
                resumeLock.lock()
                defer { resumeLock.unlock() }

                guard didResume == false else { return }
                didResume = true
                if case .failure = result {
                    recognitionTask?.cancel()
                }
                continuation.resume(with: result)
            }

            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
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

            let appendTarget = SpeechBufferAppendTarget(request)

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Self.appendAudioFile(at: url, to: appendTarget.request)
                } catch {
                    resumeOnce(.failure(error))
                }
            }
        }
    }

    @available(iOS 26.0, *)
    private func transcribeAudioFileWithAnalyzer(at url: URL) async throws -> String {
        let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) ?? locale
        let transcriber = SpeechTranscriber(
            locale: supportedLocale,
            preset: .timeIndexedTranscriptionWithAlternatives
        )
        let audioFile = try AVAudioFile(forReading: url)
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: SpeechAnalyzer.Options(
                priority: .userInitiated,
                modelRetention: .whileInUse
            )
        )

        let resultTask = Task {
            var finalized: [String] = []
            var latestVolatile = ""

            for try await result in transcriber.results {
                let text = String(result.text.characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.isEmpty == false else { continue }

                if result.isFinal {
                    finalized.append(text)
                } else {
                    latestVolatile = text
                }
            }

            return (finalized + [latestVolatile])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
                .joined(separator: " ")
        }

        do {
            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
            let text = try await resultTask.value
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard text.isEmpty == false else {
                throw TranscriptionError.noSpeechRecognized
            }

            return text
        } catch {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    func startLiveTranscription(updateHandler: @escaping @Sendable (LiveTranscriptionUpdate) -> Void) async throws {
        try await requestSpeechAuthorization()
        let microphoneAccessGranted = await requestMicrophoneAccess()
        guard microphoneAccessGranted else {
            throw TranscriptionError.microphonePermissionDenied
        }

        let recognizer = try makeOnDeviceRecognizer()
        recognizer.queue = recognitionQueue
        stopLiveRecognition(action: .cancel)

        setLatestLiveTranscript("")

        let request = SFSpeechAudioBufferRecognitionRequest()
        configure(request)
        setLiveRecognition(request: request, task: nil, recognizer: recognizer)

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

        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                self.setLatestLiveTranscript(text)
                updateHandler(LiveTranscriptionUpdate(text: text, isFinal: result.isFinal))
            }

            if error != nil {
                self.stopLiveRecognition(action: .none)
            }
        }

        setLiveRecognition(request: request, task: task, recognizer: recognizer)
    }

    func stopLiveTranscription() async -> String? {
        let finalText = currentLatestLiveTranscript().trimmingCharacters(in: .whitespacesAndNewlines)
        stopLiveRecognition(action: .finish)
        return finalText.isEmpty ? nil : finalText
    }

    private func stopLiveRecognition(action: RecognitionStopAction) {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }

        let state = clearLiveRecognition()

        switch action {
        case .cancel:
            state.request?.endAudio()
            state.task?.cancel()
        case .finish:
            state.request?.endAudio()
            state.task?.finish()
        case .none:
            break
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func setLiveRecognition(
        request: SFSpeechAudioBufferRecognitionRequest?,
        task: SFSpeechRecognitionTask?,
        recognizer: SFSpeechRecognizer?
    ) {
        lock.lock()
        liveRecognitionRequest = request
        liveRecognitionTask = task
        liveRecognizer = recognizer
        lock.unlock()
    }

    private func clearLiveRecognition() -> LiveRecognitionState {
        lock.lock()
        let state = LiveRecognitionState(
            request: liveRecognitionRequest,
            task: liveRecognitionTask,
            recognizer: liveRecognizer
        )
        liveRecognitionRequest = nil
        liveRecognitionTask = nil
        liveRecognizer = nil
        lock.unlock()
        return state
    }

    private func setLatestLiveTranscript(_ text: String) {
        lock.lock()
        latestLiveTranscript = text
        lock.unlock()
    }

    private func currentLatestLiveTranscript() -> String {
        lock.lock()
        let text = latestLiveTranscript
        lock.unlock()
        return text
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

    private static func appendAudioFile(
        at url: URL,
        to request: SFSpeechAudioBufferRecognitionRequest
    ) throws {
        defer {
            request.endAudio()
        }

        let audioFile = try AVAudioFile(forReading: url)
        let inputFormat = audioFile.processingFormat
        let outputFormat = request.nativeAudioFormat

        guard inputFormat.sampleRate > 0,
              inputFormat.channelCount > 0,
              outputFormat.sampleRate > 0,
              outputFormat.channelCount > 0
        else {
            throw TranscriptionError.audioFileFormatUnavailable
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw TranscriptionError.audioFileFormatUnavailable
        }

        let inputCapacity: AVAudioFrameCount = 4096

        while audioFile.framePosition < audioFile.length {
            let framesRemaining = audioFile.length - audioFile.framePosition
            let inputFrameCount = AVAudioFrameCount(min(Int64(inputCapacity), framesRemaining))

            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                frameCapacity: inputFrameCount
            ) else {
                throw TranscriptionError.audioFileFormatUnavailable
            }

            try audioFile.read(into: inputBuffer, frameCount: inputFrameCount)

            if inputBuffer.frameLength > 0 {
                try appendConvertedBuffer(
                    inputBuffer,
                    outputFormat: outputFormat,
                    converter: converter,
                    to: request
                )
            }
        }
    }

    private static func appendConvertedBuffer(
        _ inputBuffer: AVAudioPCMBuffer,
        outputFormat: AVAudioFormat,
        converter: AVAudioConverter,
        to request: SFSpeechAudioBufferRecognitionRequest
    ) throws {
        let sampleRateRatio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let outputCapacity = max(
            AVAudioFrameCount(Double(inputBuffer.frameLength) * sampleRateRatio) + 512,
            512
        )

        var inputWasProvided = false
        var isDone = false

        repeat {
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputCapacity
            ) else {
                throw TranscriptionError.audioFileFormatUnavailable
            }

            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                if inputWasProvided {
                    outStatus.pointee = .noDataNow
                    return nil
                }

                inputWasProvided = true
                outStatus.pointee = .haveData
                return inputBuffer
            }

            if let conversionError {
                throw conversionError
            }

            if outputBuffer.frameLength > 0 {
                request.append(outputBuffer)
            }

            switch status {
            case .haveData:
                isDone = false
            case .inputRanDry, .endOfStream:
                isDone = true
            case .error:
                throw TranscriptionError.audioFileFormatUnavailable
            @unknown default:
                isDone = true
            }
        } while isDone == false
    }

    private static func temporaryLocalCopy(of url: URL) throws -> TemporaryAudioFile {
        let didAccessSecurityScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileName = url.lastPathComponent.isEmpty ? "ImportedAudio.m4a" : url.lastPathComponent
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(fileName)")

        var coordinatorError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readableURL in
            do {
                if FileManager.default.fileExists(atPath: temporaryURL.path) {
                    try FileManager.default.removeItem(at: temporaryURL)
                }

                try FileManager.default.copyItem(at: readableURL, to: temporaryURL)
            } catch {
                copyError = error
            }
        }

        if let coordinatorError {
            throw coordinatorError
        }

        if let copyError {
            throw copyError
        }

        return TemporaryAudioFile(url: temporaryURL)
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

private enum RecognitionStopAction {
    case cancel
    case finish
    case none
}

private struct LiveRecognitionState {
    var request: SFSpeechAudioBufferRecognitionRequest?
    var task: SFSpeechRecognitionTask?
    var recognizer: SFSpeechRecognizer?
}

private final class SpeechBufferAppendTarget: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest

    init(_ request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }
}

private struct TemporaryAudioFile {
    let url: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
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
    case audioFileFormatUnavailable

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
        case .audioFileFormatUnavailable:
            "That audio file could not be decoded into a local speech-recognition format."
        }
    }
}
