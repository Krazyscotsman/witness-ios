import SwiftUI

// MARK: - Root router. threshold -> login -> (onboarding first time) -> main.
struct ContentView: View {
    private enum Route { case threshold, login, onboarding, main }
    @State private var route: Route = .threshold

    // Real: driven by the backend's narrator.onboarding_completed flag.
    @AppStorage("profile.onboarded") private var onboarded: Bool = false

    private var pageTransition: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 14)), removal: .opacity)
    }

    var body: some View {
        ZStack {
            switch route {
            case .threshold:
                ThresholdView(onEnter: { withAnimation(.easeInOut(duration: 0.6)) { route = .login } })
                    .transition(pageTransition)
            case .login:
                LoginView(
                    onBack: { withAnimation(.easeInOut(duration: 0.6)) { route = .threshold } },
                    onAuthenticated: {
                        withAnimation(.easeInOut(duration: 0.6)) { route = .onboarding }   // TEMP: always show onboarding while we build/test it
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
                    onboarded = false   // TEMPORARY: reset so onboarding is re-testable. Remove at wiring.
                    withAnimation(.easeInOut(duration: 0.5)) { route = .threshold }
                })
                .transition(pageTransition)
            }
        }
    }
}

#Preview {
    ContentView()
}
