import AVFAudio
import Foundation

actor AudioCaptureService: AudioCaptureProviding {
    private let engine = AVAudioEngine()

    func start() async throws {
        let granted = await requestMicrophoneAccess()
        guard granted else {
            throw AudioCaptureError.microphonePermissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { _, _ in
            // Audio buffers will feed the transcription service in the next milestone.
        }

        engine.prepare()
        try engine.start()
    }

    func stop() async {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

enum AudioCaptureError: LocalizedError {
    case microphonePermissionDenied

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Microphone access is required to record a conversation."
        }
    }
}

