# Architecture

Conversation Coach is split around four boundaries so the prototype can evolve without rewiring the app.

## App State

`AppModel` owns the current in-memory session list, selected session, recording state, Foundation Models availability, and question generation state.

This is intentionally simple for the first milestone. SwiftData persistence should replace the in-memory store once the transcript and question shapes settle.

## Audio Capture

`AudioCaptureProviding` is the seam for microphone recording.

`AudioCaptureService` remains available as a low-level audio-capture seam, but the current prototype routes microphone audio through `LocalSpeechTranscriptionService` so live transcription can own the audio tap and speech request together.

## Transcription

`TranscriptionProviding` is the seam for audio-file and eventually live transcription.

The current implementation, `LocalSpeechTranscriptionService`, uses Apple's Speech framework with `requiresOnDeviceRecognition = true`. It supports live microphone transcription and imported audio-file transcription. Imports are copied locally from the selected Files/iCloud URL, then the app prefers iOS 26 `SpeechAnalyzer`/`SpeechTranscriber` for longer files before falling back to buffer-based `SFSpeechAudioBufferRecognitionRequest`.

The app checks that the recognizer supports on-device recognition for the active locale before starting. If local recognition is unavailable, it fails visibly instead of falling back to network speech recognition.

Long live sessions will need transcript chunking. The first prototype keeps one active recognition task and saves the current recognized text when recording stops.

## Question Generation

`QuestionGenerating` is the seam for local AI.

`FoundationQuestionGenerator` uses Apple Foundation Models through `SystemLanguageModel.default` and checks `availability` before creating a `LanguageModelSession`. If the model is not available on device, generation fails visibly rather than falling back to a cloud provider.

The first response format is plain text with a strict parser. The app throttles transcript changes and refreshes questions while conversation continues, rather than waiting for recording to stop. New questions are added to the top of the feed, and the selected conversation topic is passed into the prompt. Once the end-to-end workflow is stable, this can move to structured generation using Foundation Models schemas.

## Product Flow

1. Create or select a session.
2. Record or import audio.
3. Append transcript segments to the session.
4. Generate "For" and "Against" questions from the accumulated transcript.
5. Persist the session locally.
