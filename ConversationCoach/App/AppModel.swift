import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var sessions: [ConversationSession]
    @Published var selectedSessionID: ConversationSession.ID?
    @Published var recorderState: RecorderState = .idle
    @Published var modelAvailability: ModelAvailabilitySummary = .checking
    @Published var generationState: GenerationState = .idle

    private let audioCapture: AudioCaptureProviding
    private let transcription: TranscriptionProviding
    private let questionGenerator: QuestionGenerating

    init(
        audioCapture: AudioCaptureProviding = AudioCaptureService(),
        transcription: TranscriptionProviding = LocalTranscriptionPlaceholder(),
        questionGenerator: QuestionGenerating = FoundationQuestionGenerator()
    ) {
        let firstSession = ConversationSession.sample
        self.sessions = [firstSession]
        self.selectedSessionID = firstSession.id
        self.audioCapture = audioCapture
        self.transcription = transcription
        self.questionGenerator = questionGenerator

        Task {
            await refreshModelAvailability()
        }
    }

    var selectedSession: ConversationSession? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

    func createSession() {
        let session = ConversationSession(title: "New Conversation")
        sessions.insert(session, at: 0)
        selectedSessionID = session.id
    }

    func select(_ session: ConversationSession) {
        selectedSessionID = session.id
    }

    func toggleRecording() async {
        switch recorderState {
        case .idle, .failed:
            do {
                try await audioCapture.start()
                recorderState = .recording(startedAt: .now)
            } catch {
                recorderState = .failed(error.localizedDescription)
            }
        case .recording:
            await audioCapture.stop()
            recorderState = .idle
            appendTranscript(
                text: "Recording stopped. Live transcription will be connected in the next milestone.",
                source: .system
            )
        }
    }

    func importAudio(from url: URL) async {
        do {
            let transcriptText = try await transcription.transcribeAudioFile(at: url)
            appendTranscript(text: transcriptText, source: .importedAudio(url.lastPathComponent))
        } catch {
            appendTranscript(text: "Audio import failed: \(error.localizedDescription)", source: .system)
        }
    }

    func refreshModelAvailability() async {
        modelAvailability = await questionGenerator.availability()
    }

    func generateQuestions() async {
        guard let session = selectedSession else { return }

        let transcript = session.transcriptText
        guard transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            generationState = .failed("A transcript is needed before questions can be generated.")
            return
        }

        generationState = .generating

        do {
            let questions = try await questionGenerator.generateQuestions(from: transcript)
            updateSelectedSession { selected in
                selected.questionSet = questions
                selected.updatedAt = .now
            }
            generationState = .idle
        } catch {
            generationState = .failed(error.localizedDescription)
        }
    }

    private func appendTranscript(text: String, source: TranscriptSource) {
        updateSelectedSession { selected in
            selected.segments.append(TranscriptSegment(text: text, source: source))
            selected.updatedAt = .now
        }
    }

    private func updateSelectedSession(_ update: (inout ConversationSession) -> Void) {
        guard let selectedSessionID,
              let index = sessions.firstIndex(where: { $0.id == selectedSessionID })
        else {
            return
        }

        update(&sessions[index])
    }
}

enum RecorderState: Equatable {
    case idle
    case recording(startedAt: Date)
    case failed(String)

    var label: String {
        switch self {
        case .idle:
            "Ready"
        case .recording:
            "Recording"
        case .failed:
            "Needs attention"
        }
    }
}

enum GenerationState: Equatable {
    case idle
    case generating
    case failed(String)
}
