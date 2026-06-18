import Foundation

protocol TranscriptionProviding: Sendable {
    func transcribeAudioFile(at url: URL) async throws -> String
}

