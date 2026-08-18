# Witness — Memory "Listen" (on-device TTS) upgrade — Result

Date: 2026-08-18. Build **0 errors / 0 warnings**. No git. iOS-only, no backend.

## Applied
- **Speaker.swift:**
  - **Best reading voice** — `static bestReadingVoice()` picks the highest-quality installed **English** voice
    (premium > enhanced > default), **preferring "Ava" within the top tier**, then the current locale.
    Decoupled from the companion gendered voice (that stays for Talk). Removed the old
    `voiceSelection()` / `bestVoice(gender:)`.
  - **Exposed** `@Published voiceName` + `@Published onlyDefaultQuality`, and a static `readingVoiceInfo()`
    (name + isDefaultOnly) the UI can read before playback.
  - **Long-memory chunking** — `static sentenceChunks(_:target:320)` splits on `. ! ?`/newlines, coalesces to
    ~320 chars, and hard-splits monster sentences. `speak(paragraphs:)` now sub-splits each paragraph into
    these chunks, mapping every sub-utterance back to its **display-paragraph index** → a 108K one-paragraph
    memory reads start-to-finish with no giant utterance, and the follow-along highlight/auto-scroll are
    unchanged.
  - **Rate/pitch** — `AVSpeechUtteranceDefaultSpeechRate * 0.9` (a touch slower), natural pitch `1.0`.
  - **Interruptions** — observes `AVAudioSession.interruptionNotification`: `.began` → pause; `.ended` +
    `.shouldResume` → reactivate session + resume. (Sendable values extracted before the `@MainActor` Task to
    stay Swift-6-clean.)
  - Neural-TTS seam preserved (Option B / Gemini HD plugs in behind the identical currentParagraph/
    paragraphCount contract).
- **MemoryDetailView.swift:**
  - `readAloudRow` = the Read-aloud pill + a **Stop** button (shown while speaking/paused).
  - `readAloudProgress` now shows **"Voice: {name}"** under "Reading N of M".
  - `enhancedVoiceHint` — one-time, dismissible (`@AppStorage`) nudge shown only when
    `Speaker.readingVoiceInfo().isDefaultOnly` (set in `.onAppear`).
  - `resolveMemoryAudioURL()` → **nil** — kills the random most-recent-`.m4a` placeholder; the recording
    `listenPlayer` stays dormant/ready for a future `GET /memories/{id}/audio`.

## Verified
- **BuildProject → "The project built successfully"** (0 errors). Per-file diagnostics **clean**: Speaker,
  MemoryDetailView (0 issues each).
- One self-caught warning en route to green: the interruption `Task` initially captured the non-Sendable
  `userInfo` dict → fixed by extracting `type` + `shouldResume` before the Task. Now 0 warnings.

## Honest scope / caveats (device checks — not verifiable in this environment)
- **NOT run on device/simulator by me** (build + diagnostics only). The real wins — Ava/premium voice quality
  vs default, a very long memory reading to completion without stalling, and a call actually pausing then
  resuming — are **device checks** (the simulator ships few, low-quality voices, so `onlyDefaultVoice` may be
  true there and the hint will show).
- Memory read-aloud now uses the **best device voice**, not the companion gendered voice (per approval).
- Random-clip recording player removed via `resolveMemoryAudioURL → nil`; the recording UI + "No recording to
  play yet." remain (kept, not deleted).
- Option B (Gemini HD) can later share this transport UI behind a toggle via the preserved seam.

## No git.
