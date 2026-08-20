import SwiftUI

// MARK: - Home ("Your Witness"). Real state derives from memory count (cached MemoriesVM) + hasEnoughData
// (/explain-me/overview via HomeViewModel): total==0 → Begin, total>0 && !hasEnoughData → Learning,
// hasEnoughData → Ready. While signals are still unknown we show a Neutral placeholder rather than flash the
// wrong panel. Ready renders the real overview headline + core forces. Overview failure degrades to
// count-only. Companion name is read dynamically (never hardcoded).
struct HomeView: View {
    @ObservedObject var auth: AuthManager
    @ObservedObject var memoriesVM: MemoriesViewModel
    @Binding var tab: MainTabView.Tab

    @StateObject private var vm = HomeViewModel()
    @AppStorage(Profile.companionNameKey) private var companionName: String = Profile.defaultCompanionName
    @State private var showRecord = false

    enum Stage { case neutral, begin, learning, ready }

    private var companion: String { companionName.isEmpty ? Profile.defaultCompanionName : companionName }

    // Commit to a panel only when it can't be wrong; otherwise Neutral (no flashing).
    private var stage: Stage {
        let memKnown = memoriesVM.state == .loaded
        let total = memoriesVM.total
        switch vm.state {
        case .loaded:
            if memKnown { return total == 0 ? .begin : (vm.hasEnoughData ? .ready : .learning) }
            return vm.hasEnoughData ? .ready : .neutral
        case .failed:                                   // degrade → memory-count-only
            if memKnown { return total == 0 ? .begin : .learning }
            return .neutral
        case .idle, .loading:
            if memKnown && total == 0 { return .begin } // only safe early commit
            return .neutral
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ParchmentBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        Group {
                            switch stage {
                            case .neutral:  neutralContent
                            case .begin:    beginContent
                            case .learning: learningContent
                            case .ready:    readyContent
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 16)
                    .padding(.bottom, 110)   // clears the tab bar so the "Talk it through" button is fully visible
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationDestination(for: MemoryDTO.self) { m in MemoryDetailView(listItem: m, auth: auth) }
            .fullScreenCover(isPresented: $showRecord) {
                RecordView(auth: auth) { Task { await memoriesVM.refresh(auth: auth) } }
            }
            .task { await vm.load(auth: auth) }
            .task { await memoriesVM.load(auth: auth) }
        }
    }

    // MARK: header (greeting is local; first-name greeting intentionally skipped)
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

    // MARK: Neutral — signals not yet known; calm, no claim, no wrong panel
    private var neutralContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your Witness").font(.serif(30)).foregroundStyle(WT.ink)
            HStack(spacing: 10) {
                ProgressView().tint(WV.teal)
                Text("Reflecting on your story…").font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.55))
            }
            .padding(.top, 4)
        }
    }

    // MARK: Begin (total == 0)
    private var beginContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your witness begins here.")
                .font(.serif(30)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
            Text("Witness builds a living picture of your life from the moments you share. Record your first memory, and the mirror begins to fill.")
                .font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.6)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            primaryButton("Record your first memory") { showRecord = true }.padding(.top, 6)
        }
    }

    // MARK: Learning (memories exist, not enough data yet)
    private var learningContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("The picture is forming.")
                .font(.serif(30)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
            Text("Keep going — each memory you share adds depth. Soon the mirror will start to reflect you back.")
                .font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.6)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            recentMemoriesCard
            primaryButton("Add a memory") { showRecord = true }.padding(.top, 2)
        }
    }

    // MARK: Ready (hasEnoughData) — real headline + core forces
    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("HERE'S WHAT'S EMERGING")
                .font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(WT.ink.opacity(0.4))
            Text(vm.headline ?? "Here’s what’s emerging in the story you’ve told.")
                .font(.serif(27)).foregroundStyle(WT.ink).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            let forces = Array(vm.coreForces.prefix(3))
            if !forces.isEmpty {
                Text("ACTIVE FORCES")
                    .font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(WT.ink.opacity(0.4)).padding(.top, 10)
                VStack(spacing: 12) {
                    ForEach(Array(forces.enumerated()), id: \.offset) { _, f in forceCard(f) }
                }
            }
            recentMemoriesCard
            primaryButton("Talk it through with \(companion)") { tab = .talk }.padding(.top, 6)
        }
    }
    private func forceCard(_ f: ExForceDTO) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Circle().fill(WV.gold).frame(width: 7, height: 7).padding(.top, 7)
            VStack(alignment: .leading, spacing: 4) {
                Text(f.title ?? "A force in your story").font(.serif(18)).foregroundStyle(WT.ink)
                Text(forceSubtitle(f)).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.55))
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
    private func forceSubtitle(_ f: ExForceDTO) -> String {
        if let ii = f.identityImpact?.trimmingCharacters(in: .whitespacesAndNewlines), !ii.isEmpty { return ii }
        let domains = (f.affectedDomains ?? []).prefix(3).map { AnchorText.titleCase($0) }.filter { !$0.isEmpty }
        if !domains.isEmpty { return domains.joined(separator: " · ") }
        return "A recurring force across your memories."
    }

    // MARK: Recent memories (top 2–3) → tap → MemoryDetailView
    @ViewBuilder private var recentMemoriesCard: some View {
        let recent = Array(memoriesVM.memories.prefix(3))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("PICK UP WHERE YOU LEFT OFF")
                    .font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(WT.ink.opacity(0.4))
                VStack(spacing: 10) { ForEach(recent) { m in recentRow(m) } }
            }
            .padding(.top, 4)
        }
    }
    private func recentRow(_ m: MemoryDTO) -> some View {
        NavigationLink(value: m) {
            HStack(spacing: 12) {
                ZStack { Circle().fill(WV.teal.opacity(0.12)); Image(systemName: "book.closed").font(.system(size: 15)).foregroundStyle(WV.teal) }
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.title ?? "Untitled memory").font(.serif(17)).foregroundStyle(WT.ink).lineLimit(1)
                    Text(MemoryFormat.date(m)).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5))
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(WV.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
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
