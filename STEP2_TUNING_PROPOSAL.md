# Witness — Step 2 Tuning Proposal: 1.5× Ring Growth + Widened Controls Row

Status: **PROPOSED — nothing applied yet, awaiting approval.** Touches layout. No git.

## Goal
Increase ring growth to 1.5× (outer scaleBoost 0.42 → 0.63, inner 0.22 → 0.33). At 1.5×
the outer ring peaks near 98pt radius, which would collide with the side controls at the
current `spacing: 28`. Rather than shrink the rings, widen the HStack spacing so the
pause/trash buttons clear the ring's peak with a comfortable margin.

## Geometry math
- Outer ring peak (at level 1.0): `scaleBoost 0.63` → scale `1.63` → radius
  `60 × 1.63 = 97.8pt`. With the 2pt stroke centered on the path (+1pt), visible outer
  edge ≈ **99pt** from the stop-button center.
- Side button near edge from center = `halfStop + spacing = 60 + spacing`.
- Clearance requirement: `60 + spacing ≥ 99 + margin`. For ~13pt margin → `spacing ≥ 52`.

### Proposed `spacing: 52` (was 28)
| Measure | Value |
|---|---|
| Stop button half-width | 60pt |
| Side button half-width | 28pt |
| HStack spacing | 52pt |
| Center-to-side-button center | 60 + 52 + 28 = 140pt |
| Center-to-side-button near edge | 60 + 52 = 112pt |
| Outer ring peak edge (incl. stroke) | ~99pt |
| Clearance at peak loudness | 112 − 99 = ~13pt ✅ |

Inner ring peak (`scaleBoost 0.33`): `60 × 1.33 = 79.8pt` — well inside.

## Screen-width fit (iPhone 17 Pro Max)
- Controls row layout footprint: `56 + 120 + 56 + 2×52 = 336pt`. The ring bloom is a
  `scaleEffect` overflow — purely visual, does NOT enlarge the layout.
- iPhone 17 Pro Max ≈ 440pt wide (6.9" class; also fine on the 430pt Pro Max generation).
  336pt centered row → ~52pt per side (~47pt on 430pt). No edge crowding.
- Row is centered; stop button at screen center; ring bloom reaches only ~99pt from
  center vs ~220pt screen half-width — rings never approach the edges.

## Proposed diff — RecordView.swift

### (a) Widen the recording controls row (line 96)
```diff
             if recorder.isRecording {
-                HStack(spacing: 28) {
+                HStack(spacing: 52) {
                     secondaryControl(recorder.isPaused ? "play.fill" : "pause.fill") { togglePause() }
```

### (b) 1.5× ring growth in LevelPulse (scaleBoost only)
```diff
         ZStack {
-            ring(scaleBoost: 0.42, base: 0.05, gain: 0.12)   // outer: larger, fainter
-            ring(scaleBoost: 0.22, base: 0.09, gain: 0.20)   // inner: tighter, stronger
+            ring(scaleBoost: 0.63, base: 0.05, gain: 0.12)   // outer: larger, fainter (1.5×)
+            ring(scaleBoost: 0.33, base: 0.09, gain: 0.20)   // inner: tighter, stronger (1.5×)
         }
```

Unchanged: stroke `lineWidth: 2`, opacity ramps (base/gain), `.easeOut(0.22)`,
`.allowsHitTesting(false)`, base 120pt ring size, button level-scale (1.0→~1.06).

## After approval
Apply both hunks → build → report 0 errors / 0 warnings honestly. Haptics still not
verifiable in Simulator (no Taptic hardware).
