# Witness — Scroll-content bottom inset: full class

Status: **PROPOSED — nothing applied. Awaiting approval + Home decision.** No git.

## Key finding: NavigationStack is the discriminator
The tab bar's `safeAreaInset` (MainTabView) does NOT reach the ScrollView content of the
NavigationStack-wrapped tab screens — which is why Insights clips at 28pt. Non-NavStack
tab screens (Home, Talk) apparently DO receive it (never reported clipping).

| Screen | NavigationStack? | Reported clip? | Reading |
|---|---|---|---|
| Insights | Yes | Yes (confirmed) | inset blocked → needs explicit padding |
| Memories | Yes | no (but same structure, list grows) | same bug |
| You | Yes | no (short list) | same bug if it scrolls |
| Home | No | no | inset likely reaches it → NOT the bug |
| Talk | No | no | pinned composer; inset likely reaches it |

## TalkView analysis — different pattern, do NOT force the fix
`ZStack { ParchmentBackground(); VStack(spacing:0){ header; conversation(ScrollView); composer } }`.
The composer is a PINNED bottom bar (own parchment bg + top divider), not scrolling content.
This is a chat-composer layout, not a clipping-list. Not this bug; leave it.

## Proposed fixes — NavStack tab screens → .bottom 110

### InsightsView.swift
```diff
                     .padding(.horizontal, 24)
                     .padding(.top, 16)
-                    .padding(.bottom, 28)
+                    .padding(.bottom, 110)
```

### MemoriesView.swift
```diff
                         .padding(.horizontal, 24)
                         .padding(.top, 16)
-                        .padding(.bottom, 24)
+                        .padding(.bottom, 110)
```

### YouView.swift
```diff
                     .padding(.horizontal, 24)
                     .padding(.top, 24)
-                    .padding(.bottom, 28)
+                    .padding(.bottom, 110)
```
YouView "Sign out" check: VStack is top-aligned (no Spacer), so bottom padding only adds
scroll space BELOW Sign out — it stays at its natural position under the Settings row,
fully reachable, does not float higher.

## HomeView — recommendation: DO NOT blindly apply 110
Home has no NavigationStack, so its ScrollView already gets the tab-bar inset (why it
wasn't reported clipping). Adding 110 on top would double-pad: in the tall `.ready` state,
scrolling to the bottom would leave a large dead gap below the button ("floating too high").
Recommendation: leave Home at 40, verify on device; bump modestly only if `.ready` clips.
Alternative if you prefer safe-over-sorry: a smaller bump (e.g. 60) rather than 110.
(Caveat: NavStack theory is structural inference, not an observed run — Home is the one to eyeball.)

## After approval
Apply Insights + Memories + You (110); Home per your decision; Talk excluded.
Build 0/0, report honestly.
