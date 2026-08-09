import SwiftUI

// Branded launch splash that doubles as the visible surface of the auth-validation gate. It runs
// a calm ~3s reveal while AuthManager.bootstrapAndValidate() resolves underneath (in ContentView),
// then resolves to "Now." and dissolves into the destination. Minimum ~3s floor: completes only
// when BOTH the reveal has elapsed AND auth has resolved (holds gracefully if auth lags; a launch
// timeout on the validation itself ensures "auth resolved" always arrives within ~8s).
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
        withAnimation(.easeInOut(duration: 3.0)) { circleScale = 1.0 }    // gentle grow over ~3s
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)             // ~3s minimum floor
            minElapsed = true                                            // → onChange → tryResolve
        }
    }

    private func tryResolve() {
        guard minElapsed, isAuthResolved, !resolving, !didComplete else { return }
        withAnimation(.easeInOut(duration: 0.8)) {
            resolving = true        // "Now." crossfades in (contentTransition)
            circleScale = 1.3       // the eclipse completes
        }
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)              // let "Now." + settle read
            didComplete = true
            onComplete()
        }
    }
}
