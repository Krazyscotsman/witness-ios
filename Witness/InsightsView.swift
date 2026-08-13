import SwiftUI

// MARK: - Insights: a HUB (per IA map). Anchors opens the real surface; others are
// placeholders naming their endpoint until built out.
struct InsightsView: View {
    @ObservedObject var auth: AuthManager
    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                ParchmentBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        header
                        NavigationLink(value: InsightItem.explain) { ExplainFeatureCard() }
                            .witnessPress(scale: 0.97)
                        ForEach(InsightItem.others) { item in
                            NavigationLink(value: item) { InsightRow(item: item) }
                                .witnessPress()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 110)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: InsightItem.self) { item in
                switch item.id {
                case "anchors":  AnchorRegistryView(auth: auth)
                case "timeline": TimelineView(auth: auth)
                case "memoir":   MemoirView()
                case "learn":    LearnView()
                case "explain":  ExplainView(auth: auth)
                case "graph":    GraphView()
                case "media":    MediaView(auth: auth)
                default:         InsightSurfaceView(item: item)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Insights").font(.serif(28)).foregroundStyle(WV.teal)
                Text("What your memories reveal.")
                    .font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.5))
            }
            Spacer()
            CompassMark(color: WV.gold).frame(width: 30, height: 30)
        }
        .padding(.bottom, 2)
    }
}

// MARK: - The six surfaces.
struct InsightItem: Identifiable, Hashable {
    let id: String
    let icon: String
    let title: String
    let blurb: String
    let endpoint: String?
    let note: String?

    static let explain = InsightItem(
        id: "explain", icon: "sparkles", title: "Explain",
        blurb: "The forces, contradictions, and evolutions that shape you.",
        endpoint: "GET /api/v1/explain-me/overview", note: nil)

    static let others: [InsightItem] = [
        .init(id: "timeline", icon: "clock", title: "Timeline",
              blurb: "Your life laid out in time.",
              endpoint: "GET /timeline/visual", note: nil),
        .init(id: "memoir", icon: "text.book.closed", title: "Memoir",
              blurb: "Your story, written as a flowing narrative.",
              endpoint: nil, note: nil),
        .init(id: "learn", icon: "magnifyingglass", title: "Learn",
              blurb: "Ask your life a question — answered with its own sources.",
              endpoint: nil, note: nil),
        .init(id: "anchors", icon: "mappin.and.ellipse", title: "Anchors",
              blurb: "The defining truths everything else orbits.",
              endpoint: "GET /timeline/{category}", note: nil),
        .init(id: "graph", icon: "point.3.connected.trianglepath.dotted", title: "Graph",
              blurb: "A map of the people in your life and how they connect.",
              endpoint: "GET /api/v1/graph",
              note: "Renders natively with the Grape package — we'll add it when we build this view."),
      .init(id: "media", icon: "photo.stack", title: "Media",
              blurb: "Every photo, video, and recording you've kept.",
              endpoint: "GET /api/v1/media/gallery", note: nil),
      ]
}

// MARK: - Featured Explain card (centerpiece).
struct ExplainFeatureCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.white.opacity(0.18))
                Image(systemName: "sparkles").font(.system(size: 20)).foregroundStyle(.white)
            }
            .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text("Explain").font(.serif(22)).foregroundStyle(.white)
                Text("The forces, contradictions, and evolutions that shape you.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.teal, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: WV.teal.opacity(0.35), radius: 14, y: 8)
    }
}

// MARK: - Standard hub row.
struct InsightRow: View {
    let item: InsightItem
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(WV.teal.opacity(0.12))
                Image(systemName: item.icon).font(.system(size: 18, weight: .medium)).foregroundStyle(WV.teal)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.serif(19)).foregroundStyle(WT.ink)
                Text(item.blurb).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.06), radius: 10, y: 5)
    }
}

// MARK: - Placeholder surface (honest "coming together" + the real endpoint).
struct InsightSurfaceView: View {
    let item: InsightItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            VStack(spacing: 16) {
                Spacer()
                ZStack {
                    Circle().fill(WV.teal.opacity(0.12))
                    Image(systemName: item.icon).font(.system(size: 30, weight: .medium)).foregroundStyle(WV.teal)
                }
                .frame(width: 76, height: 76)
                Text(item.title).font(.serif(30)).foregroundStyle(WV.teal)
                Text(item.blurb)
                    .font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.6))
                    .multilineTextAlignment(.center).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)
                Text("This view is coming together.")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(WT.ink.opacity(0.4))
                    .padding(.top, 4)
                if let note = item.note {
                    Text(note)
                        .font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.4))
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 44)
                }
                if let endpoint = item.endpoint {
                    Text(endpoint)
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(WT.ink.opacity(0.35))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(WV.card, in: Capsule())
                        .overlay(Capsule().stroke(WT.ink.opacity(0.08), lineWidth: 1))
                        .padding(.top, 2)
                }
                Spacer(); Spacer()
            }
            .frame(maxWidth: .infinity)

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.8))
                        .frame(width: 44, height: 44).background(Color.white, in: Circle())
                        .overlay(Circle().stroke(WT.ink.opacity(0.08), lineWidth: 1))
                        .shadow(color: WT.ink.opacity(0.1), radius: 4, y: 2)
                }
                .witnessPress()
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 6)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}
