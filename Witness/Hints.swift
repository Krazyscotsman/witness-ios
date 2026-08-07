import SwiftUI

// Shared key so the toggle and every hint badge read the same setting.
enum HintSettings {
    static let key = "settings.showHints"
}

// The little teal "?" badge.
struct HintDot: View {
    var body: some View {
        ZStack {
            Circle().fill(WV.teal)
            Image(systemName: "questionmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 20, height: 20)
        .shadow(color: WT.ink.opacity(0.18), radius: 2, y: 1)
    }
}

// The explanation bubble.
struct HintCallout: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(WT.ink)
            .lineSpacing(3)
            .padding(16)
            .frame(maxWidth: 260)
            .presentationBackground(Color(hex: 0xfaf7f0))
    }
}

// Attach a hint to any control: `.witnessHint("what this does")`
struct WitnessHint: ViewModifier {
    @AppStorage(HintSettings.key) private var showHints: Bool = true
    let text: String
    let alignment: Alignment
    @State private var showing = false

    func body(content: Content) -> some View {
        content.overlay(alignment: alignment) {
            if showHints {
                Button { showing = true } label: { HintDot() }
                    .buttonStyle(.plain)
                    .padding(6)
                    .offset(x: 12, y: -12)
                    .popover(isPresented: $showing) {
                        HintCallout(text: text)
                            .presentationCompactAdaptation(.popover)
                    }
                    .accessibilityLabel("Help")
            }
        }
    }
}

extension View {
    func witnessHint(_ text: String, at alignment: Alignment = .topTrailing) -> some View {
        modifier(WitnessHint(text: text, alignment: alignment))
    }
}

// MARK: - Press feedback ---------------------------------------------------------
// A button style that makes a press obvious: the control dips and dims while held,
// springs back on release, and fires a haptic tap. Use everywhere for consistency.

struct WitnessPressStyle: ButtonStyle {
    var scale: CGFloat = 0.95     // how far it dips
    var dim: Double = 0.82        // how much it dims while held

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? dim : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tap() }
            }
    }
}

extension View {
    /// Use in place of `.buttonStyle(.plain)` to get the dip + dim + haptic.
    func witnessPress(scale: CGFloat = 0.95, dim: Double = 0.82) -> some View {
        buttonStyle(WitnessPressStyle(scale: scale, dim: dim))
    }
}

// Small haptic helper (no-op on devices without a haptic engine, e.g. older iPads).
enum Haptics {
    static func tap() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.impactOccurred()
    }
    static func recordStart() {
        let g = UIImpactFeedbackGenerator(style: .heavy)
        g.impactOccurred()
    }
    static func recordStop() {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
