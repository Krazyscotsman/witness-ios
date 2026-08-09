import SwiftUI

// MARK: - Root router. threshold -> login -> (onboarding first time) -> main.
struct ContentView: View {
    private enum Route { case launching, threshold, login, onboarding, main }
    @State private var route: Route = .launching
    @StateObject private var auth = AuthManager()
    @State private var authValid: Bool? = nil   // nil = validation pending

    private var pageTransition: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 14)), removal: .opacity)
    }

    var body: some View {
        ZStack {
            switch route {
            case .launching:
                SplashView(isAuthResolved: authValid != nil) { finishLaunch() }
                    .transition(pageTransition)
            case .threshold:
                ThresholdView(onEnter: { withAnimation(.easeInOut(duration: 0.6)) { route = .login } })
                    .transition(pageTransition)
            case .login:
                LoginView(
                    auth: auth,
                    onBack: { withAnimation(.easeInOut(duration: 0.6)) { route = .threshold } },
                    onAuthenticated: {
                        // Fetch the backend profile, then route on onboarding_completed (decision a: unknown → main).
                        Task {
                            await auth.loadLaunchProfile()
                            withAnimation(.easeInOut(duration: 0.6)) {
                                route = (auth.onboardingCompleted ?? true) ? .main : .onboarding
                            }
                        }
                    }
                )
                .transition(pageTransition)
            case .onboarding:
                OnboardingView(onFinish: {
                    // The backend onboarding_completed flag is written by the (not-yet-wired) save step.
                    // Until then this only advances the session; a relaunch re-routes per the backend flag.
                    withAnimation(.easeInOut(duration: 0.6)) { route = .main }
                })
                .transition(pageTransition)
            case .main:
                MainTabView(auth: auth, onSignOut: {
                    auth.logout()
                    withAnimation(.easeInOut(duration: 0.5)) { route = .threshold }
                })
                .transition(pageTransition)
            }
        }
        .task {
            // Validate underneath the splash, THEN (if valid) fetch the profile so the onboarding route is
            // known at reveal. Both calls are timeout-bounded (8s each) so a down/hung backend can't freeze
            // launch. authValid is set only after the profile resolves (or times out) — the splash reveals on
            // min ~3s AND authValid != nil.
            let valid = await auth.bootstrapAndValidate()
            if valid { await auth.loadLaunchProfile() }
            authValid = valid
        }
        .onChange(of: auth.isLoggedIn) { _, loggedIn in
            // Session ended mid-use (e.g. a 401 with no/invalid refresh) → back to the door.
            if !loggedIn && (route == .main || route == .onboarding) {
                withAnimation(.easeInOut(duration: 0.5)) { route = .threshold }
            }
        }
    }

    // Called by SplashView once the reveal + auth have both resolved.
    private func finishLaunch() {
        let valid = authValid ?? false
        withAnimation(.easeInOut(duration: 0.6)) {
            // Decision (a): valid token but profile unknown/failed (onboardingCompleted == nil) → main.
            route = valid ? ((auth.onboardingCompleted ?? true) ? .main : .onboarding) : .threshold
        }
    }
}

#Preview {
    ContentView()
}
