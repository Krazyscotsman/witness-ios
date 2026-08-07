# Witness — Step 2 Result: Live Input-Level Meter + Record Haptics

Date: 2026-08-07

## Summary
Applied the approved Step 2 diffs (with the crisp stroked-ring revision — no blur, no
glow). The record screen now shows two concentric teal rings that breathe around the
stop button driven by `recorder.level`, the stop button scales subtly with level, and
firm/lighter haptics fire on true record start/stop. No change to `AudioRecorder` or to
how `level` is computed. No git.

## Final build result
`The project built successfully.` (Xcode BuildProject, 0 errors)

- `RecordView.swift` — diagnostics: **no issues** (clean).
- `Hints.swift` — diagnostics: **no issues** (clean).

**0 errors, 0 warnings.**

## What changed
- `Hints.swift` (additive): `Haptics.recordStart()` = `.heavy`, `Haptics.recordStop()`
  = `.medium`, matching the existing `tap()` style (create generator → `impactOccurred()`).
- `RecordView.swift`:
  - `body`: `.onChange(of: recorder.isRecording)` fires `Haptics.recordStart()` only when
    recording truly begins (after permission + `record()`), not on button touch.
  - `speakMode`: the stop button is wrapped in a `ZStack` with `LevelPulse(level:)`
    behind it, and scales `1.0 → ~1.06` with level, eased `.easeOut(0.22)`.
  - `stopRecording()`: fires `Haptics.recordStop()` (stop path only — not cancel/trash).
  - New private `LevelPulse` view: two `Circle().stroke(WV.teal, lineWidth: 2)` rings
    (outer larger/fainter: scaleBoost 0.42, opacity 0.05→0.17; inner tighter/stronger:
    scaleBoost 0.22, opacity 0.09→0.29), eased `.easeOut(0.22)`, `.allowsHitTesting(false)`.
    No blur anywhere.

## Ring rests when paused — confirmed (by data-flow trace)
On pause, `AudioRecorder.pauseRecording()` sets `level = 0` (from Step 1). `LevelPulse`
and the button scale are pure functions of `recorder.level`, so at `level == 0` the rings
sit at scale 1.0 with only their faint base opacity (outer 0.05 / inner 0.09) and the
button scale is exactly 1.0 — i.e. a static, non-pulsing rest. This is deterministic from
the code path.

## Honest testing scope
- Verified: clean compile (diagnostics on both files) and a successful full build.
- Ring-rests-on-pause: confirmed by tracing the state → view data flow (level → 0 on
  pause drives the rest), **not** via an interactive Simulator session.
- The meter animation *feel* (breathing against live mic) was **not** run interactively
  here; it can be exercised in the Simulator since it uses the Mac's mic.
- **Haptics were NOT verified.** The Simulator has no Taptic hardware, so
  `impactOccurred()` is a no-op there. The `.heavy` start and `.medium` stop cues can only
  be confirmed on a real device later.

## Not done (as instructed)
- No git operations.
- No change to timer, Speak/Type switcher, layout structure, saved screen, level math.
- No playback. No reduce-motion gate (was flagged as optional; not added).
