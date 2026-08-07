# Witness — Polish v2: Bottom-button safe area (Fix 1, corrected scope) + Tab haptic (Fix 2)

Status: **PROPOSED — nothing applied. Scope corrected from v1; awaiting confirmation.** No git.

## Scope correction (important)
On close reading, 5 of the 9 v1 grep hits are NOT pinned bottom buttons and are excluded:
- SettingsView `.bottom,20` = datePickerSheet "Done" (sheet, fixed detent) — EXCLUDE.
- AnchorsView `.bottom,20` = AnchorFormView.dateSheet "Done" (sheet) — EXCLUDE.
- MemoirView = "Generate" scrolls inside ScrollView (.bottom,120); grep hit was yearPickerSheet — EXCLUDE.
- EntityAtlasView `.bottom,16` = confirmSheet (sheet) — EXCLUDE.
- LoginView `.bottom,40` = scroll content; buttons scroll, never pinned — EXCLUDE.
Converting sheet buttons to safeAreaInset would break their detents — do not touch them.

ThresholdView "Enter" is pinned but uses `.bottom, 44` (> ~34pt indicator) so it already
clears — LEAVE per instruction (can convert for consistency if desired).

### True class (pinned, non-scrolling, full-width bottom buttons; full-screen flows)
1. OnboardingView "Continue"        (.bottom, 20)
2. OnboardingView "Begin your witness" (.bottom, 24; VStack+Spacers, no scroll)
3. RecordView savedView "Done"      (.bottom, 24; VStack+Spacers, no scroll)
4. RecordView typeMode "Save memory" (.bottom, 16; pinned under maxHeight .infinity TextEditor)

Fix 1 touches only OnboardingView + RecordView.

## Fix 1 — pattern
Move the button into `.safeAreaInset(edge: .bottom) { … }` (the tab bar's proven pattern);
change trailing `.padding(.bottom, N)` → `.padding(.bottom, 10)` (safe area gives indicator
clearance). Keep horizontal 24 and any top padding.

### Diff A — OnboardingView "Continue"
```diff
                 VStack(spacing: 0) {
                     topBar
                     ScrollView(showsIndicators: false) {
                         stepContent
                             .padding(.horizontal, 28)
                             .padding(.top, 8)
                             .padding(.bottom, 24)
                             .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity))
                             .id(step)
                     }
-                    bottomButton
                 }
+                .safeAreaInset(edge: .bottom) { bottomButton }
```
```diff
     private var bottomButton: some View {
         Button { advance() } label: { … }
         .witnessPress()
         .disabled(!canAdvance)
-        .padding(.horizontal, 24).padding(.bottom, 20).padding(.top, 4)
+        .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 10)
     }
```

### Diff B — OnboardingView "Begin your witness"
```diff
     private var completionView: some View {
         VStack(spacing: 18) {
             Spacer(minLength: 16)
             CompassMark(color: WV.gold).frame(width: 56, height: 56)
             Text(...welcome...) …
             Text("It's good to finally be here with you. …") …
             Spacer(minLength: 16)
             agreementCard.padding(.horizontal, 24)
-
-            Button {
-                onFinish()
-            } label: {
-                Text("Begin your witness") …
-            }
-            .witnessPress()
-            .disabled(!allAgreed)
-            .padding(.horizontal, 24).padding(.bottom, 24)
         }
         .padding(.horizontal, 24)
+        .safeAreaInset(edge: .bottom) {
+            Button { onFinish() } label: {
+                Text("Begin your witness")
+                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
+                    .frame(maxWidth: .infinity).frame(height: 56)
+                    .background(allAgreed ? WV.teal : WV.teal.opacity(0.4),
+                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
+                    .shadow(color: WV.teal.opacity(allAgreed ? 0.3 : 0), radius: 10, y: 6)
+            }
+            .witnessPress()
+            .disabled(!allAgreed)
+            .padding(.horizontal, 24).padding(.bottom, 10)
+        }
         .sheet(item: $legalDoc) { LegalView(doc: $0) }
     }
```

### Diff C — RecordView savedView "Done"
```diff
     private var savedView: some View {
         VStack(spacing: 18) {
             Spacer()
             ZStack { … check … }.frame(width: 90, height: 90)
             Text("Saved").font(.serif(30)).foregroundStyle(WV.teal)
             Text("\(companion) is finding its shape.") …
             if recorder.lastRecordingURL != nil {
                 playbackBar.padding(.top, 6)
             }
             Spacer()
-            Button { dismiss() } label: {
-                Text("Done") …
-            }
-            .witnessPress()
-            .padding(.horizontal, 24).padding(.bottom, 24)
         }
         .padding(.horizontal, 24)
+        .safeAreaInset(edge: .bottom) {
+            Button { dismiss() } label: {
+                Text("Done")
+                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
+                    .frame(maxWidth: .infinity).frame(height: 54)
+                    .background(WV.teal, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
+            }
+            .witnessPress()
+            .padding(.horizontal, 24).padding(.bottom, 10)
+        }
         .onAppear {
             if let url = recorder.lastRecordingURL { audioPlayer.load(url) }
         }
         .onDisappear { audioPlayer.stop() }
     }
```

### Diff D — RecordView typeMode "Save memory"
```diff
     private var typeMode: some View {
         VStack(alignment: .leading, spacing: 14) {
             field("Title (optional)", text: $title)
             field("When was this? (optional)", text: $dateText, hint: "…")
             Text("YOUR WORDS") …
             ZStack(alignment: .topLeading) { … TextEditor … }
             .frame(maxWidth: .infinity, maxHeight: .infinity)
             .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
             .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.12), lineWidth: 1))
-
-            Button { saveMemory() } label: {
-                Text("Save memory") …
-            }
-            .witnessPress()
-            .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
         }
-        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 16)
+        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 8)
+        .safeAreaInset(edge: .bottom) {
+            Button { saveMemory() } label: {
+                Text("Save memory")
+                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
+                    .frame(maxWidth: .infinity).frame(height: 54)
+                    .background(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? WV.teal.opacity(0.4) : WV.teal,
+                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
+            }
+            .witnessPress()
+            .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
+            .padding(.horizontal, 24).padding(.bottom, 10)
+        }
     }
```

## Fix 2 — MainTabView tab haptic
```diff
             ForEach(MainTabView.Tab.allCases, id: \.self) { t in
                 let sel = (t == selection)
-                Button { selection = t } label: {
+                Button {
+                    if t != selection { Haptics.tap() }   // light tick only on an actual switch
+                    selection = t
+                } label: {
```

## Visual-check caveats (verify after applying)
- Screens that already cleared shift the button down ~10pt (gap 20/24 → safeArea+10). Tunable.
- typeMode "Save": confirm TextEditor still fills and button floats above the keyboard.
- Begin/Done Spacer-VStacks: button now pinned (strictly better); middle content could be
  tight on very short screens since those aren't scrollable (separate concern, out of scope).

## After confirmation
Apply the 4 Fix-1 conversions + Fix 2 → build 0/0 → report honestly. Haptics verified on
device only (Simulator has no Taptic hardware); clipping visible in Simulator frames, phone
is the real proof.
