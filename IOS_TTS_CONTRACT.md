# iOS TTS / Voice-Synthesis Contract — findings from the live code + specs

Date: 2026-08-09. Read-only investigation. No code modified.
Searched: the whole repo AND the machine (`~/Desktop`, `~/Documents`, `~/Downloads`, common dev dirs).

## Headline (read this first)
1. **No Gemini TTS endpoint exists anywhere I can see** — not in the iOS repo, and there is **no backend or
   web-app source on this machine at all** (searched home + Desktop/Documents/Downloads/common dev dirs).
   The tokens `companion_voice`, `tts/generate`, `VOICE_OPTIONS`, `gemini` return **no backend/web code** —
   only the iOS app and two spec `.md`s.
2. **The project's own spec explicitly says read-aloud is ON-DEVICE, no backend, no Gemini.** From
   `~/Downloads/Witness_Text_To_Speech_Spec.md` (dated 2026-08-08): *"fully local — no backend, no network,
   no seam… Use the platform's built-in speech synthesis."* Premium/branded voices are a **later** item (12),
   *"possibly cloud-based"* — i.e. not built, not decided.
3. **Gemini's only stated voice role is different from what the premise assumes.** The spec: the engine is
   *"the voice-output half of Talk later (**Gemini's text response → spoken audio**)."* That means Gemini
   produces **text**, which **on-device TTS** then speaks — NOT Gemini synthesizing audio. There is no
   Gemini-audio contract anywhere.
4. **So the premise "the read-aloud TTS is Gemini voice synthesis" is not supported by any code or spec on
   this machine.** The real, running read-aloud is Apple `AVSpeechSynthesizer`, and it does **not** use the
   six companion voices.

**Bottom line:** I cannot document a Gemini TTS contract from live code, because that code is not here.
Build/keep read-aloud **on-device**; the branded/cloud voice is an unbuilt future item.

---

## Direct answer to your diagnostic ("a memory that didn't finish reading")
**Almost certainly a size/length problem — NOT a content refusal.** Reasoning from the actual code path:

- The current read-aloud path is `MemoryDetailView.toggleReadAloud()` → `Speaker.speak(spokenText)` →
  **Apple `AVSpeechSynthesizer`** (on-device). Apple's synthesizer performs **no content moderation and does
  not refuse/flag text** — there is no refusal mechanism in this path, and no code/comment anywhere notes one.
- `Speaker.speak()` submits the **entire narrative as ONE `AVSpeechUtterance`** — **there is no speech
  chunking.** (The ~4000-char splitting in `MemoryDetailViewModel.splitNarrative` is for *rendering only*.)
  A single very long utterance — e.g. the ~174K-char "April 28, 1993" memory — is exactly the case that
  `AVSpeechSynthesizer` handles unreliably (it can stop partway). That matches a "didn't finish" symptom far
  better than any refusal.
- Two secondary suspects, both length/mechanics rather than content: the audio session getting deactivated,
  and the stop-then-restart race in `speak()` (guarded by `handleEnd()` but worth noting).

**If a specific memory reproducibly stops at the same word regardless of length, revisit — but nothing in the
current (on-device) path can "refuse" content.** Content-refusal is only conceivable once a *cloud* TTS is
wired, which it is not. **Fix direction: chunk the text into sentence/paragraph utterances and queue them.**

---

## 1. Is there a Gemini TTS endpoint? (method / path / auth / request / response / limits)
**Not determinable from live code — none exists on this machine.** The only endpoint breadcrumbs are three
identical **`// TODO` comments** in the iOS app naming a *future* `POST /api/v1/tts/generate` with hint
`{ text: answer }` (in `LearnView.swift`, `ExplainView.swift`, `EntityAtlasView.swift`). There is:
- **No** `APIClient` call, request model, or response model for it.
- **No** voice/personality parameter shown in any TODO (only `text`).
- **No** documented response shape (bytes? base64? URL? mp3/wav/opus? — unknown).
- **No** stated max text length or rate limit.
- **No** `gemini` / `elevenlabs` / `openai` / `azure` / `text-to-speech` reference in any code (only the
  `Speaker.swift` docstring "On-device text-to-speech. Fully local, no backend.").

