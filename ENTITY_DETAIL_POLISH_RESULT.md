# Witness — Entity Detail polish — Result

Date: 2026-08-19. **Build: 0 errors / 0 warnings.** No git.

## Applied
### A. Bottom padding
- Loaded-branch content padding `.bottom, 40` → **`.bottom, 110`** (clears the Insights tab bar; harmless in the
  graph sheet). Last card no longer clipped.

### B1. Linked memories → dedicated list (bottom section removed)
- Removed the always-visible `linkedMemoriesSection` (+ its `memoryRow`/`memoryRowContent`).
- The **"Linked memories" summary tile** is now a `NavigationLink` → new **`EntityLinkedMemoriesList`** (title +
  count header, reused row style) → tap a memory → `MemoryDetailView` (destination-closure link; works in both
  the graph-sheet stack and the Insights stack).

### Sections tile → scroll + auto-expand (data review)
- **`EDSection` gained an external expand binding** (`expanded: Binding<Bool>?`): when provided it drives
  expansion (and captures the user's manual toggles); otherwise the internal `@State` default is used. This is
  the requested "equivalent scroll-target + open mechanism."
- The page holds `@State forceExpand: Set<String>`; `expandBinding(key)` maps membership ⇄ a section's expansion.
  Every detail section now passes `expanded: expandBinding(key)` and carries `.id(key)`:
  `dialogue` · `across` · `arcs` · `romantic` · each Phase-5 spec key.
- Body wrapped in a `ScrollViewReader`. The **Sections tile** calls `openReview(proxy)` →
  `forceExpand.insert(targetKey)` (**auto-expands**, not just scroll-to-collapsed) + `proxy.scrollTo(targetKey,
  anchor: .top)`, animated. Target = `reviewTargetKey`: first populated **structured** section
  (`across → arcs → romantic → phase-5 specs`), falling back to `dialogue`.
- Both summary tiles show a small chevron to signal tappability.
- The same mechanism is wired for the **dialogue** section (it's externally-expandable + has `.id("dialogue")`),
  so it's the automatic fallback target when no structured section exists; there's no separate dialogue tile to
  trigger it independently.

## Verified
- **BuildProject → 0 errors / 0 warnings**; live diagnostics clean on EntityDetailPage + EntityDetailSupport.
- One fix en route to 0/0: `expandBinding`'s setter used a ternary over `Set.insert`/`remove` (mismatched return
  types) → switched to an `if/else` statement body.

## Honest caveats (device — not runnable here)
- Scroll-to + auto-expand: `scrollTo` targets the section header and `forceExpand` opens it in the same animated
  transaction. On device, if a first-tap ever lands slightly high because layout expands after the scroll, a
  second tap re-centers; verify the feel on a real device (can't run the simulator/tab-bar layout here).
- `EntityLinkedMemoriesList` reuses the existing memory-row → `MemoryDetailView` path (already device-verified in
  earlier phases). Header `date` pill remains provisional pending the still-absent spec.

## No git.
