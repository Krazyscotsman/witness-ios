import SwiftUI

// MARK: - Root router. threshold -> login -> (onboarding first time) -> main.
struct ContentView: View {
    private enum Route { case launching, threshold, login, onboarding, main }
    @State private var route: Route = .launching
    @StateObject private var auth = AuthManager()
    @State private var authValid: Bool? = nil   // nil = validation pending

    // Real: driven by the backend's narrator.onboarding_completed flag (deferred; local flag for now).
    @AppStorage("profile.onboarded") private var onboarded: Bool = false

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
                        withAnimation(.easeInOut(duration: 0.6)) { route = onboarded ? .main : .onboarding }
                    }
                )
                .transition(pageTransition)
            case .onboarding:
                OnboardingView(onFinish: {
                    onboarded = true
                    withAnimation(.easeInOut(duration: 0.6)) { route = .main }
                })
                .transition(pageTransition)
            case .main:
                MainTabView(onSignOut: {
                    auth.logout()
                    withAnimation(.easeInOut(duration: 0.5)) { route = .threshold }
                })
                .transition(pageTransition)
            }
        }
        .task {
            // Validate underneath the splash; the splash decides WHEN to reveal the result
            // (min ~3s AND auth resolved). bootstrapAndValidate has an 8s timeout so a down
            // backend resolves to false quickly rather than hanging the splash.
            authValid = await auth.bootstrapAndValidate()
        }
    }

    // Called by SplashView once the reveal + auth have both resolved.
    private func finishLaunch() {
        let valid = authValid ?? false
        withAnimation(.easeInOut(duration: 0.6)) {
            route = valid ? (onboarded ? .main : .onboarding) : .threshold
        }
    }
}

#Preview {
    ContentView()
}
