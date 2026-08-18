# Witness — HD (Gemini) memory voice + Native↔HD toggle — Result

Date: 2026-08-18. Build **0 errors / 0 warnings**. No git. iOS-only (backend endpoint already works).

## Applied
- **APIModels.swift** — `MemoryAudioResponse { audioBase64?, mimeType?, duration?, voice?, style?, characterCount? }`
  (`nonisolated`, `.convertFromSnakeCase`).
- **AudioPlayer.swift** — added `load(_ data: Data)` (`AVAudioPlayer(data:)`) to play the decoded base64 WAV;
  same reset/fail behavior as `load(url:)`.
- **MemoryDetailView.swift — unified Listen surface:**
  - **Device ↔ HD toggle** (`@AppStorage("listen.preferHD")`, remembered); HD chip disabled when the length
    guard fails. `mode` = `.hd` only when `preferHD && hdAllowed`, else `.device`.
  - **HD play** (`playHD`): `GET /api/v1/memories/{id}/audio?voice={hdVoice}&style=warm_memory` (60s,
    401→refresh→retry) → decode `audio_base64` → `audioPlayer.load(data)` → `play()`. First fetch shows
    **"Preparing HD audio…"**; failure → **`.failed` note + `preferHD=false`** (graceful fall back to Device);
    in-session cache keyed by `memoryId|voice` so replay/resume doesn't refetch.
  - **Voice validation:** `VoiceOption.geminiName(for: voiceKey)` whitelisted to the **6 app-emitted names**
    (Kore/Leda/Aoede/Orus/Charon/Puck), else **Kore** — can never send an invalid voice. `style=warm_memory`.
  - **Transport shared:** one play/pause button + Stop route to the active engine — **Device** → `Speaker`
    (+ "Reading N of M" + "Voice: {name}"), **HD** → `audioPlayer` (+ real time bar `mmss/mmss` +
    "Voice: {name} · HD"). Switching mode stops the other engine.
  - **Length guard:** `hdAllowed = narrative.count <= 9000` (tunable, gated on detail loaded) → HD chip disabled
    with "This memory is too long for HD yet — coming soon."; Device always available.
  - **Cleanup:** removed the dead recording player — `listenPlayer`, `toggleListen`, `resolveMemoryAudioURL`,
    `audioURL` — and `audioPlayer` is now solely the HD player.

## Verified
- **BuildProject → "The project built successfully"** (0 errors). Per-file diagnostics **clean**:
  MemoryDetailView, AudioPlayer, APIModels (0 issues each).
- One tool hiccup (not a code error): a removal Edit initially failed because `listenSurface` had been inserted
  between `toggleListen` and `readAloudControl`, shifting the trailing anchor; re-scoped the deletion and it
  applied cleanly.

## Honest scope / caveats (device + backend checks — can't run here)
- **NOT exercised against the live backend/device.** Verified: compile 0/0 + the fetch/decode/transport/toggle/
  fallback/length-guard logic read through. A device pass confirms: the WAV round-trip
  (`AVAudioPlayer(data:)` playing the decoded base64), first-call latency + "Preparing…", the 8-voice
  validation (we only ever send one of the 6 → safe), `warm_memory`, replay-from-cache, and the length guard
  keeping the un-chunked backend from failing on big memories.
- **HD voice = 6 of the backend's 8** (the app can't emit the other 2); default Kore.
- **Recorded-memory original audio** (`GET /memories/{id}/media`) intentionally **deferred** — follow-up.
- Native path unchanged (best/Ava device voice, sentence-chunked, interruption-safe) and remains the fallback.

## No git.
