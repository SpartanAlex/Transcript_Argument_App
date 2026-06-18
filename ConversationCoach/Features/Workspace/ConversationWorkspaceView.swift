import SwiftUI
import UniformTypeIdentifiers

struct ConversationWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel
    let session: ConversationSession

    @State private var isImportingAudio = false

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader
                .padding(.horizontal, 24)
                .padding(.vertical, 18)

            Divider()

            GeometryReader { proxy in
                let isWide = proxy.size.width > 820

                Group {
                    if isWide {
                        HStack(spacing: 0) {
                            transcriptPanel
                                .frame(maxWidth: .infinity)

                            Divider()

                            questionsPanel
                                .frame(width: min(390, proxy.size.width * 0.38))
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: 18) {
                                transcriptPanel
                                questionsPanel
                            }
                            .padding(.vertical, 18)
                        }
                    }
                }
            }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isImportingAudio = true
                } label: {
                    Label("Import Audio", systemImage: "square.and.arrow.down")
                }

                Button {
                    Task { await appModel.generateQuestions() }
                } label: {
                    Label("Generate Questions", systemImage: "sparkles")
                }
                .disabled(appModel.generationState == .generating)
            }
        }
        .fileImporter(
            isPresented: $isImportingAudio,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result,
                  let url = urls.first
            else {
                return
            }

            Task { await appModel.importAudio(from: url) }
        }
    }

    private var workspaceHeader: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(session.title)
                    .font(.title2.weight(.semibold))

                HStack(spacing: 10) {
                    StatusPill(
                        label: appModel.recorderState.label,
                        systemImage: recorderIcon,
                        tint: recorderTint
                    )

                    StatusPill(
                        label: appModel.modelAvailability.shortLabel,
                        systemImage: appModel.modelAvailability.systemImage,
                        tint: appModel.modelAvailability.tint
                    )
                }
            }

            Spacer()

            Button {
                Task { await appModel.toggleRecording() }
            } label: {
                Label(recordButtonTitle, systemImage: recordButtonIcon)
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(recordButtonTint)
            .accessibilityLabel(recordButtonTitle)
        }
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelHeader(title: "Transcript", systemImage: "quote.bubble")

            if session.segments.isEmpty {
                ContentUnavailableView(
                    "No Transcript",
                    systemImage: "waveform",
                    description: Text("Start recording or import audio.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(session.segments) { segment in
                            TranscriptSegmentRow(segment: segment)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .padding(24)
    }

    private var questionsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelHeader(title: "Questions", systemImage: "questionmark.bubble")

            switch appModel.generationState {
            case .generating:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView(
                    "Questions Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            case .idle:
                if let questionSet = session.questionSet {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            QuestionSection(title: "For", tint: .green, questions: questionSet.supportive)
                            QuestionSection(title: "Against", tint: .red, questions: questionSet.challenging)
                        }
                        .padding(.bottom, 24)
                    }
                } else {
                    ContentUnavailableView(
                        "No Questions",
                        systemImage: "sparkles",
                        description: Text("Generate questions from the current transcript.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(24)
        .background(Color(.secondarySystemBackground))
    }

    private var recorderIcon: String {
        switch appModel.recorderState {
        case .idle:
            "mic"
        case .recording:
            "record.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    private var recorderTint: Color {
        switch appModel.recorderState {
        case .idle:
            .secondary
        case .recording:
            .red
        case .failed:
            .orange
        }
    }

    private var recordButtonTitle: String {
        switch appModel.recorderState {
        case .recording:
            "Stop Recording"
        default:
            "Start Recording"
        }
    }

    private var recordButtonIcon: String {
        switch appModel.recorderState {
        case .recording:
            "stop.fill"
        default:
            "mic.fill"
        }
    }

    private var recordButtonTint: Color {
        switch appModel.recorderState {
        case .recording:
            .red
        default:
            .blue
        }
    }
}

private struct PanelHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

private struct StatusPill: View {
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(segment.source.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(segment.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(segment.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct QuestionSection: View {
    let title: String
    let tint: Color
    let questions: [ConversationQuestion]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(tint)

            ForEach(questions) { question in
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.text)
                        .font(.body.weight(.medium))
                        .textSelection(.enabled)

                    if question.rationale.isEmpty == false {
                        Text(question.rationale)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
