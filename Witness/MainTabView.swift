import SwiftUI

// MARK: - The app shell: five rooms, custom tab bar (active = teal icon, on white).
struct MainTabView: View {
    @ObservedObject var auth: AuthManager
    var onSignOut: () -> Void
    @State private var tab: Tab = .home
    @StateObject private var memoriesVM = MemoriesViewModel()   // owned above the tab → cached across switches
    // Nav paths owned above the tabs so each pushing tab survives switches AND can pop-to-root on re-tap.
    @State private var memoriesPath = NavigationPath()
    @State private var insightsPath = NavigationPath()
    @State private var youPath = NavigationPath()

    enum Tab: Int, CaseIterable {
        case home, memories, talk, insights, you
        var title: String {
            switch self {
            case .home: return "Home"; case .memories: return "Memories"
            case .talk: return "Talk"; case .insights: return "Insights"; case .you: return "You"
            }
        }
        var icon: String {
            switch self {
            case .home: return "house"; case .memories: return "book.closed"
            case .talk: return "bubble.left.and.bubble.right"; case .insights: return "sparkles"; case .you: return "person"
            }
        }
        var iconSelected: String {
            switch self {
            case .home: return "house.fill"; case .memories: return "book.closed.fill"
            case .talk: return "bubble.left.and.bubble.right.fill"; case .insights: return "sparkles"; case .you: return "person.fill"
            }
        }
    }

    var body: some View {
        Group {
            switch tab {
            case .home:     HomeView()
            case .memories: MemoriesView(vm: memoriesVM, auth: auth, path: $memoriesPath)
            case .talk:     TalkView()
            case .insights: InsightsView(path: $insightsPath)
            case .you:      YouView(auth: auth, path: $youPath, onSignOut: onSignOut)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WitnessTabBar(selection: $tab, onReselect: { reselected in
                // Tapping the already-active tab pops that tab's stack to root (iOS standard).
                switch reselected {
                case .memories: memoriesPath = NavigationPath()
                case .insights: insightsPath = NavigationPath()
                case .you:      youPath = NavigationPath()
                default: break   // home/talk don't push
                }
            })
        }
    }
}

private struct WitnessTabBar: View {
    @Binding var selection: MainTabView.Tab
    var onReselect: (MainTabView.Tab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTabView.Tab.allCases, id: \.self) { t in
                let sel = (t == selection)
                Button {
                    if t == selection {
                        onReselect(t)          // already active → pop that tab to root
                    } else {
                        Haptics.tap()          // light tick only on an actual switch (unchanged)
                        selection = t
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: sel ? t.iconSelected : t.icon)
                            .font(.system(size: 26, weight: sel ? .semibold : .regular))
                            .frame(height: 30)
                        Text(t.title)
                            .font(.system(size: 12, weight: sel ? .semibold : .regular))
                    }
                    .foregroundStyle(sel ? WV.teal : WT.ink.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background {
            Color.white
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Rectangle().fill(WT.ink.opacity(0.08)).frame(height: 1)
                }
                .shadow(color: WT.ink.opacity(0.06), radius: 10, y: -3)
        }
    }
}
