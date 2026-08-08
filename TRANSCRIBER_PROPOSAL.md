# Witness — On-device Transcriber (item 3) — Proposal

Status: **PROPOSED — nothing applied. Awaiting approval + Info.plist key.** No git.

## Read-first findings
- Recorded-file URL for the proof UI: `AudioRecorder.lastRecordingURL` is in scope in
  RecordView.savedView via `recorder.lastRecordingURL` (the just-recorded file). ✅
- Speech framework available on iOS 26 (`import Speech`). ✅
- Info.plist has NSCameraUsageDescription + NSMicrophoneUsageDescription but NOT
  NSSpeechRecognitionUsageDescription. ⚠️ Needs adding.

## Step 0 — permission (REQUIRED; add in Xcode)
requestAuthorization crashes at request time if the key is missing (Apple: app will crash).
Add via the target Info tab / Info.plist:
- Key: NSSpeechRecognitionUsageDescription
- Value: Witness transcribes your recordings on your device so your memories become searchable text.
(Not edited by me — user adds in Xcode.)

## Verified iOS 26 SDK signatures
- `class func requestAuthorization(_ handler: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void)` (handler not guaranteed on main)
- `class func authorizationStatus() -> SFSpeechRecognizerAuthorizationStatus` (.notDetermined/.denied/.restricted/.authorized)
- `init?(locale: Locale)` / `init?()`; `var isAvailable: Bool`; `var supportsOnDeviceRecognition: Bool`
- `SFSpeechURLRecognitionRequest(url:)`; `.requiresOnDeviceRecognition`; `.shouldReportPartialResults`
- `recognitionTask(with:resultHandler: (SFSpeechRecognitionResult?, (any Error)?) -> Void) -> SFSpeechRecognitionTask`
- `SFSpeechRecognitionResult.isFinal`, `.bestTranscription.formattedString`; `SFSpeechRecognitionTask.cancel()`

Honest notes: progress stays nil (URL recognition reports no fraction; not faked). No-speech
detected heuristically by NSError code (203/1110, no public constant) + empty-final path;
other errors → .unavailable(reason). Never falls back to cloud.

## New file — Transcriber.swift
(See full source in the chat proposal; @MainActor ObservableObject, import Speech, states
idle/running/done/unavailable/denied/noSpeech, requestPermission/transcribe/cancel, off-main
callbacks marshalled to @MainActor via Task, requiresOnDeviceRecognition=true.)

## Proof UI — RecordView.swift (temporary scaffold, saved screen)
- `@StateObject private var transcriber = Transcriber()`
- `transcribeScaffold`: "Transcribe (temp)" button → transcriber.transcribe(recorder.lastRecordingURL),
  shows engine state + live transcript (maxHeight 120 scroll). Clearly marked TEMP.
- Inserted in savedView after playbackBar; `.onDisappear` also calls transcriber.cancel().

Out of scope (not built): wiring into Talk/exploration/nav/video, backend path, filler-scrubbing.

## After approval + key added
Create Transcriber.swift, apply RecordView diff, build 0/0, report honestly. Engine is
device-testable (record → Transcribe). No git.
