# Witness — Activation Home — investigation + proposal (report only)

Date: 2026-08-20. **No build, no edits, no git.** Rebuild Home as the premium floating-text "activation Home."

> ⚠️ **Spec file missing.** `Witness_Activation_Home_Spec.md` is **not in the repo** (checked root + tree). This
> is built to the PROMPT only. The **starter prompt list "in the spec" is unavailable** — I need it, or I'll seed
> a placeholder set you tune. Anything spec-specific below is marked provisional.

---

## Investigation

### 1. Current HomeView — structure / data / keep vs replace
- **Greeting:** time-of-day string ("Good morning") + "Your Witness" (serif). `header` (HomeView:70).
- **Stage machine** (`neutral / begin / learning / ready`, HomeView:22) chosen from `memoriesVM.total` +
  `HomeViewModel.hasEnoughData`.
- **`readyContent`** (HomeView:125): `/explain-me/overview` **headline** + **"ACTIVE FORCES"** (`forceCard`) +
  **"PICK UP WHERE YOU LEFT OFF"** recent memories (`recentMemoriesCard`) + "Talk it through with {companion}".
- **Data:** `HomeViewModel.load` → `GET /api/v1/explain-me/overview` (headline/coreForces/hasEnoughData);
  `memoriesVM.load` → the memory list.
- **Safe to REPLACE:** the entire stage machine, Active Forces, recent-memories card, time-of-day greeting.
- **KEEP / reuse:** `HomeView(auth:memoriesVM:tab:)` props; `memoriesVM` as the real-memory source; the
  `NavigationStack` + `.navigationDestination(for: MemoryDTO.self) { MemoryDetailView(listItem:auth:) }`; the
  `fullScreenCover` Record entry (with `onSaved → memoriesVM.refresh`). **`HomeViewModel` (overview) becomes
  unused** on Home once Active Forces is removed → stop loading it here (leave the file for later reuse).

### 2. Memory data for the floating memory line (the critical one)
Home's real memories come from `memoriesVM.memories: [MemoryDTO]`. `MemoryDTO` (list) exposes:
`id, title, narrative?, narrativeSnippet?, exactDate, timeGranularity, exactDateEstimated, narratorAge,
qualityScore, importanceScore, people:[String]?, location, createdAt, updatedAt`.
- **No notable-line / key-line / theme field on the list DTO.**
- `MemoryDetailDTO` has `quotes[].quoteText` + `emotions` — a real "notable line" would require a **per-memory
  `/detail` fetch (N calls)**; too heavy for a cycling Home.
- **Media is NOT on the memory DTO.** It only exists via `GET /api/v1/media/gallery` (`MediaItemDTO.memoryId →
  url`) — a separate fetch to cross-reference.
- **Confirmed fallback for the "key line":** `narrativeSnippet` → first sentence of `narrative` (when present) →
  `title`. Date via existing `MemoryFormat.date(m)`.
- **Recommendation:** v1 floating memory line = **title + key line (snippet/first-sentence)** (+ date). Treat
  **media as optional Phase-2** (load the gallery once, map `memory_id → first image url`) or defer.

### 3. Record priming
- `RecordView(auth:onSaved:)`; opened via `fullScreenCover`. **No initial-suggestion / prefill param today.**
- Type mode already shows **Title** + **"When was this?"** fields and a body **placeholder**
  ("Write the memory in your own words…"). Speak mode shows title/date before recording.
