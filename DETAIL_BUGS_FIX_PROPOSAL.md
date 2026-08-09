# Witness — Detail bugs fix proposal (#1/#2 peopleChips, #3 pop-to-root)

Status: **PROPOSED — nothing applied. Awaiting approval.** No git.

## Fix #1/#2 — wrapping peopleChips
FlowLayout (SwiftUI Layout, iOS 16+) so chips wrap onto multiple lines; lineLimit(1) on each name.
No cap — all people show. FlowLayout returns width ≤ proposed, so the people row can't exceed the
content column → column stays screen-width → title/narrative stop overflowing (Fix #2 guaranteed).

### MemoryDetailView.swift
```diff
     private var peopleChips: some View {
-        HStack(spacing: 8) {
+        FlowLayout(spacing: 8, lineSpacing: 8) {
             ForEach(memory.people, id: \.self) { p in
                 HStack(spacing: 6) {
                     Image(systemName: "person.fill").font(.system(size: 12)).foregroundStyle(WV.teal)
                     Text(p).font(.system(size: 15, weight: .medium)).foregroundStyle(WT.ink.opacity(0.8))
+                        .lineLimit(1)
                 }
                 .padding(.horizontal, 13).padding(.vertical, 8)
                 .background(WV.teal.opacity(0.10), in: Capsule())
             }
         }
     }
```
New FlowLayout (bottom of MemoryDetailView.swift):
```swift
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, usedWidth: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            let w = min(s.width, maxWidth)
            if x > 0 && x + w > maxWidth { y += lineHeight + lineSpacing; x = 0; lineHeight = 0 }
            x += w + spacing
            lineHeight = max(lineHeight, s.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return CGSize(width: usedWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            let w = min(s.width, maxWidth)
            if x > bounds.minX && x + w > bounds.minX + maxWidth { y += lineHeight + lineSpacing; x = bounds.minX; lineHeight = 0 }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: s.height))
            x += w + spacing
            lineHeight = max(lineHeight, s.height)
        }
    }
}
```

## Fix #3 — pop-to-root on active-tab re-tap (Memories)
Own the Memories NavigationStack path in MainTabView (survives tab switches); clear on re-tap of the
active tab. Haptic-on-change kept. Behavior change (intended): switching tabs now PRESERVES the
Memories detail; re-tapping the Memories tab pops to root.

### MemoriesView.swift
```diff
     @ObservedObject var vm: MemoriesViewModel
     @ObservedObject var auth: AuthManager
+    @Binding var path: NavigationPath
     ...
-        NavigationStack {
+        NavigationStack(path: $path) {
```

### MainTabView.swift
```diff
     @StateObject private var memoriesVM = MemoriesViewModel()
+    @State private var memoriesPath = NavigationPath()
```
```diff
-            case .memories: MemoriesView(vm: memoriesVM, auth: auth)
+            case .memories: MemoriesView(vm: memoriesVM, auth: auth, path: $memoriesPath)
```
```diff
-            WitnessTabBar(selection: $tab)
+            WitnessTabBar(selection: $tab, onReselect: { reselected in
+                if reselected == .memories { memoriesPath = NavigationPath() }
+            })
```
```diff
 private struct WitnessTabBar: View {
     @Binding var selection: MainTabView.Tab
+    var onReselect: (MainTabView.Tab) -> Void
     ...
                 Button {
-                    if t != selection { Haptics.tap() }
-                    selection = t
+                    if t == selection { onReselect(t) }
+                    else { Haptics.tap(); selection = t }
                 } label: {
```

## Other tabs (noted, not fixed — Memories priority)
InsightsView (pushes Anchors/Timeline/Memoir/…) and YouView (pushes Settings) own internal
implicit-path NavigationStacks → same re-tap-doesn't-pop behavior. Home/Talk don't push. Offer to
apply the same treatment in a follow-up.

## After approval
Apply both; build 0/0; report; confirm content column is width-constrained (title/narrative no longer
overflow) and Memories re-tap pops to root. No git.
