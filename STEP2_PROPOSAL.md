# Witness — Step 2 Proposal: Live Input-Level Meter + Record Haptics

Status: **PROPOSED — nothing applied yet, awaiting approval.**

Scope: `RecordView.swift` (meter visuals + haptic wiring) plus a small additive edit to
`Hints.swift` (two new `Haptics` methods). No change to `AudioRecorder` and no change to
how `level` is computed. Out of scope: timer, Speak/Type switcher, layout structure,
saved screen, level math, playback. No git.

---

## What I found in Hints.swift (existing haptic pattern)
- A central **`Haptics` enum** (Hints.swift:93–101):
  - `Haptics.tap()` → `UIImpactFeedbackGenerator(style: .light).impactOccurred()`
  - `Haptics.success()` → `UINotificationFeedbackGenerator().notificationOccurred(.success)`
- Pattern: create a generator, call `impactOccurred()` — no `prepare()`, no stored
  generator. Comment notes it is a **no-op on devices without a haptic engine**.
- `WitnessPressStyle` (the `.witnessPress()` used by every button, incl. mic/stop/trash)
  already fires `Haptics.tap()` on press-down. So the stop/trash buttons already get a
  light tap on touch; the new start/stop cues are distinct, on top of that.

---

## Design decisions
- **Meter = a level-reactive "breath," not sonar pings.** Two concentric teal halos sit
  behind the stop button; their size and opacity are functions of the eased
  `recorder.level`. Loud → they bloom outward and brighten; silence → they nearly rest;
  paused → `recorder.level` is already 0 (Step 1 sets it on pause), so they settle to
  rest with no extra logic. No repeating/strobe animation.
- **Smoothing:** `.easeOut(duration: 0.22)` keyed to `recorder.level` eases each ~10 Hz
  update toward the new value instead of snapping — kills frame-to-frame jitter while
  staying calm.
- **Button "alive" cue:** the stop button scales `1.0 → ~1.06` across silence→loud.
  Subtle secondary cue.
- **Haptics location:** kept entirely in the view — no `AudioRecorder` change needed.
  Start fires via `.onChange(of: recorder.isRecording)` (true only after permission +
  `record()`), stop fires in the view's `stopRecording()` path (not on cancel/trash, so
  stop vs. discard stay distinct). Helpers added to the existing `Haptics` enum to match
  the app pattern (the one edit outside RecordView — purely additive).
- **Not included (to keep scope tight):** a `reduce-motion` accessibility gate. Easy to
  add if wanted.

---

## Diff 1 — `Hints.swift` (additive only: two new `Haptics` methods)
```diff
     static func tap() {
         let g = UIImpactFeedbackGenerator(style: .light)
         g.impactOccurred()
     }
+    static func recordStart() {
+        let g = UIImpactFeedbackGenerator(style: .heavy)
+        g.impactOccurred()
+    }
+    static func recordStop() {
+        let g = UIImpactFeedbackGenerator(style: .medium)
+        g.impactOccurred()
+    }
     static func success() {
         UINotificationFeedbackGenerator().notificationOccurred(.success)
     }
```

## Diff 2 — `RecordView.swift`

### (a) `body`: fire the start haptic on the real recording transition (after the alert modifier, lines 47–50)
```diff
         } message: {
             Text("Allow microphone access in Settings to record a voice memory.")
         }
+        .onChange(of: recorder.isRecording) { _, isRecording in
+            // Firm cue only when capture truly begins (after permission + record()),
+            // never on the button touch. The stop cue fires in stopRecording().
+            if isRecording { Haptics.recordStart() }
+        }
     }
```

### (b) `speakMode`: wrap the stop button with the pulse + level scale (lines 95–100)
```diff
             if recorder.isRecording {
                 HStack(spacing: 28) {
                     secondaryControl(recorder.isPaused ? "play.fill" : "pause.fill") { togglePause() }
-                    micButton(systemName: "stop.fill") { stopRecording() }
+                    ZStack {
+                        LevelPulse(level: recorder.level)
+                        micButton(systemName: "stop.fill") { stopRecording() }
+                            .scaleEffect(1.0 + 0.06 * recorder.level)
+                            .animation(.easeOut(duration: 0.22), value: recorder.level)
+                    }
                     secondaryControl("trash") { cancelRecording() }
                 }
             } else {
```

### (c) `stopRecording()`: fire the stop haptic (lines 210–214)
```diff
     private func stopRecording() {
         // Audio file is at recorder.lastRecordingURL; backend owns upload/transcription.
+        Haptics.recordStop()
         recorder.stopRecording()
         withAnimation { saved = true }
     }
```

### (d) New private view at the end of the file (after `ModeSwitcher`, line 258)
```diff
         .padding(4)
         .background(WT.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
     }
 }
+
+// MARK: - Live input-level pulse (breathes around the stop button, driven by recorder.level).
+private struct LevelPulse: View {
+    var level: Double   // 0…1; eased by the parent's .animation on recorder.level
+
+    var body: some View {
+        ZStack {
+            halo(scaleBoost: 0.42, base: 0.05, gain: 0.12, blur: 7)   // outer: larger, fainter
+            halo(scaleBoost: 0.22, base: 0.09, gain: 0.20, blur: 3)   // inner: tighter, stronger
+        }
+        .animation(.easeOut(duration: 0.22), value: level)
+        .allowsHitTesting(false)
+    }
+
+    private func halo(scaleBoost: CGFloat, base: Double, gain: Double, blur: CGFloat) -> some View {
+        Circle()
+            .fill(WV.teal)
+            .frame(width: 120, height: 120)
+            .scaleEffect(1.0 + scaleBoost * CGFloat(level))
+            .opacity(base + gain * level)
+            .blur(radius: blur)
+    }
+}
```

Geometry note: max outer halo radius at level 1.0 is `60 × 1.42 ≈ 85pt`, inside the ~88pt
gap to the side controls, so even at peak loudness the bloom doesn't collide with the
pause/trash buttons. It's also `.allowsHitTesting(false)` so it never intercepts taps.

---

## What will be verified after approval
1. Build → report **0 errors / 0 warnings** honestly (diagnostics on both files + full build).
2. **Meter** is visually verifiable in the Simulator (it uses the Mac's mic, so `level`
   responds to real input) — confirm it breathes and rests when paused.
3. **Haptics: NOT claimed to work from a Simulator run** — the Simulator has no Taptic
   hardware, so `impactOccurred()` is a no-op there. Start/stop haptics can only be
   confirmed on a real device later.
