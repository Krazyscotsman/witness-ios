import SwiftUI

// MARK: - Home ("Your Witness"). A single, calm invitation: a greeting and one floating prompt
// that slowly cross-fades through the activation set. No stage machine, no forces, no recent list,
// no /explain-me/overview load — Home no longer diagnoses; it invites. Tapping the prompt opens
// Record seeded with that prompt (Type mode, disappearing placeholder). There is no global "+".
struct HomeView: View {
    @ObservedObject var auth: AuthManager
    @ObservedObject var memoriesVM: MemoriesViewModel
    @Binding var tab: MainTabView.Tab

    @StateObject private var vm = HomeActivationViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("witness.home.greetingVariant") private var greetingVariant = 0

    @State private var showRecord = false
    @State private var suggestion: String?          // prompt text handed to RecordView
    @State private var suggestionPromptID: String?  // so a successful save can retire/evolve its kind

    var body: some View {
        NavigationStack {
            ZStack {
                ParchmentBackground()
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Spacer()
                    promptItem
                    Spacer()
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 110)   // clears the tab bar
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fullScreenCover(isPresented: $showRecord) {
                RecordView(auth: auth, initialSuggestion: suggestion) {
                    vm.didRecord(fromPromptID: suggestionPromptID)
                    Task { await memoriesVM.refresh(auth: auth) }
                }
            }
            .task { vm.start() }
            .onDisappear { vm.stop() }
            .onAppear { greetingVariant = (greetingVariant + 1) % 3 }
        }
    }

    // MARK: Header — rotating greeting + wordmark + compass. No card chrome.
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

    // Three greeting variants; one is time-aware. Rotates each time Home appears.
    private var greeting: String {
        let daypart: String
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  daypart = "morning"
        case 12..<17: daypart = "afternoon"
        case 17..<22: daypart = "evening"
        default:      daypart = "night"
        }
        let variants = ["Good \(daypart).", "Welcome back.", "Whenever you're ready."]
        return variants[greetingVariant % variants.count]
    }

    // MARK: Floating cycling prompt — premium, minimal, no card. Slow cross-fade + subtle grow-in,
    // a light haptic on each change, all suppressed under Reduce Motion. Tap → Record with this prompt.
    private var promptItem: some View {
        Button {
            beginRecord()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text("A MEMORY TO SHARE")
                    .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(WT.ink.opacity(0.35))
                Text(vm.currentText)
                    .font(.serif(32)).foregroundStyle(WT.ink)
                    .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    .id(vm.current?.id)
                    .transition(promptTransition)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .witnessPress(scale: 0.98, dim: 0.9)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: vm.current?.id)
    }

    private var promptTransition: AnyTransition {
        reduceMotion ? .opacity
                     : .opacity.combined(with: .scale(scale: 0.98, anchor: .leading))
    }

    private func beginRecord() {
        suggestion = vm.currentText
        suggestionPromptID = vm.current?.id
        showRecord = true
    }
}
