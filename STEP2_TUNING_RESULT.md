# Witness — Step 2 Tuning Result: 1.25× Rings + Matched Spacing

Date: 2026-08-07

## Applied (RecordView.swift only)
- Recording controls `HStack(spacing: 28 → 42)`.
- `LevelPulse` scaleBoost: outer `0.42 → 0.525`, inner `0.22 → 0.275` (1.25× growth).
- Unchanged in `LevelPulse`: stroke `lineWidth: 2`, opacity ramps (base/gain),
  `.easeOut(0.22)`, base 120pt ring size, `.allowsHitTesting(false)`, button level-scale.

## Collision check (confirmed)
| Measure | Value |
|---|---|
| Outer ring peak (60 × 1.525 + 1pt stroke) | ~92.5pt |
| Side-button near edge (60 + 42) | 102pt |
| Clearance at peak loudness | ~9.5pt ✅ |

Row footprint: `56 + 120 + 56 + 2×42 = 316pt`. On iPhone 17 Pro Max (~440pt wide) that
leaves ~62pt per side — centered, uncrowded. Ring bloom reaches only ~92.5pt from the
centered stop button vs ~220pt screen half-width.

## Build result
`The project built successfully.` — 0 errors.
`RecordView.swift` diagnostics: no issues.
**0 errors, 0 warnings.**

## Honest testing scope
- Verified: clean compile + successful full build; geometry confirmed by calculation.
- Not run interactively; the live breathing feel can be exercised in the Simulator via
  the Mac mic.
- Haptics NOT verified — Simulator has no Taptic hardware (`impactOccurred()` is a no-op
  there); confirm on a real device later.

No git.
