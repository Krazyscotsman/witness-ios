import SwiftUI

struct HomeView: View {
    enum MirrorState: String, CaseIterable {
        case begin = "Begin"
        case learning = "Learning"
        case ready = "This is you"
    }
    @State private var state: MirrorState = .begin
    @State private var showRecord = false

    var body: some View {
        ZStack {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    StateSwitcher(selection: $state)   // TEMPORARY — backend readiness flag later
                    Group {
                        switch state {
                        case .begin:    beginContent
                        case .learning: learningContent
                        case .ready:    readyContent
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fullScreenCover(isPresented: $showRecord) { RecordView() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.5))
                Text("Your Witness").font(.serif(24)).foregroundStyle(WV.teal)
            }
            Spacer()
            CompassMark(color: WV.gold).frame(width: 30, height: 30)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Hello"
        }
    }

    private var beginContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your witness begins here.")
                .font(.serif(30)).foregroundStyle(WT.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Witness builds a living picture of your life from the moments you share. Record your first memory, and the mirror begins to fill.")
                .font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.6))
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            primaryButton("Record your first memory") { showRecord = true }
                .padding(.top, 6)
        }
    }

    private var learningContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("The picture is forming.")
                .font(.serif(30)).foregroundStyle(WT.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Keep going — each memory you share adds depth. Soon the mirror will start to reflect you back.")
                .font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.6))
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 12) { formingCard; formingCard }.padding(.top, 4)
            primaryButton("Add a memory") { showRecord = true }.padding(.top, 4)
        }
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("HERE'S WHAT'S EMERGING")
                .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                .foregroundStyle(WT.ink.opacity(0.4))
            Text("You return, again and again, to the people who shaped you.")
                .font(.serif(27)).foregroundStyle(WT.ink)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Text("ACTIVE FORCES")
                .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                .foregroundStyle(WT.ink.opacity(0.4)).padding(.top, 10)
            VStack(spacing: 12) {
                forceCard("Family", "The center of gravity in most of your memories.")
                forceCard("Reinvention", "A recurring turn toward starting over.")
                forceCard("Service", "A throughline of looking after others.")
            }
            primaryButton("Talk it through with Scarlett") { /* TODO: switch to Talk tab */ }.padding(.top, 6)
        }
    }

    private var formingCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 9) {
                Capsule().fill(WT.ink.opacity(0.09)).frame(width: 150, height: 10)
                Capsule().fill(WT.ink.opacity(0.06)).frame(width: 210, height: 10)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(WT.ink.opacity(0.06), lineWidth: 1))
    }

    private func forceCard(_ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Circle().fill(WV.gold).frame(width: 7, height: 7).padding(.top, 7)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.serif(18)).foregroundStyle(WT.ink)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(WT.ink.opacity(0.06), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.04), radius: 10, y: 5)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(WV.teal)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: WV.teal.opacity(0.30), radius: 10, y: 6)
        }
        .witnessPress()
    }
}

private struct StateSwitcher: View {
    @Binding var selection: HomeView.MirrorState
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HomeView.MirrorState.allCases, id: \.self) { s in
                let isSel = s == selection
                Text(s.rawValue)
                    .font(.system(size: 13, weight: isSel ? .semibold : .regular))
                    .foregroundStyle(isSel ? Color.white : WT.ink.opacity(0.5))
                    .frame(maxWidth: .infinity).frame(height: 34)
                    .background(
                        Group {
                            if isSel {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(WV.teal)
                                    .matchedGeometryEffect(id: "seg_pill", in: ns)
                            }
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = s } }
            }
        }
        .padding(4)
        .background(WT.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
