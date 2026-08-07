# Witness — Lock App to Light Appearance (proposal)

Status: **PROPOSED — awaiting approval on placement before applying.** No git. No color changes.

## Root location (verified)
`@main struct WitnessApp` (WitnessApp.swift:10). Its `WindowGroup` root view is
`ContentView()` (line 14) — the true app root hosting all screens. The modifier goes on
the WindowGroup's content so it drives the WINDOW's resolved color scheme (this is what
forces the system date-picker wheel and presented surfaces to light — not screen-by-screen).

## Proposed diff — WitnessApp.swift (one line)
```diff
     var body: some Scene {
         WindowGroup {
             ContentView()
+                .preferredColorScheme(.light)
         }
     }
```

## Propagation analysis
Root `.preferredColorScheme(.light)` sets the window interface style; iOS presents these
in the same UIWindowScene and inherits it:
- fullScreenCover (record screen) — inherits.
- sheet (legal, etc.) — inherits.
- SwiftUI DatePicker wheel — inherits (the key previously-broken control).
- .alert / .popover (mic alert, hint callouts) — inherit.
- UIViewControllerRepresentable UIKit controllers (e.g. UIImagePickerController) — inherit
  traits from the presenting controller.

### Honest caveat
`PHPickerViewController` (modern Photos picker, if used by MediaCapture) runs
out-of-process and always follows the SYSTEM appearance; `preferredColorScheme` cannot
override it. Its own chrome may still look dark in device dark mode. That's Apple's UI,
not our parchment design, and not among the reported-broken screens (birthdate wheel,
origin fields, memory-date fields). Flagged so it's not a surprise.

## After approval
Apply the one line → build 0 errors / 0 warnings → report honestly.
Real proof is on-device: with the iPhone kept in dark mode, walk the onboarding birthdate
wheel, origin fields, and memory-date field and confirm they're readable.

## Follow-ups noted (not part of this change)
- Commit the device-testing checkpoint after the light fix is verified on-device.
- Clipped Continue button (safe-area layout bug on device).
- Audio memos not appearing in the gallery (unbuilt connection, not a break).