- **To prime:** add an optional `initialSuggestion: String? = nil` used as the **disappearing body placeholder**
  (and default the mode to `.type` when a suggestion is present so it's visible). Title/date already encouraged.
  Small, additive change; thread the suggestion only from a Home prompt tap.
- **No tab-bar "+".** The tab bar is home/memories/talk/insights/you — there is **no global + Record**. Record is
  reached from Home/Memories/Timeline buttons. (See decision #2.)

### 4. Narrator name for "Hi {narrator}!"
- `@AppStorage(Profile.firstNameKey)` (same source `TalkView`/`SettingsView` use). Greeting uses it when
  non-empty; a no-name variant otherwise ("Hi! What would you like to share…").

### 5. Haptics
- `Haptics.tap()` = `UIImpactFeedbackGenerator(style: .light)` (Hints.swift:94). Ideal for the subtle press.

---

## Proposed structure (for approval — not yet built)

### New file: `ActivationPrompts.swift` (easily editable model + list)
```swift
enum HomePromptType { case singular, repeatable, parent }   // singular evolves to repeatVariant after use

struct HomePrompt: Identifiable {
    let id: String            // stable key for used/retire tracking
    let base: String          // the line shown (cold start)
    let type: HomePromptType
    var repeatVariant: String? = nil   // singular → shown after the base is used
    let kind: String          // grouping for "retire after 2 of this kind"
}

enum ActivationPrompts {
    // PROVISIONAL starter set — replace with the spec list; David tunes freely.
    static let all: [HomePrompt] = [
        .init(id: "love_of_life", base: "Tell me about the love of your life.",
              type: .singular, repeatVariant: "Tell me about another person you’ve loved.", kind: "people"),
        .init(id: "turning_point", base: "Tell me about a moment that changed everything.",
              type: .repeatable, kind: "turning_point"),
        .init(id: "childhood_home", base: "Describe the home you grew up in.",
              type: .singular, repeatVariant: "Describe another place that shaped you.", kind: "place"),
        // … more, from the spec …
    ]
    static let freeform = "You decide what to share…"   // ALWAYS in the cycle (id: "freeform")
}
```

### New file: `HomeActivationViewModel.swift`
- Owns: the **current cycling item**, a **slow cross-fade timer** (~5–7s), the **live pool**, and **local
  persistence** of used-prompt ids + per-`kind` counts via `@AppStorage` JSON (needed because **memories carry
  no category** — "retire after 2 of a kind" must be tracked locally, not inferred).
- **Pool** = active prompts (not used-and-removed, not retired) **+** real memories (`memoriesVM.memories`) **+**
  always `freeform`, **shuffled**; recompute when `memoriesVM.memories` changes.
- **Cycle logic:**
  - Recording **from a prompt** → mark that prompt id **used** (remove from pool) and **+1** its `kind` count; the
    just-recorded memory enters the pool on the next `memoriesVM.refresh`.
  - A **kind retires after 2 real memories recorded from prompts of that kind** (local count ≥ 2 → drop remaining
    prompts of that kind).
  - **Singular evolves:** once a singular prompt's `base` is used, show its `repeatVariant` instead (becomes a
    gentle repeatable).
  - `freeform` always present; never retired.
- Exposes: `current: CycleItem` (`.prompt(HomePrompt)` or `.memory(MemoryDTO)`), `advance()`, `markRecorded(from:)`.

### `HomeView` rebuilt (premium/minimal)
- **Greeting** (top, floating serif, one of **3 launch-varying variants**, picked once per launch):
  "Hi {narrator}! What would you like to share with me today?" / "…What new stories can we explore this session?"
  / "…The more you share, the more I’ll understand you."
- **Cycling floating item** (center, the star): transparent, **no card chrome**, generous negative space, **slow
  cross-fade** (`.easeInOut ~1.2s`), **subtle grow on press** (scale ~1.03) + `Haptics.tap()`. Serif. No bounce.
  - Prompt → the line (evolved variant if applicable).
  - Memory → `title` + key line (snippet/first-sentence) [+ media later].
- **Taps:** prompt → **primed Record** (`initialSuggestion` = the prompt base; encourage title/date);
  memory → `MemoryDetailView`.
- **Remove** the Active Forces list + stage machine + recent-memories card from Home.
- Motion: driven by `TimelineView`/`Timer` + `withAnimation`, slow and calm; respect Reduce Motion.

### `RecordView` change
- Add `var initialSuggestion: String? = nil`; when set, default to Type mode and use it as the vanishing body
  placeholder. Home threads it on prompt tap; blank Record (global) stays blank.

---

## Decisions needed before I build
1. **Starter prompt list** — send the spec list, or approve seeding the provisional set above (you tune later).
2. **"Tab-bar +"** — none exists. Add a global "+" that opens blank Record, or treat the Memories "+" as the
   blank-Record entry? (The prompt/memory taps on Home handle primed Record either way.)
3. **Media on the floating memory line** — v1 = title + key line only (recommended), or load the gallery to
   attach a thumbnail?
4. **"Retire after 2 of a kind"** — confirm OK to track **locally** (per-kind counts in UserDefaults), since
   memories expose no category.

## When approved
Apply, then **BuildProject → 0/0** + per-file diagnostics (HomeView, HomeActivationViewModel, ActivationPrompts,
RecordView). Honest caveats: the cycle/retire behavior and priming are device-verified; media/notable-line are
constrained by the DTOs as reported. No git.
