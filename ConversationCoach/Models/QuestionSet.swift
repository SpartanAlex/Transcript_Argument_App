import Foundation

struct QuestionSet: Hashable {
    var supportive: [ConversationQuestion]
    var challenging: [ConversationQuestion]
}

struct ConversationQuestion: Identifiable, Hashable {
    let id: UUID
    var text: String
    var rationale: String

    init(id: UUID = UUID(), text: String, rationale: String = "") {
        self.id = id
        self.text = text
        self.rationale = rationale
    }
}

