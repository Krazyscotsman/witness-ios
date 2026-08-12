# Witness — Onboarding save wired (POST /api/v1/settings/profile) — Result

Date: 2026-08-11. Build **0 errors / 0 warnings**. No git.
One call only — the POST saves the profile AND flips onboarding_completed. `/auth/complete-onboarding` NOT called.

## Applied
### APIModels.swift
- `ProfileCreateRequest: Encodable` (snake_case). `first_name`/`last_name`/`birth_date` always sent
  (`last_name` `""` when empty, never omitted); optional `birth_city`/`birth_state`/`gender` omitted when nil
  (synthesized encodeIfPresent); `companion_name` + all three voice fields always sent.
- `ProfileCreateResponse: Decodable { status: String?; narrator_id → narratorId }` — the small ack the
  contract returns (NOT ProfileDTO, NOT 204).

### AuthManager.swift
- `saveOnboardingProfile(_:)`: `POST /settings/profile` (20s) decoding into `ProfileCreateResponse`; **any 2xx
  = success**, sets `onboardingCompleted = true` (does not depend on reading the flag back — launch fetch
  confirms it). Throws `APIError` for the view to map.

### OnboardingView.swift
- Voice mapping added VERBATIM: `VoiceOption.geminiName(for:)` (warm_female→Kore, direct_female→Leda,
  playful_female→Aoede, warm_male→Orus, direct_male→Charon, playful_male→Puck; unknown→Aoede) and
  `VoiceOption.personality(for:)` (style token). Derived: `companion_voice = id`,
  `companion_personality = personality`, `custom_voice_name = geminiName`.
- ISO date: `static let` `DateFormatter`, `Locale("en_US_POSIX")`, `"yyyy-MM-dd"`.
- Completion button now runs `save()` with a busy state (spinner + disabled while saving / until agreed).
- `save()`: build body → `auth.saveOnboardingProfile` → on success persist `lastName`/`birthdate`/
  `selectedVoice`/`customVoiceName(Gemini)` to their `Profile` keys → `onFinish()` (route to main).
- On failure: stays on the completion screen, clears busy, shows a friendly banner + tailored action:
  401 → "session timed out, sign in" → `auth.logout()` (ContentView's watcher routes to the door);
  400 → "problem with your date of birth" → returns to the DOB step (completed=false; step=1);
  network → "check your connection, try again" → retry; other → generic → retry. No raw codes, no dead-end.
- Takes `@ObservedObject var auth`.

### ContentView.swift
- `OnboardingView(auth: auth, onFinish: …)`.

## Verified
- Build: **0 errors, 0 warnings.** Per-file diagnostics (APIModels, AuthManager, ContentView, OnboardingView)
  all report no issues. (OnboardingView hit the transient SourceEditor error 5 once, cleared on retry.)
- Voice mapping transcribed exactly as given.

## Honest scope / caveats
- NOT run against the live backend. The request field names/shape, the `{status, narrator_id}` ack, and the
  four error-status mappings are wired per the confirmed contract but unexercised against real responses.
  Worth an on-device pass: happy path (save → main, and a relaunch confirms onboarding_completed via the
  launch fetch); a forced 401 (→ sign-in door); a 400 (→ back to DOB step); airplane mode (→ network message,
  retry works).
- Decode is `ProfileCreateResponse` and success is treated as any 2xx (per your fix) — so a valid ack won't be
  misread, and we don't depend on the body for the flag.
- Per spec, `birth_city`/`birth_state`/`gender` are POSTed but not written to local `Profile` keys (Settings
  reloads from backend); only lastName/birthdate/voice/Gemini-name are persisted locally.

## No git.
