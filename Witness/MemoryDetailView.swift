import SwiftUI

struct MemoryDetailView: View {
    let memory: SampleMemory
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Profile.companionNameKey) private var companion: String = Profile.defaultCompanionName

    // Set true once a memory carries a real cover photo; sample memories have none.
    private var hasCoverPhoto: Bool { false }

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    cover
                    VStack(alignment: .leading, spacing: 18) {
                        Text(memory.date.uppercased())
                            .font(.system(size: 12, weight: .semibold)).tracking(1.5)
                            .foregroundStyle(WV.gold)
                        Text(memory.title)
                            .font(.serif(30)).foregroundStyle(WT.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if !memory.people.isEmpty { peopleChips }
                        Text(memory.narrative)
                            .font(.serif(18)).foregroundStyle(WT.ink.opacity(0.85))
                            .lineSpacing(7).fixedSize(horizontal: false, vertical: true)
                        metadataRow.padding(.top, 2)
                        actionsRow.padding(.top, 8)
                        askCard.padding(.top, 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, hasCoverPhoto ? 6 : 22)
                    .padding(.bottom, 64)   // clears the tab bar so Ask card is fully visible
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .ignoresSafeArea(edges: .top)

            topControls
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // With a photo: a tall cover that dissolves into the page. Without: a slim, quiet
    // band of color at the very top — a hint, not a slab.
    private var cover: some View {
        Group {
            if hasCoverPhoto {
                LinearGradient(colors: [WV.teal.opacity(0.32), Color(hex: 0xe6dccb)],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
                    .frame(height: 300)
                    .mask(
                        LinearGradient(stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: 0.60),
                            .init(color: .clear, location: 1.0)
                        ], startPoint: .top, endPoint: .bottom)
                    )
            } else {
                LinearGradient(colors: [WV.teal.opacity(0.16), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 130)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var topControls: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: { controlCircle("chevron.left") }
                .witnessPress()
            Spacer()
            Button { /* TODO: edit -> PUT /api/v1/memories/{id} */ } label: { controlCircle("pencil") }
                .witnessPress()
                .witnessHint("Edit this memory's title, date, and words.")
            Button(role: .destructive) { /* TODO: delete (confirm first when wired) */ } label: {
                controlCircle("trash", tint: WV.danger)
            }
            .witnessPress()
            .witnessHint("Delete this memory. You'll be asked to confirm.")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private func controlCircle(_ system: String, tint: Color = WT.ink.opacity(0.8)) -> some View {
        Image(systemName: system)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(Color.white, in: Circle())
            .overlay(Circle().stroke(WT.ink.opacity(0.08), lineWidth: 1))
            .shadow(color: WT.ink.opacity(0.12), radius: 5, y: 2)
    }

    private var peopleChips: some View {
        HStack(spacing: 8) {
            ForEach(memory.people, id: \.self) { p in
                HStack(spacing: 6) {
                    Image(systemName: "person.fill").font(.system(size: 12)).foregroundStyle(WV.teal)
                    Text(p).font(.system(size: 15, weight: .medium)).foregroundStyle(WT.ink.opacity(0.8))
                }
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(WV.teal.opacity(0.10), in: Capsule())
            }
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 18) {
            metaItem("doc.text", "\(memory.wordCount) words")
            metaItem("heart", memory.texture)
        }
    }
    private func metaItem(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.4))
            Text(text).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.5))
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            actionChip("speaker.wave.2.fill", "Listen") { /* TODO: GET /api/v1/memories/{id}/audio */ }
                .witnessHint("Hear this memory read aloud in \(companion)'s voice.")
            actionChip("photo.badge.plus", "Add media") { /* TODO: POST /api/v1/memories/{id}/media */ }
            actionChip("wand.and.stars", "Create image") { /* TODO: POST /visualize/{id} */ }
        }
    }
    private func actionChip(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(WV.teal.opacity(0.12))
                    Image(systemName: icon).font(.system(size: 20)).foregroundStyle(WV.teal)
                }
                .frame(width: 44, height: 44)
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(WT.ink.opacity(0.75))
            }
            .frame(maxWidth: .infinity).frame(height: 96)
            .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
            .shadow(color: WT.ink.opacity(0.06), radius: 8, y: 4)
        }
        .witnessPress()
    }

    private var askCard: some View {
        Button { /* TODO: open Talk anchored to this memory */ } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.18))
                    CompassMark(color: WV.gold).frame(width: 22, height: 22)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ask \(companion)")
                        .font(.serif(19)).foregroundStyle(.white)
                    Text("Talk through this memory together.")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(WV.teal, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: WV.teal.opacity(0.35), radius: 14, y: 8)
        }
        .witnessPress(scale: 0.97)
    }
}