The one **real** audio endpoint in the specs is **`GET /api/v1/memories/{id}/audio`** — but that returns the
**original human recording** for the "Listen" control (`Witness_Memory_Playback_Spec.md`), **not** synthesized
speech. Different feature; not TTS.

---

## 2. The six companion voices — definition, ids, and the `companion_voice` mapping
- **Defined in** `OnboardingView.swift` as `struct VoiceOption` / `VoiceOption.all`, labeled *"The six voices
  (verbatim from the web's VOICE_OPTIONS)."* Also shown in `SettingsView.swift`.

  | id | label | gender | desc |
  | --- | --- | --- | --- |
  | `warm_female` | Warm | female | Gentle and reassuring |
  | `direct_female` | Direct | female | Clear and confident |
  | `playful_female` | Playful | female | Light and energetic |
  | `warm_male` | Warm | male | Calm and steady |
  | `direct_male` | Direct | male | Strong and focused |
  | `playful_male` | Playful | male | Friendly and upbeat |

  Scheme `<style>_<gender>`, styles {warm, direct, playful}. **Default `playful_female`** (your "playful").
- **Storage:** local only — `@AppStorage(Profile.voiceKey)` = `"profile.voice"` (declared in `YouView.swift`).
  ⚠️ **The field name `companion_voice` does not exist anywhere on this machine** (searched — zero hits). The
  iOS app uses the local key `profile.voice` and a comment says onboarding *will*
  `POST /api/v1/settings/profile { …, selectedVoice, companionName }` — but that save is **TODO, not wired**,
  and the request key shown is `selectedVoice`, not `companion_voice`.
- **Mapping `voice id → Gemini voice setting`: does not exist in this repo.** The ids are bare strings with no
  table/enum/param mapping them to any Gemini voice/model/config. If such a mapping exists, it's in the
  backend/web app — which is **not on this machine.**
- **"How the web app passes the chosen voice when reading aloud": not determinable** — there is no web-app
  source here to read. (`VoiceOption` is annotated as copied *from* the web's `VOICE_OPTIONS`, but the web
  code itself is absent.)
- Onboarding itself states the system isn't connected: *"Voice previews play once the voice system is
  connected."*

---

## 3. Chunking (whole vs. chunked) and per-call limits
- **Web app chunking / per-call limit: not determinable** — no web/backend source on this machine.
- **iOS app:** does **NOT** chunk text for speech — `Speaker.speak()` sends the whole string as one
  utterance. On-device synthesis has no per-call size limit or rate limit (it's local/free), but long single
  utterances are unreliable in practice (see the diagnostic above). No chunking-for-speech exists yet.

---

## 4. Content-refusal behavior
- **In the current (on-device) path: none, and impossible** — `AVSpeechSynthesizer` does not moderate/refuse
  text, and **no code or comment anywhere notes any TTS refusal/skip behavior** (searched).
- A cloud model like Gemini *can* refuse/flag content in general, but **there is no Gemini TTS wired here**,
  so that behavior is not present in this app today and cannot be the cause of a truncated read-aloud now.

---

## 5. What I could NOT verify (and what to hand me to close the gap)
The real Gemini TTS contract — method, path, auth, whether it takes a voice id and how, response
format/encoding, max length, rate limits, refusal behavior, and the `voice id → Gemini voice` mapping — lives
in the **backend / web app, which is not present on this machine.** Nothing I can read here defines it.

To document it authoritatively, give me the backend/web repo (or its files): the `/tts` route handler, the
Gemini TTS client call, and the `VOICE_OPTIONS` → Gemini voice mapping. I'll extract the exact contract
verbatim.

## 6. Recommendation (unchanged, now spec-backed)
Read-aloud should stay **on-device** for now (this is literally what the spec prescribes). To fix "didn't
finish" and honor "same chosen voice everywhere the companion speaks":
- **Chunk speech** into sentence/paragraph-sized `AVSpeechUtterance`s and queue them (fixes long-memory
  truncation, incl. the 174K memory).
- Read `profile.voice` and **map the six ids onto `AVSpeechSynthesisVoice` gender + a rate/pitch character
  per style** as the on-device approximation of the companion voice, applied in `Speaker` so *every* caller
  (memories now, Talk later) uses it.
- Keep a clean seam so a future `POST /api/v1/tts/generate` (Gemini audio → `AudioPlayer`) can slot behind the
  same `Speaker` interface once the backend contract is actually known.
