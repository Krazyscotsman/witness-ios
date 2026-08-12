# Witness — Profile/Settings edit wired (PUT /api/v1/settings/profile, Option A) — Result

Date: 2026-08-12. Build **0 errors / 0 warnings**. No git.

## Applied
- **APIClient.swift** — `putIgnoringResponseBody(...)`: PUT that treats **any 2xx as success and does not
  decode the body** (tolerant of {status,…}/empty/204); throws APIError on 401 / non-2xx / transport.
- **APIModels.swift** — `ProfileUpdateRequest` (partial, all-optional, snake_case). Names always sent; the
  three voice fields sent only when the voice changed (nil omitted via encodeIfPresent).
- **AuthManager.swift** — `updateProfile(_:)` → PUT (20s), any-2xx success.
- **MainTabView.swift / YouView.swift** — thread `auth` down to `SettingsView(auth:)`.
- **SettingsView.swift** — new top **"Edit profile"** section: first/last name, companion name, six-option
  voice picker (drafts prefilled from @AppStorage on first appear; current voice highlighted). **Save changes**
  with busy spinner + subtle **"Saved"**; on success commits `firstName/lastName/companionName/voiceKey/
  customVoiceNameKey(=Gemini)` to @AppStorage so companion display + read-aloud/Talk voice update immediately.
  On failure: stays put, drafts preserved, friendly copy + action — **401→"Sign in"** (`auth.logout()` →
  ContentView routes to the door), **400→validation message**, network/other→**Try again**. Editing any field
  clears the error/"Saved". `custom_voice_name` is derived **solely** from the picker via the reused mapping.

## Removed (per Option A)
- The duplicate inline **first/last-name** rows from `profileSection` (now DOB/gender/city/state only).
- The duplicate **companion-name** row and **voice list**, plus the obsolete manual **"Custom voice name"**
  field, and the now-unused `voiceRow(_:)`.
- **The `companionSection` was removed entirely, which also removed the "Voice confirmation" toggle**
  (`voiceConfirm`) and its `@AppStorage` declaration. CONFIRMED intentional per your flag — it's a local-only
  setting with no backend, and it is **no longer present anywhere in the UI**. (The `Profile.voiceConfirmKey`
  constant remains defined but unreferenced; harmless. Easy to reintroduce elsewhere later if wanted.)

## Verified
- Build **0 errors / 0 warnings** (clean on first build). Per-file diagnostics — SettingsView, APIClient,
  APIModels, AuthManager, MainTabView, YouView — all report no issues.
- Partial-send logic: names always; voice trio only when `draftVoice != originalVoice`, carrying the correct
  load-bearing `custom_voice_name` (Gemini) from the mapping.

## Honest scope / caveats
- **NOT exercised against the live backend.** The PUT round-trip (2xx / 400 / 401) and the field/shape
  contract are wired to the agreed spec but unconfirmed on real responses. This is the testable one — on
  device: edit the voice → Save → then a memory's **Read aloud** should speak in the new voice (verifies
  `custom_voice_name`/voice → playback and the shared onboarding mapping). Also worth checking: a forced 401
  → sign-in door; a 400 → validation copy with drafts intact; airplane mode → network copy + working retry.
- Prefill copies from @AppStorage once per SettingsView instance (guarded by `prefilled`), so unsaved drafts
  aren't clobbered on re-appear; a fresh instance re-reads the now-saved values.

## No git.
