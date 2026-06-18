# Architecture

Conversation Coach is split around four boundaries so the prototype can evolve without rewiring the app.

## App State

`AppModel` owns the current in-memory session list, selected session, recording state, Foundation Models availability, and question generation state.

This is intentionally simple for the first milestone. SwiftData persistence should replace the in-memory store once the transcript and question shapes settle.

## Audio Capture

`AudioCaptureProviding` is the seam for microphone recording.

The first implementation, `AudioCaptureService`, requests microphone access, starts an `AVAudioEngine`, and installs an input tap. The tap is ready to feed audio buffers into the transcription layer in the next milestone.

## Transcription

`TranscriptionProviding` is the seam for audio-file and eventually live transcription.

The current implementation is a placeholder so the app can already exercise Voice Memos/File import paths without committing prematurely to one transcription API.

The next implementation should prefer Apple-native on-device transcription. If that is not accurate or responsive enough for live conversation, we can revisit the transcription layer while keeping Apple Foundation Models as the question engine.

## Question Generation

`QuestionGenerating` is the seam for local AI.

`FoundationQuestionGenerator` uses Apple Foundation Models through `SystemLanguageModel.default` and checks `availability` before creating a `LanguageModelSession`. If the model is not available on device, generation fails visibly rather than falling back to a cloud provider.

The first response format is plain text with a strict parser. Once the end-to-end workflow is stable, this can move to structured generation using Foundation Models schemas.

## Product Flow

1. Create or select a session.
2. Record or import audio.
3. Append transcript segments to the session.
4. Generate "For" and "Against" questions from the accumulated transcript.
5. Persist the session locally.

