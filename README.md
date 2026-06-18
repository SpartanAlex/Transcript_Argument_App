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
- Import audio placeholder.
- Microphone capture placeholder.
- Foundation Models question-generation service.
- Local session model stored in memory for the first prototype.

## Next Milestones

1. Replace the transcription stub with live on-device transcription.
2. Persist sessions with SwiftData.
3. Add Share Sheet/File import handling for Voice Memos exports.
4. Add streaming transcript updates.
5. Run on an Apple Intelligence-capable iPad and benchmark latency, heat, and battery use.

## Requirements

- Xcode 26.4 or newer.
- iOS/iPadOS 26.0 SDK.
- Apple Intelligence-capable iPad or iPhone for Foundation Models.

## Build

Open `ConversationCoach.xcodeproj` in Xcode and run the `ConversationCoach` scheme on a modern iPad or iPhone.

