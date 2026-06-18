import Foundation

struct LocalTranscriptionPlaceholder: TranscriptionProviding {
    func transcribeAudioFile(at url: URL) async throws -> String {
        "Imported \(url.lastPathComponent). On-device transcription will be connected in the next milestone."
    }
}

