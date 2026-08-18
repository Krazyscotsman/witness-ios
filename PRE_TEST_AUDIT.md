# Witness iOS — pre-test audit (report only, no fixes)

**Date:** 2026-08-18. Read-only sweep of view + view-model code. No changes made.

## 🔴 Broken (visible defect a tester will hit)
- **Custom font never loads.** `Info.plist:28` — `UIAppFonts` = `" PlayfairDisplay-SemiBold.ttf"` has a LEADING
  SPACE, so Playfair fails to register; every `.serif(...)` silently falls back to system serif, and the app
  logs the font warning. This is the font-warning source.
- **Recording a memory doesn't persist.** `RecordView` records + transcribes on-device only; save is a comment
  (`RecordView:329 // Real: POST /api/v1/memories …`; `:315 "backend owns upload"`). No `POST /memories`
  anywhere → recorded/typed memories never reach the backend or the Memories list.
- **`Info.plist:6` `CFBundleIdentifier` is an empty string** (`<string></string>`) — normally
  `$(PRODUCT_BUNDLE_IDENTIFIER)`; verify it doesn't ship blank.

## 🟠 Half-wired (real screen, dead controls)
- **MemoryDetailView** edit (`:300 // TODO PUT /memories/{id}`) and delete (`:303 // TODO delete`) top-control
  buttons are visible no-ops.
- **Media capture** — gallery read is real; the `+` capture only adds to the in-session `MediaStore`; upload is
  a comment (`MediaCapture:27 // Real: POST /memories/{id}/media`) → captured media isn't persisted.
- **Shell-screen TTS/download buttons** are TODO no-ops: `LearnView:159`, `MemoirView:307`, `EntityAtlasView:280`.

## 🟡 Shell / placeholder (sample/mock, not backend) — reachable
- **Learn** (Insights → Learn): fully mock — `LearnReflection.sample` (`LearnView:208/265`), fake ask,
  `// Real: POST /learn/chat`; `InsightsView:34` `LearnView()` with NO auth. (Wiring proposal written earlier,
  never applied.)
- **Memoir** (Insights → Memoir): shell — `runGenerate()` fakes 2.2s → `.ready` (`MemoirView:342-347`),
  `// Real: POST /memoir/generate`, download-PDF TODO; `InsightsView:33` `MemoirView()` no auth.
- **AtmosphereModal** (from Memoir): `AtmospherePeriod.samples`; skip/save are `// POST …` no-ops.
- **EntityAtlasView** (Settings → Entity Atlas, `SettingsView:305`): `AtlasEntity.samples`; merge + delete are
  `// Real:` comment no-ops.
- **Settings → More** (`SettingsView:406`): `SettingsDetailPlaceholder` "coming together" screens.
- **BackendTestView** (You → dev sheet, `YouView:62`): dev tool.

## 🟣 Backend-blocked / deferred by design (confirmed)
- **Anchor delete** — "Deleting is coming soon." across all editors + registry (`AnchorRegistryView:323`,
  `RelationshipEditor:392`, `LocationEditor:283`, `JobEditor:293`, `EducationEditor:286`, `PetEditor:267`,
  Hobby/Service). (Gap 2.)
- **Anchor rename propagation** (Gap 1) — noted.
- **Login OAuth** (`LoginView:149`) — Apple/Google buttons are empty `Button { }` `.disabled(true)` (intentional).
- **HD voice length guard** (`MemoryDetailView` >9000 chars → "too long for HD yet") — deliberate; guards the
  un-chunked backend.
- **Recorded-memory original-audio playback** — deferred (HD/Native TTS works; original recording via
  `/memories/{id}/media` not wired).

## 🔵 Cosmetic / hygiene
- **DEBUG logging still in:** `🩺[Graph]`/`🩺[WitnessStart]` prints — `APIClient:149/161/165`,
  `GraphViewModel:51`, `AskScarlettView:40/67`. Remove before broad test.
- **ATS** scoped to dev IP `192.168.1.115` over http (`Info.plist:11`) — dev-only; prod needs HTTPS.
- **LegalView** shows explicitly-labeled draft placeholder legal text (`LegalView:98`).

## States (loading / empty / failed)
- Present on all real surfaces: Memories, Anchors, Timeline, Graph, Media, Explain (7 tabs), Home,
  Conversation history, Ask Scarlett / Talk.
- Absent because mock: Learn, Memoir, AtmosphereModal, EntityAtlas.

## Top tester surprises
1. New memories don't save (Record → no backend create).
2. Learn + Memoir look real but are mock/shell (no auth, sample output).
3. Memory edit/delete buttons are dead.
4. Playfair font silently absent (leading-space bundle path) → fallback serif everywhere.
5. Captured media isn't uploaded; Entity Atlas is sample data with dead merge/delete.

## Fully wired & real (for contrast)
Memories list + detail, Home, Insights → Explain / Timeline / Graph (+ node memories) / Media (read) / Anchors
registry (+ 7 editors, create/edit; delete blocked), Ask Scarlett + Talk (witness sessions) + conversation
history, memory Read-aloud (Native best-voice + HD Gemini toggle), onboarding + profile save, auth/login +
401-refresh.
