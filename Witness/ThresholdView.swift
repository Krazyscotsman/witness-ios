import SwiftUI

// MARK: - Threshold (launch). One confident action: Enter -> login.
struct ThresholdView: View {
    var onEnter: () -> Void
    private let rControl: CGFloat = 16

    var body: some View {
        ZStack {
            ParchmentDoorBackground(fade: 0.41, inkContrast: 1.35)

            VStack(spacing: 0) {
                Spacer()
                CompassMark(color: WV.gold).frame(width: 46, height: 46)
                Text("WITNESS")
                    .font(.serif(36)).tracking(12).padding(.leading, 12)
                    .foregroundStyle(WV.teal).padding(.top, 18)
                Rectangle().fill(WT.ink.opacity(0.18)).frame(width: 56, height: 1).padding(.top, 16)
                Text("A SECOND WITNESS TO YOUR LIFE")
                    .font(.system(size: 11)).tracking(2)
                    .foregroundStyle(WT.ink.opacity(0.83)).padding(.top, 16)
                Spacer()
                Button { onEnter() } label: {
                    Text("Enter")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(WV.teal)
                        .clipShape(RoundedRectangle(cornerRadius: rControl, style: .continuous))
                        .shadow(color: WV.teal.opacity(0.35), radius: 12, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 44)
        }
    }
}
