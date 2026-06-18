import Foundation

@MainActor
protocol TranscriptionProviding: AnyObject {
    func transcribeAudioFile(at url: URL) async throws -> String
    func startLiveTranscription(updateHandler: @escaping @MainActor (LiveTranscriptionUpdate) -> Void) async throws
    func stopLiveTranscription() async -> String?
}

struct LiveTranscriptionUpdate: Equatable {
    var text: String
    var isFinal: Bool
}
