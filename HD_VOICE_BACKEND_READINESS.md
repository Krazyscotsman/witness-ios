# Witness — HD (Gemini) memory voice: backend readiness — report

**Date:** 2026-08-18. Read-only.

## STATUS: backend source is NOT on this machine (searched)
The working directory is the **iOS client only**. On 2026-08-18 I searched `~`, `~/Documents`, `~/Desktop`
(depth 3) for any Python / `requirements.txt` / `pyproject.toml` / `main.py` / `app.py` and for any
`*moryn*` / `*backend*` directory — **none found**. The `~/Documents/moryn-systems` repo referenced by the
earlier graph spec is not present now. Therefore the backend **cannot be documented from live code here**, and
nothing about it is fabricated. Below is the iOS-client contract (grep-verified) + the exact questions to answer
against the real backend.

## iOS-visible evidence vs. verdict
| Question | iOS evidence | Verdict |
|---|---|---|
| `POST /api/v1/tts/generate` — exists? req/resp/format? | TODO comments only (LearnView, EntityAtlas, Speaker seam). Never called. | Backend-only. |
| `GET /api/v1/memories/{id}/audio` — file/URL/job/404? | Not called; aspirational comment; `resolveMemoryAudioURL()` returns nil. Real audio path = media gallery (`/media/gallery`, `/media/{id}/url` presigned, `/media/{id}/file`) with `file_type`/`memory_id`. | Backend-only; uploaded recording (if any) discoverable via media gallery by memory_id. |
| Gemini wiring / model / params / companion==memory / 564-cache? | Client stores `custom_voice_name` (`VoiceOption.geminiName`) on profile; comment says it "drives playback." No TTS endpoint called. Model/params/reuse/564-cache: zero refs. | Backend-only. |
| Recorded vs text — field/table? | `MemoryDetailDTO` has no has_recording flag; only signal = linked audio media (gallery memory_id + file_type=="audio"). | Backend-only. |
| Storage (generate-once by memory_id+voice)? | Media served via presigned URLs; generated-TTS persistence not represented client-side. | Backend-only. |
| Chunking (32K-token limit)? | iOS chunks on-device for the NATIVE voice (`Speaker.sentenceChunks`). No backend chunking visible. | Backend-only / likely needs building. |
| Streaming (chunk-1 plays while chunk-2 generates)? | Client plays whole files only; no streaming client. | Backend-only; iOS would need a streaming player built. |
| Cost logging (char/token/cost)? | None client-side. | Backend-only. |
| Provider abstraction (Gemini↔local/4090↔other)? | iOS has its own seam (Speaker NEURAL-TTS SEAM) behind the shared transport. Backend swappability not represented. | Backend-only for the server; iOS seam ready. |

## iOS readiness (client half of the A/B) — already in place
- Native on-device path complete (best/Ava voice, sentence-chunked, transport, interruption-safe).
- HD seam: an HD provider fetches audio per chunk (e.g. `POST /api/v1/tts/generate { text: chunk, voice:
  <gemini_name> }` → bytes → AudioPlayer), sets currentParagraph/paragraphCount identically → the existing
  player UI (play/pause/stop/progress/voice-name) needs NO changes; an A/B toggle swaps providers behind it.

## Questions to answer against the live backend
1. `POST /api/v1/tts/generate` — exists? request/response shape (text+voice → bytes/URL)? audio format?
2. `GET /api/v1/memories/{id}/audio` — exists? returns file / URL / async job id? 404 today?
3. Gemini TTS — wired? model + voice params? does stored `custom_voice_name` drive it? is companion-conversation
   TTS the same pipeline, reusable for memory reading? what is the 564-phrase startup cache pre-warming, same
   pipeline?
4. Recorded vs text — field/table marking a memory as having an original recording (play that, no synthesis).
5. Storage — generated audio persisted (generate-once), keyed by memory_id + voice? DB / object store / fs?
6. Chunking — server-side chunking for the 32K-token limit? lazy per-chunk?
7. Streaming — whole-file only, or streamable?
8. Cost logging — per-generation char/token/cost tracking?
9. Provider abstraction — TTS provider swappable (Gemini ↔ local/4090 ↔ other) or hard-coded?

## To produce the verified doc
Give me read access to the backend: (1) point me at its path on this Mac, (2) copy/clone it somewhere reachable
(e.g. ~/Desktop/), or (3) drop the FastAPI TTS/audio router + Gemini TTS module + memory/audio model (or a TTS
spec, e.g. in ~/Downloads). Then I'll replace this client-side view with the confirmed backend contract.
