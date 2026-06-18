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

    func generateQuestions(from transcript: String, topic: ConversationTopic) async throws -> QuestionSet {
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
            Tune the questions to the selected conversation topic.
            Avoid giving advice as if you are a party to the conversation.
            Never return placeholder text.
            """
        )

        let response = try await session.respond(
            to: Self.prompt(for: transcript, topic: topic),
            options: GenerationOptions(
                sampling: .greedy,
                temperature: 0.2,
                maximumResponseTokens: 520
            )
        )

        return Self.questionSet(from: response.content, transcript: transcript, topic: topic)
        #else
        throw QuestionGenerationError.modelUnavailable("Apple Foundation Models are not present in this SDK.")
        #endif
    }

    private static func prompt(for transcript: String, topic: ConversationTopic) -> String {
        """
        Read the transcript inside the delimiters and write questions a participant could ask next.

        Conversation topic: \(topic.rawValue)
        Topic focus: \(topic.promptFocus)

        <<<TRANSCRIPT
        \(transcript)
        TRANSCRIPT>>>

        Output only two sections named FOR and AGAINST.
        Under each section, write two bullet points.
        Each bullet must contain one concrete question based on the transcript, then a vertical bar, then a short reason the question is useful.
        The question text must not be generic and must not contain the words "Question", "placeholder", or "Why this helps".
        """
    }

    private static func questionSet(
        from content: String,
        transcript: String,
        topic: ConversationTopic
    ) -> QuestionSet {
        let parsed = parse(content)
        let fallback = fallbackQuestionSet(from: transcript, topic: topic)

        return QuestionSet(
            supportive: fill(parsed.supportive, with: fallback.supportive, targetCount: 2),
            challenging: fill(parsed.challenging, with: fallback.challenging, targetCount: 2)
        )
    }

    private static func parse(_ content: String) -> QuestionSet {
        var supportive: [ConversationQuestion] = []
        var challenging: [ConversationQuestion] = []
        var section: Section?

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.isEmpty == false else { continue }

            let sectionLabel = line
                .uppercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: ":"))

            if sectionLabel == "FOR" || sectionLabel.hasPrefix("SUPPORT") {
                section = .supportive
                continue
            }

            if sectionLabel == "AGAINST" || sectionLabel.hasPrefix("CHALLENGE") {
                section = .challenging
                continue
            }

            guard let section else { continue }

            let cleaned = bulletText(from: line)
            guard cleaned.isEmpty == false else { continue }

            let parts = splitQuestionAndRationale(cleaned)
            let questionText = parts.question.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isUsableQuestion(questionText) else { continue }

            let question = ConversationQuestion(
                text: questionText,
                rationale: parts.rationale.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            switch section {
            case .supportive:
                supportive.append(question)
            case .challenging:
                challenging.append(question)
            }
        }

        return QuestionSet(supportive: supportive, challenging: challenging)
    }

    private static func bulletText(from line: String) -> String {
        var cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if let first = cleaned.first, ["-", "*"].contains(first) {
            cleaned = String(cleaned.dropFirst())
        } else if let range = cleaned.range(
            of: #"^\d+[\.\)]\s+"#,
            options: .regularExpression
        ) {
            cleaned.removeSubrange(range)
        } else {
            return ""
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitQuestionAndRationale(_ text: String) -> (question: String, rationale: String) {
        let separators = ["|", " -- ", " - "]

        for separator in separators {
            let parts = text.components(separatedBy: separator)
            guard parts.count > 1 else { continue }

            return (
                parts[0].trimmingCharacters(in: .whitespacesAndNewlines),
                parts.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return (text, "")
    }

    private static func isUsableQuestion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        guard trimmed.count >= 12 else { return false }
        guard trimmed.contains("?") else { return false }

        let blockedFragments = [
            "question?",
            "why this helps",
            "<question",
            "<rationale",
            "placeholder",
            "insert",
            "your question"
        ]

        return blockedFragments.contains { lowercased.contains($0) } == false
    }

    private static func fill(
        _ generated: [ConversationQuestion],
        with fallback: [ConversationQuestion],
        targetCount: Int = 3
    ) -> [ConversationQuestion] {
        var result = generated

        for question in fallback where result.count < targetCount {
            let isDuplicate = result.contains {
                $0.text.caseInsensitiveCompare(question.text) == .orderedSame
            }

            if isDuplicate == false {
                result.append(question)
            }
        }

        return Array(result.prefix(targetCount))
    }

    private static func fallbackQuestionSet(from transcript: String, topic: ConversationTopic) -> QuestionSet {
        let topics = salientTerms(from: transcript)
        let primary = topics.first ?? "the main point"
        let secondary = topics.dropFirst().first ?? "the next decision"

        return QuestionSet(
            supportive: [
                ConversationQuestion(
                    text: "What evidence in this \(topic.rawValue.lowercased()) conversation most strongly supports the point about \(primary)?",
                    rationale: "This asks the group to anchor the discussion in what has already been said."
                ),
                ConversationQuestion(
                    text: "What would make the \(topic.rawValue.lowercased()) idea about \(secondary) clearer or easier to act on?",
                    rationale: "This pushes for a concrete next step instead of staying abstract."
                )
            ],
            challenging: [
                ConversationQuestion(
                    text: "What evidence would change our mind about \(primary) in this \(topic.rawValue.lowercased()) context?",
                    rationale: "This tests whether the current view is open to revision."
                ),
                ConversationQuestion(
                    text: "What important \(topic.rawValue.lowercased()) cost, constraint, or tradeoff has not been discussed yet?",
                    rationale: "This surfaces risks that may be missing from the current framing."
                )
            ]
        )
    }

    private static func salientTerms(from transcript: String) -> [String] {
        let stopWords: Set<String> = [
            "about", "after", "again", "also", "because", "before", "being", "could",
            "conversation", "does", "going", "have", "here", "into", "just", "like",
            "more", "need", "only", "really", "should", "some", "that", "their",
            "there", "these", "thing", "think", "this", "those", "through", "want",
            "were", "what", "when", "where", "which", "with", "would", "your"
        ]

        let words = transcript
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 && stopWords.contains($0) == false }

        let counts = Dictionary(words.map { ($0, 1) }, uniquingKeysWith: +)

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    lhs.key < rhs.key
                } else {
                    lhs.value > rhs.value
                }
            }
            .prefix(2)
            .map(\.key)
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
