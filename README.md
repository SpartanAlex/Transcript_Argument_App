# Conversation Coach

Conversation Coach is an iPad-first SwiftUI prototype for private, local conversation support.

The intended workflow:

1. Capture or import conversation audio.
2. Produce a local transcript.
3. Use Apple Foundation Models on device to generate useful questions both for and against the current conversation.

## Prototype Decisions

- Native SwiftUI app for iPad and iPhone.
- iOS/iPadOS 26.0 minimum.
- Apple Foundation Models for question generation.
- Local-only AI behavior: the question generator checks `SystemLanguageModel.default.availability` and refuses to run if the on-device model is not available.
- Audio capture and transcription are scaffolded as replaceable services so we can choose the best Apple-native transcription path next.

## Current Status

- SwiftUI app shell.
- Session list and iPad workspace layout.
- Local-only microphone transcription using Apple's Speech framework.
- Local-only audio-file transcription for Voice Memos/File imports.
- Foundation Models question-generation service.
- Local session model stored in memory for the first prototype.

## Next Milestones

1. Run on an Apple Intelligence-capable iPad and benchmark speech accuracy, latency, heat, and battery use.
2. Persist sessions with SwiftData.
3. Add Share Sheet handling for direct Voice Memos exports.
4. Add transcript chunking for longer live sessions.
5. Move question generation from plain-text parsing to structured Foundation Models output.

## Requirements

- Xcode 26.4 or newer.
- iOS/iPadOS 26.0 SDK.
- Apple Intelligence-capable iPad or iPhone for Foundation Models.
- A locale that supports Apple's on-device speech recognition.

## Build

Open `ConversationCoach.xcodeproj` in Xcode and run the `ConversationCoach` scheme on a modern iPad or iPhone.
