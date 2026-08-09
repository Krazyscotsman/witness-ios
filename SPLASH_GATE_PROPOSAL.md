# Witness — Branded launch splash / auth-validation gate — Proposal

Status: **PROPOSED — nothing applied. Awaiting approval + circle-style choice.** No git.

## Read-first
- WitnessApp hosts ContentView (+ .preferredColorScheme(.light)). ContentView is the decider.
- ContentView Route { launching, threshold, login, onboarding, main }, starts .launching.
  bootstrapAndValidate() runs in ContentView.task and flips the route the INSTANT auth resolves.
- .launching currently shows a bare placeholder (ParchmentBackground + CompassMark), no timing/
  animation → the flash risk.
- Integration: splash goes in the .launching case; routing moves from "immediately on auth resolve"
  to "on splash completion (min ~3s AND auth resolved)". Existing auth routing otherwise untouched.

## Timing (crux)
Splash completes only when BOTH minElapsed (~3s) AND isAuthResolved. The 3s timer only flips a
@State; the decision runs via onChange(minElapsed)+onChange(isAuthResolved) → tryResolve(), reading
CURRENT values (avoids stale-capture from reading isAuthResolved inside the detached sleep Task).
Cases: auth-fast → wait to 3s; auth-slow → hold past 3s; no-token → fast false but still full 3s →
login; valid → app.

## SplashView.swift (full source)
```swift
import SwiftUI

struct SplashView: View {
    let isAuthResolved: Bool
    var onComplete: () -> Void

    @State private var circleScale: CGFloat = 0.15
    @State private var minElapsed = false
    @State private var resolving = false
    @State private var didComplete = false

    var body: some View {
        ZStack {
            WV.parchment.ignoresSafeArea()

            Circle()
                .fill(WV.teal.opacity(0.12))                 // flat teal, no glow
                .frame(width: 260, height: 260)
                .scaleEffect(circleScale)

            Text(resolving ? "Now." : "Your story begins…")
                .font(.serif(resolving ? 40 : 26))
                .foregroundStyle(WV.teal)
                .contentTransition(.opacity)
                .multilineTextAlignment(.center)
        }
        .onAppear(perform: begin)
        .onChange(of: minElapsed) { _, _ in tryResolve() }
        .onChange(of: isAuthResolved) { _, _ in tryResolve() }
    }

    private func begin() {
        withAnimation(.easeInOut(duration: 3.0)) { circleScale = 1.0 }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            minElapsed = true
        }
    }

    private func tryResolve() {
        guard minElapsed, isAuthResolved, !resolving, !didComplete else { return }
        withAnimation(.easeInOut(duration: 0.8)) {
            resolving = true
            circleScale = 1.3
        }
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            didComplete = true
            onComplete()
        }
    }
}
```

## ContentView.swift diff
```diff
     @State private var route: Route = .launching
     @StateObject private var auth = AuthManager()
+    @State private var authValid: Bool? = nil   // nil = validation pending
```
```diff
             case .launching:
-                ZStack { ParchmentBackground(); CompassMark(color: WV.gold).frame(width: 46, height: 46) }
-                    .transition(pageTransition)
+                SplashView(isAuthResolved: authValid != nil) { finishLaunch() }
+                    .transition(pageTransition)
```
```diff
         .task {
-            let valid = await auth.bootstrapAndValidate()
-            withAnimation(.easeInOut(duration: 0.4)) {
-                route = valid ? (onboarded ? .main : .onboarding) : .threshold
-            }
+            authValid = await auth.bootstrapAndValidate()
         }
     }
+
+    private func finishLaunch() {
+        let valid = authValid ?? false
+        withAnimation(.easeInOut(duration: 0.6)) {
+            route = valid ? (onboarded ? .main : .onboarding) : .threshold
+        }
+    }
```

## Aesthetic choice
Default: flat teal circle @0.12 opacity + teal serif text (legible, calm, no glow, on-brand).
Alternative: solid/opaque teal disc with parchment/white text below it (more literal eclipse).
Confirm which.

## After approval
Create SplashView.swift, apply ContentView diff, build 0/0, report. Auth routing unchanged
underneath. No git.
