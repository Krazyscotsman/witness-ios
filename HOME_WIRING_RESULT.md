# Witness — Home tab → real data — Result

Date: 2026-08-13. Build **0 errors / 0 warnings**. No git. No new contracts.

## Applied
- **HomeViewModel.swift** (NEW, `@MainActor` + `import Combine`) — own read-only `GET /api/v1/explain-me/overview`
  (30s, snake decoder, fetch-once, 401→refresh→retry), reusing the `ExplainOverview` DTO. Exposes `state`,
  `overview`, and `hasEnoughData` / `headline` / `coreForces`. Failure sets `.failed` and surfaces no error on
  Home (degrade to count-only).
- **HomeView.swift** (rewritten) — now takes `auth`, `memoriesVM`, `@Binding tab`; owns `@StateObject vm` +
  `@AppStorage(Profile.companionNameKey)`. Wrapped in a local `NavigationStack`. `.task` fires both
  `vm.load` and `memoriesVM.load` (both fetch-once).
  - **Real stage** replaces the manual StateSwitcher: `total==0 → Begin`, `total>0 && !hasEnoughData →
    Learning`, `hasEnoughData → Ready`, with a **Neutral** placeholder while signals are unknown (commits to a
    panel only when it can't be wrong — `.begin` only when `total==0` is known). Overview `.failed` → count-only
    (Begin if 0 else Learning; Ready never shown without a loaded overview → no nil-force risk).
  - **Ready** ← real data: hero from `summary.headline` (fallback if null); top-3 `summary.coreForces` → force
    cards (title + second line from `identityImpact`, else an `affectedDomains` summary, else a gentle
    fallback).
  - **Recent-memories card** (Learning + Ready): top 3 of `memoriesVM.memories` → `NavigationLink` →
    `MemoryDetailView`.
  - 🔴 **Locked-rule fix:** companion name now read from `@AppStorage(Profile.companionNameKey)` (empty →
    `defaultCompanionName`); "Talk it through with {name}" switches to the Talk tab (`tab = .talk`). The
    hardcoded "Scarlett" and the no-op TODO are gone.
  - REMOVED: `StateSwitcher`, `MirrorState`, the manual `state`, `formingCard` skeletons, and the hardcoded
    headline + 3 hardcoded force cards.
- **MainTabView.swift** — `HomeView(auth: auth, memoriesVM: memoriesVM, tab: $tab)`.

## Verified
- **BuildProject → "The project built successfully"** (0 errors). Per-file diagnostics **clean**: HomeView,
  HomeViewModel, MainTabView (0 issues each). No transient error 5.
- `MemoryFormat.date(_:)` (MemoriesView.swift:192), `CompassMark` (DesignSystem), `Profile.companionNameKey` /
  `defaultCompanionName` (YouView.swift) all confirmed by reading before use.

## Honest scope / caveats (not bugs)
- **NOT exercised against the live backend** (none on this machine). Verified: compile 0/0 + the stage state
  machine + degradation logic + defensive accessors. A device pass confirms: the real overview
  headline/forces, `hasEnoughData` gating Begin/Learning/Ready, the recent-memory tap → `/detail`, and the
  Talk-tab switch.
- **Second overview call** by design (HomeViewModel doesn't share ExplainViewModel, which is owned below the
  Insights tab). Read-only; acceptable per the task.
- Overview failure degrades **silently** to count-only (no retry affordance on the landing screen — deliberate).
- Skipped per instruction: first-name greeting (ProfileDTO gap), daily prompt, anchor counts.

## No git.
