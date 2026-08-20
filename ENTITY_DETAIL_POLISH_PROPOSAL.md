# Witness — Entity Detail polish (interaction/layout) — Report + Proposals

Status: **REPORT ONLY — no build, no git.** These need a design call; I'll implement to 0/0 once confirmed.

## Read-first findings
- **Body** (`EntityDetailPage`, loaded branch): one `ScrollView` → `VStack(spacing:18)` with `header, heroCards,
  summaryCards, dialogueSection, acrossMemoriesSection, relationshipEvolutionSection, romanticDynamicsSection,
  phase5Sections, linkedMemoriesSection`, padded `.top 60 / .bottom 40` (line 220).
- **Entry contexts:** graph → `NodeDetailSheet` (a `.sheet`, no tab bar); people anchor → `RelationshipDetailView`
  **inside the Insights tab** (tab bar ≈ 83pt).
- **Summary tiles** (`summaryCards`, line 696): Entity type · Anchor · **Linked memories** (`linkedMemories.count`,
  inert) · **Sections** (`populatedSectionCount` = count of non-empty top-level `attributes` keys, inert).
- **Linked Memories** (`linkedMemoriesSection`, line 717): an **always-visible bottom section** listing every
  linked memory as a tappable row → `MemoryDetailView` (destination-closure NavigationLink — already works).

## 1. Bottom padding bug
- Cause: `.padding(.bottom, 40)`. In the Insights-tab context the tab bar (~83pt) overlaps it → last card clipped.
  Every other tab-embedded detail view uses `.bottom, 110`.
- **Fix (recommend apply): `.padding(.bottom, 110)`** — clears the tab bar; harmless extra space inside the sheet.

## 2. Linked Memories structure + making the tile tappable
Currently: always-visible bottom section (works, but adds length to an already-long page); the tile is inert.
- **B1 (recommend): tile → pushes a dedicated Linked-Memories list; REMOVE the always-visible bottom section.**
  Tile becomes meaningful, page gets shorter, memories are one tap away (tile → list → `MemoryDetailView`). Needs a
  small pushed view (reuses `memoryRow`).
- **B2: keep the bottom section; tile scrolls to it** (ScrollViewReader). Lower effort, keeps memories visible, but
  the page stays long and the tile is only a jump link.

## 3. "Sections" tile
`populatedSectionCount` ("39 Sections") is inert and meaningless to a user.
- **C (recommend): replace "Sections" → "Quotes" = `vm.dialogueLines.count`** (verbatim things they said — the
  page's centerpiece, already computed), and **tap → scroll to "Everything they said"** (ScrollViewReader).
  Meaningful metric + useful jump.
- Alternatives: (a) keep "Sections" but make it tap→scroll to the first detail section; (b) a different metric
  (year span needs reliable dates we don't have; "Notable lines" = `dialogue_and_quotes` count is another option);
  (c) remove the tile → a 3-tile row.

## Recommended package
**A** (bottom 110) + **B1** (tile → pushed list, drop bottom section) + **C** (Quotes tile → scroll to dialogue).
Both bottom tiles become purposeful, the page shortens, and the clip is fixed.

## Open decisions (confirm before I build)
1. Linked memories: **B1** (push to list, remove bottom section) or **B2** (keep bottom, tile scrolls)?
2. Sections tile: **C** (replace with "Quotes", tap-to-scroll) or a different metric / remove?

## Notes
- If **B1**: scroll-to-dialogue for the Quotes tile still works (dialogue section stays inline). If **B2**: both
  tiles use the same ScrollViewReader.
- Scroll-to a collapsed `EDSection` lands on its header (collapsed). Auto-expanding on tap would need `EDSection`
  to take an external expand binding — I can add that if you want the tile to also open the section (flag).
- Build 0/0 + honest report when we proceed. No git.
