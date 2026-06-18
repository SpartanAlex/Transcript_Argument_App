import Foundation

struct ConversationSession: Identifiable, Hashable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var segments: [TranscriptSegment]
    var questionSet: QuestionSet?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        segments: [TranscriptSegment] = [],
        questionSet: QuestionSet? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.segments = segments
        self.questionSet = questionSet
    }

    var transcriptText: String {
        segments
            .map { "[\($0.source.label)] \($0.text)" }
            .joined(separator: "\n")
    }
}

extension ConversationSession {
    static let sample = ConversationSession(
        title: "Prototype Session",
        segments: [
            TranscriptSegment(
                text: "This sample transcript is here so the local question generator has something to work with on first launch.",
                source: .system
            ),
            TranscriptSegment(
                text: "We are exploring whether a local iPad app can listen, transcribe, and suggest stronger questions during a live discussion.",
                source: .speaker("Speaker 1")
            )
        ]
    )
}

