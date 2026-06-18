import Foundation

struct TranscriptSegment: Identifiable, Hashable {
    let id: UUID
    var text: String
    var source: TranscriptSource
    var createdAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        source: TranscriptSource,
        createdAt: Date = .now
    ) {
        self.id = id
        self.text = text
        self.source = source
        self.createdAt = createdAt
    }
}

enum TranscriptSource: Hashable {
    case speaker(String)
    case importedAudio(String)
    case system

    var label: String {
        switch self {
        case let .speaker(name):
            name
        case let .importedAudio(fileName):
            fileName
        case .system:
            "System"
        }
    }
}

