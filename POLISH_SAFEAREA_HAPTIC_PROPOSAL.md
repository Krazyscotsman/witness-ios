# Witness — Polish: Bottom-button safe area (Fix 1) + Tab haptic (Fix 2)

Status: **PROPOSED — nothing applied. Awaiting approval (scope choice on Fix 1).** No git.

## Fix 2 — tab bar has no haptic (how it works)
`MainTabView` holds `@State tab: Tab`; `WitnessTabBar` has `@Binding selection`. Each tab is
`Button { selection = t }` — plain assignment, no haptic. The bar is hosted via
`.safeAreaInset(edge: .bottom)` (the correct clear-the-indicator pattern).

### Fix 2 diff — MainTabView.swift
```diff
             ForEach(MainTabView.Tab.allCases, id: \.self) { t in
                 let sel = (t == selection)
-                Button { selection = t } label: {
+                Button {
+                    if t != selection { Haptics.tap() }   // light tick only on an actual switch
+                    selection = t
+                } label: {
```
Light `.tap()` only; fires only when switching to a different tab; reuses existing Haptics
enum; never the .medium/.heavy record cues.

## Fix 1 — bottom-button clipping

### Inventory (all full-width primary buttons use FIXED bottom padding; none safe-area-aware)
| Screen | Button | Bottom handling | Container |
|---|---|---|---|
| OnboardingView | Continue | .padding(.bottom, 20) | last child of VStack (topBar/ScrollView/button) |
| OnboardingView | Begin your witness | .padding(.bottom, 24) | VStack w/ Spacers, NO ScrollView |
| RecordView (saved) | Done | .padding(.bottom, 24) | VStack w/ Spacers, NO ScrollView |
| RecordView (type) | Save memory | VStack .padding(.bottom, 16) | typeMode VStack |
| SettingsView | bottom button | .padding(.bottom, 20) | — |
| AnchorsView | bottom button | .padding(.bottom, 20) | — |
| MemoirView | bottom button | .padding(.bottom, 20) | — |
| EntityAtlasView | bottom button | .padding(.bottom, 16) | — |
| LoginView / ThresholdView | entry CTA | .padding(.bottom, 40 / 44) | larger, likely already clears indicator |

Tab-bar screens (Home/Memories/etc.) are fine — MainTabView gives them a `.safeAreaInset`
bottom inset. The clip-prone class = full-screen flows WITHOUT that inset. Worst offenders:
the two Spacer-based screens (Begin, Done) with no ScrollView — content can overflow the
frame and push the button under the home indicator on short screens.

### Honest mechanism caveat
Static reading confirms the shared pattern but does NOT definitively prove the exact clip
cause (SwiftUI `ZStack { ParchmentBackground(); content }` should keep content in the safe
area; likeliest real cause is Spacer-overflow on the no-ScrollView screens + small fixed
paddings). The device is the proof.

### Recommended fix (robust regardless of cause)
Host each primary bottom button in `.safeAreaInset(edge: .bottom)` — the same proven
pattern the tab bar uses — so the button is always laid out above the home indicator.
Keep the button's look; drop the redundant fixed `.padding(.bottom, N)` and keep a small gap.

### Example diff — OnboardingView "Continue"
```diff
                 VStack(spacing: 0) {
                     topBar
                     ScrollView(showsIndicators: false) {
                         stepContent
                             ...
                     }
-                    bottomButton
                 }
+                .safeAreaInset(edge: .bottom) { bottomButton }
```
```diff
     private var bottomButton: some View {
         Button { advance() } label: { ... }
         .witnessPress()
         .disabled(!canAdvance)
-        .padding(.horizontal, 24).padding(.bottom, 20).padding(.top, 4)
+        .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 8)
     }
```
Same shape for "Begin", RecordView "Done", then Settings/Anchors/Memoir/EntityAtlas.

### Scope question
(a) Apply to the 3 named (Continue, Begin, Done) first → verify on device → roll the rest, OR
(b) apply to the whole class in one pass now.
Recommended: (a), because the cause is only confirmed by the device test.

## After approval
Apply chosen scope → build 0/0 → report honestly. Haptics verified on device only
(Simulator has no Taptic hardware).
