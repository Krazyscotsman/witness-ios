# Witness — Scroll-content bottom inset: InsightsView fix + tab-screen inventory

Status: **PROPOSED — nothing applied. Awaiting approval + scope decision.** No git.

## Bug
InsightsView's scrolling hub list clips its last row ("Media") under the tab bar.
Not a pinned-button issue — it's scroll-content under-padding.

## InsightsView structure
`NavigationStack → ZStack { ParchmentBackground(); ScrollView { VStack(spacing:14) {
header; ExplainFeatureCard; ForEach(InsightItem.others = Timeline, Memoir, Learn, Anchors,
Graph, Media) } .padding(.horizontal,24).padding(.top,16).padding(.bottom, 28) } }`.
Only 28pt bottom padding; tab bar (~70pt) + home indicator exceed that → last row clipped.
The tab-bar `.safeAreaInset` from MainTabView is NOT insetting this ScrollView's content
(the pushed children in the same NavigationStack compensate with `.padding(.bottom, 110)`).

## Proposed fix — InsightsView.swift
```diff
                     .padding(.horizontal, 24)
                     .padding(.top, 16)
-                    .padding(.bottom, 28)
+                    .padding(.bottom, 110)
```
110 matches this screen's own pushed sub-screens (Anchors/Timeline/EntityAtlas = 110),
the proven value that clears the tab bar in this NavigationStack context.

## Inventory — same pattern (report only; not fixing yet)
Tab-root screens (sit above MainTabView's tab bar):
| Screen | Structure | Bottom padding | Last item | Risk |
|---|---|---|---|---|
| InsightsView | NavStack + ScrollView/VStack | 28 | "Media" row | Confirmed bug (fixing) |
| MemoriesView | NavStack + ScrollView/LazyVStack | 24 | last memory card | High — same bug |
| HomeView | ScrollView/VStack (no NavStack) | 40 | primary button | Moderate — scrolls in learning/ready states |
| YouView | NavStack + ScrollView/VStack | 28 | Sign out button | Low–moderate — usually fits, clips if it scrolls |
| TalkView | not fully analyzed | — | pinned composer? | Needs check — likely different pattern |

Not in this class:
- Pushed sub-screens (Anchors/Settings/Memoir/Timeline/Learn/EntityAtlas/MemoryDetail):
  already use .padding(.bottom, 110–120) — handled.
- MediaView: presented as .fullScreenCover (tab bar not shown over it); its .bottom 90/110
  clears its own pinned selection bar + indicator. Not at risk from the tab bar.

True same-bug set: Insights (fixing), Memories, Home, You; Talk to verify.

## After approval
Apply the InsightsView one-liner → build 0/0 → report honestly. Then you decide scope for
Memories/Home/You/Talk.
