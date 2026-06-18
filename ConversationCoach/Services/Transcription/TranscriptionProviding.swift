import Foundation

protocol TranscriptionProviding: AnyObject, Sendable {
    func transcribeAudioFile(at url: URL) async throws -> String
    func startLiveTranscription(updateHandler: @escaping @Sendable (LiveTranscriptionUpdate) -> Void) async throws
    func stopLiveTranscription() async -> String?
}

struct LiveTranscriptionUpdate: Equatable, Sendable {
    var text: String
    var isFinal: Bool
}
