import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct FoundationQuestionGenerator: QuestionGenerating {
    func availability() async -> ModelAvailabilitySummary {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            return .unavailable("Apple Foundation Models require iOS 26 or newer.")
        }

        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case let .unavailable(reason):
            return .unavailable(Self.message(for: reason))
        }
        #else
        return .unavailable("Apple Foundation Models are not present in this SDK.")
        #endif
    }

    func generateQuestions(from transcript: String) async throws -> QuestionSet {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            throw QuestionGenerationError.modelUnavailable("Apple Foundation Models require iOS 26 or newer.")
        }

        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw QuestionGenerationError.modelUnavailable(await availability().shortLabel)
        }

        let session = LanguageModelSession(
            model: model,
            instructions: """
            You help a thoughtful participant prepare better questions during a live conversation.
            Use only the provided transcript.
            Produce concise, specific questions.
            Separate questions that strengthen or clarify the current line of thought from questions that challenge assumptions, risks, or missing evidence.
            Avoid giving advice as if you are a party to the conversation.
            """
        )

        let prompt = """
        Transcript:
        \(transcript)

        Return exactly this plain text format:
        FOR:
        - Question? | Why this helps.
        - Question? | Why this helps.
        - Question? | Why this helps.

        AGAINST:
        - Question? | Why this helps.
        - Question? | Why this helps.
        - Question? | Why this helps.
        """

        let response = try await session.respond(
            to: prompt,
            options: GenerationOptions(
                sampling: .greedy,
                temperature: 0.2,
                maximumResponseTokens: 700
            )
        )

        return try Self.parse(response.content)
        #else
        throw QuestionGenerationError.modelUnavailable("Apple Foundation Models are not present in this SDK.")
        #endif
    }

    private static func parse(_ content: String) throws -> QuestionSet {
        var supportive: [ConversationQuestion] = []
        var challenging: [ConversationQuestion] = []
        var section: Section?

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.isEmpty == false else { continue }

            if line.uppercased().hasPrefix("FOR:") {
                section = .supportive
                continue
            }

            if line.uppercased().hasPrefix("AGAINST:") {
                section = .challenging
                continue
            }

            guard line.hasPrefix("-"), let section else { continue }

            let cleaned = line
                .dropFirst()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = cleaned
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            let question = ConversationQuestion(
                text: parts.first ?? cleaned,
                rationale: parts.dropFirst().first ?? ""
            )

            switch section {
            case .supportive:
                supportive.append(question)
            case .challenging:
                challenging.append(question)
            }
        }

        guard supportive.isEmpty == false || challenging.isEmpty == false else {
            throw QuestionGenerationError.emptyResponse
        }

        return QuestionSet(supportive: supportive, challenging: challenging)
    }

    private enum Section {
        case supportive
        case challenging
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func message(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            "This device does not support Apple Foundation Models on device."
        case .appleIntelligenceNotEnabled:
            "Apple Intelligence is not enabled on this device."
        case .modelNotReady:
            "The on-device Apple Foundation Model is not ready yet."
        @unknown default:
            "The on-device Apple Foundation Model is unavailable."
        }
    }
    #endif
}

