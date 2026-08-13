# Witness — Home tab read-first map (report only; no build, no git)

## What Home displays today
- **Header:** greeting (time-of-day, local `Calendar`, NOT personalized) · "Your Witness" title · CompassMark.
- **StateSwitcher** (Begin / Learning / This is you): a manual `@State` 3-segment pill, commented
  `// TEMPORARY — backend readiness flag later`.
- **Begin:** hero "Your witness begins here." + explainer · button "Record your first memory" → RecordView.
- **Learning:** hero "The picture is forming." + explainer · 2× `formingCard` (skeleton shimmer bars) ·
  button "Add a memory" → RecordView.
- **Ready:** "HERE'S WHAT'S EMERGING" · HARDCODED headline "You return, again and again, to the people who
  shaped you." · "ACTIVE FORCES" + 3× HARDCODED forceCard (Family / Reinvention / Service) · button
  "Talk it through with **Scarlett**" → TODO no-op.

## Data source
Everything is sample/hardcoded or local. HomeView takes NO auth and NO VM. Nothing is wired to the backend.
Greeting is real-but-generic (time of day). The state switcher is a manual toggle.

## Should show real data → endpoint status
| Element | Source | Status |
|---|---|---|
| Begin/Learning/Ready readiness | `ExplainOverview.dataAvailable.hasEnoughData` + memory `total` | ✅ built (overview DTO + MemoriesVM) |
| Ready headline | `ExplainOverview.summary.headline` | ✅ overview |
| Active forces | `ExplainOverview.summary.coreForces` (`ExForceDTO`) | ✅ overview |
| "Talk it through with {companion}" | `Profile.companionNameKey` | ✅ local @AppStorage |
| Recent memories card (if added) | `MemoriesResponse.memories` | ✅ MemoriesVM (cached in MainTabView) |
| Greeting w/ first name | narrator first name | ⚠️ gap — ProfileDTO doesn't decode first_name |
| Daily prompt | — | ❌ no endpoint in any contract |
| Anchor counts | `/api/v1/entities` (isAnchor) | ✅ EntitySummary exists; not shown today |

## Quick wins (already-wired endpoints)
1. Replace the temporary StateSwitcher with the real signal: `total==0 → Begin`, `total>0 && !hasEnoughData →
   Learning`, `hasEnoughData → Ready`. Uses MemoriesVM.total (cached) + ExplainOverview (DTO/decoder built).
2. Fill Ready from the same `/explain-me/overview` call: `summary.headline` → hero; `summary.coreForces` →
   force cards. Highest value, lowest cost — same call that powers Insights → Explain.
3. Recent-memories card from MemoriesVM.memories (top 2–3) → tap → MemoryDetailView (all wired).

## Flags before wiring
- 🔴 LOCKED-RULE VIOLATION now: HomeView.swift:98 hardcodes "Talk it through with **Scarlett**". Must read
  `Profile.companionNameKey`. Fix regardless of broader wiring.
- Plumbing gap: MainTabView builds `HomeView()` with no auth/VM (unlike every other tab). Wiring needs auth +
  likely a HomeViewModel (overview) + access to memoriesVM.total + a `Tab` binding so Ready's "Talk it through"
  can switch to the Talk tab. `ExForceDTO` has no short subtitle field → force-card second line is a small
  design choice (candidate: `identityImpact` or an `affectedDomains` summary).
