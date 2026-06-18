import Foundation

enum ConversationTopic: String, CaseIterable, Identifiable, Sendable {
    case general = "General"
    case strategy = "Strategy"
    case product = "Product"
    case technical = "Technical"
    case legal = "Legal"
    case financial = "Financial"
    case negotiation = "Negotiation"
    case interview = "Interview"
    case research = "Research"

    var id: String { rawValue }

    var promptFocus: String {
        switch self {
        case .general:
            "general reasoning, assumptions, evidence, and next useful questions"
        case .strategy:
            "strategic tradeoffs, goals, constraints, second-order effects, and decision quality"
        case .product:
            "user needs, product scope, adoption risks, usability, positioning, and prioritization"
        case .technical:
            "implementation details, architecture, reliability, constraints, dependencies, and failure modes"
        case .legal:
            "legal reasoning, risks, obligations, definitions, evidence, and opposing interpretations"
        case .financial:
            "financial assumptions, incentives, costs, risks, returns, and measurable outcomes"
        case .negotiation:
            "interests, leverage, concessions, alternatives, incentives, and hidden constraints"
        case .interview:
            "candidate signal, follow-up probes, examples, ambiguity, and evidence for claims"
        case .research:
            "hypotheses, evidence quality, counterexamples, methodology, and missing data"
        }
    }
}

