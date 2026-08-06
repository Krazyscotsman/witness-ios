import SwiftUI

// MARK: - The app shell: five rooms, custom tab bar (active = teal icon, on white).
struct MainTabView: View {
    var onSignOut: () -> Void
    @State private var tab: Tab = .home

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
            case .memories: MemoriesView()
            case .talk:     TalkView()
            case .insights: InsightsView()
            case .you:      YouView(onSignOut: onSignOut)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WitnessTabBar(selection: $tab)
        }
    }
}

private struct WitnessTabBar: View {
    @Binding var selection: MainTabView.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTabView.Tab.allCases, id: \.self) { t in
                let sel = (t == selection)
                Button { selection = t } label: {
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
