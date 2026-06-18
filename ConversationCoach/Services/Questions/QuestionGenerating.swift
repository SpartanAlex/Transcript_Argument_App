import Foundation
import SwiftUI

protocol QuestionGenerating: Sendable {
    func availability() async -> ModelAvailabilitySummary
    func generateQuestions(from transcript: String, topic: ConversationTopic) async throws -> QuestionSet
}

enum ModelAvailabilitySummary: Equatable {
    case checking
    case available
    case unavailable(String)

    var shortLabel: String {
        switch self {
        case .checking:
            "Checking AI"
        case .available:
            "Local AI Ready"
        case .unavailable:
            "Local AI Off"
        }
    }

    var systemImage: String {
        switch self {
        case .checking:
            "clock"
        case .available:
            "checkmark.seal"
        case .unavailable:
            "xmark.seal"
        }
    }

    var tint: Color {
        switch self {
        case .checking:
            .secondary
        case .available:
            .green
        case .unavailable:
            .orange
        }
    }
}

enum QuestionGenerationError: LocalizedError {
    case modelUnavailable(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case let .modelUnavailable(reason):
            reason
        case .emptyResponse:
            "The local model did not return questions."
        }
    }
}
