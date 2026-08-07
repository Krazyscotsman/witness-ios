# Witness — Step 1 Handoff (for browser Claude)

## What was done
1. **Retain-cycle fix** in `AudioRecorder.swift` `startTimer()` — `[weak self]` moved to the
   outer `Timer` closure, breaking the cycle
   (self → meterTimer → Timer → closure → self) that would leak the recorder on a
   mid-recording teardown.
2. **Caught and fixed a misplaced file:** `AudioRecorder.swift` had been written one
   directory too deep (a stray nested `Witness/Witness/Witness/` folder). It compiled
   only because Xcode's synchronized group recurses. It was moved to
   `Witness/Witness/AudioRecorder.swift` alongside the other sources, and the empty
   stray folder was removed.
3. **RecordView wiring applied** exactly as approved, with `import Combine` dropped and
   `import UIKit` added (Combine kept in `AudioRecorder.swift`).

## Build result (authoritative)
`The project built successfully.` — 0 errors.

- `RecordView.swift`: no issues (clean).
- `AudioRecorder.swift`: 1 warning, verbatim:
```
[Warning] [Line: 209] Reference to captured var 'self' in concurrently-executing code; this is an error in the Swift 6 language mode
```

Per instruction I did NOT revert — kept the requested outer-`[weak self]` form and am
reporting the warning as-is. It is a warning (not an error) in this project's Swift 5
language mode, so the build passes.

A form that is BOTH cycle-free AND warning-free is available and can be applied on
request:
```swift
let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
    guard let self else { return }
    Task { @MainActor in self.tick() }
}
```

## Files saved
- `Witness/Witness/AudioRecorder.swift` (new, relocated to correct dir)
- `Witness/Witness/RecordView.swift` (wiring only)
- `STEP1_RESULT.md` (repo root) — full result detail
- `RecordView-wiring-proposal.md` (repo root) — the approved wiring diff + full recorder source

No git operations were run.

## Open decision for review
Do you want the both-clean Timer form applied (removing the lingering
"error in Swift 6 language mode" warning), or leave the currently-applied
outer-`[weak self]` form as-is?
