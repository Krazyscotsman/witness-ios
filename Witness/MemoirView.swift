import SwiftUI

// MARK: - Memoir Studio — configures and requests a full memoir.
// POST /memoir/preview (estimate) and POST /memoir/generate (the book).
// Personal atmosphere prompts (the Hope update) enrich quality before generation.
struct MemoirView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var words = 70000
    @State private var style = "narrative"
    @State private var tone = "warm"
    @State private var startYear = ""
    @State private var endYear = ""
    @State private var includeImages = false
    @State private var enrichWithAtmosphere = true
    @State private var dedication = ""

    @State private var showAtmosphere = false
    @State private var showYearPicker = false
    @State private var yearTarget: YearTarget = .start
    @State private var pickerYear = Calendar.current.component(.year, from: Date()) - 30

    @State private var phase: Phase = .config
    enum Phase { case config, generating, ready }
    enum YearTarget { case start, end }

    private let years = Array(1900...Calendar.current.component(.year, from: Date()))

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    switch phase {
                    case .config:     configBody
                    case .generating: generatingBody
                    case .ready:      readyBody
                    }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 120)
            }
            navBar
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showAtmosphere) {
            AtmosphereModal(
                onComplete: { showAtmosphere = false; runGenerate() },
                onCancel: { showAtmosphere = false }
            )
        }
        .sheet(isPresented: $showYearPicker) { yearPickerSheet }
    }

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)); Text("Insights").font(.system(size: 16)) }
                    .foregroundStyle(WV.teal).frame(height: 44)
            }.witnessPress()
            Spacer()
        }
        .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
    }

    // MARK: Config
    private var configBody: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("MEMOIR STUDIO").font(.system(size: 12, weight: .semibold)).tracking(1.4).foregroundStyle(WV.gold)
                Text("Write your life into a book").font(.serif(28)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
                Text("Your memories, woven into chapters. Choose how long, in what voice, and over what span of years.")
                    .font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.6)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }

            section("BOOK TITLE") { field("e.g. The Long Way Home", text: $title) }

            section("TARGET LENGTH") {
                VStack(spacing: 10) { ForEach(WordTarget.all) { lengthCard($0) } }
            }

            section("NARRATIVE STYLE") {
                VStack(spacing: 10) { ForEach(MemoirStyle.all) { styleCard($0) } }
            }

            section("TONE") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["warm","nostalgic","honest","celebratory"], id: \.self) { t in
                            let sel = tone == t
                            Text(t.capitalized)
                                .font(.system(size: 14, weight: sel ? .semibold : .regular))
                                .foregroundStyle(sel ? .white : WT.ink.opacity(0.6))
                                .padding(.horizontal, 16).frame(height: 38)
                                .background(sel ? WV.teal : Color.white, in: Capsule())
                                .overlay(Capsule().stroke(sel ? Color.clear : WT.ink.opacity(0.1), lineWidth: 1))
                                .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { tone = t } }
                        }
                    }
                }
            }

            section("TIME SPAN (OPTIONAL)") {
                HStack(spacing: 12) {
                    yearButton("Start year", value: startYear, target: .start)
                    yearButton("End year", value: endYear, target: .end)
                }
            }

            section("BOOK DETAILS") {
                VStack(spacing: 12) {
                    atmosphereToggle
                    Toggle(isOn: $includeImages) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Include images").font(.system(size: 15, weight: .medium)).foregroundStyle(WT.ink)
                            Text("Weave your photos into the chapters.").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5))
                        }
                    }
                    .tint(WV.teal)
                    .padding(14).background(WV.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(WT.ink.opacity(0.1), lineWidth: 1))
                    field("Dedication (optional)", text: $dedication)
                }
            }

            previewCard

            Button { startGenerate() } label: {
                Text("Generate memoir")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(WV.teal, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: WV.teal.opacity(0.3), radius: 10, y: 6)
            }
            .witnessPress()
        }
    }

    // MARK: Year picker (wheel)
    private func yearButton(_ label: String, value: String, target: YearTarget) -> some View {
        Button {
            yearTarget = target
            pickerYear = Int(value) ?? (target == .start ? Calendar.current.component(.year, from: Date()) - 40 : Calendar.current.component(.year, from: Date()))
            showYearPicker = true
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(WT.ink.opacity(0.45))
                HStack {
                    Text(value.isEmpty ? "Any" : value)
                        .font(.system(size: 17)).foregroundStyle(value.isEmpty ? WT.ink.opacity(0.4) : WT.ink)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.4))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var yearPickerSheet: some View {
        VStack(spacing: 16) {
            Capsule().fill(WT.ink.opacity(0.15)).frame(width: 36, height: 5).padding(.top, 10)
            Text(yearTarget == .start ? "Start year" : "End year").font(.serif(22)).foregroundStyle(WV.teal)
            Picker("", selection: $pickerYear) {
                ForEach(years, id: \.self) { y in Text(String(y)).tag(y) }
            }
            .pickerStyle(.wheel).labelsHidden()
            HStack(spacing: 12) {
                Button {
                    if yearTarget == .start { startYear = "" } else { endYear = "" }
                    showYearPicker = false
                } label: {
                    Text("Clear").font(.system(size: 16, weight: .medium)).foregroundStyle(WT.ink.opacity(0.6))
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.12), lineWidth: 1))
                }
                .witnessPress()
                Button {
                    if yearTarget == .start { startYear = String(pickerYear) } else { endYear = String(pickerYear) }
                    showYearPicker = false
                } label: {
                    Text("Done").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(WV.teal, in: RoundedRectangle(cornerRadius: 16))
                }
                .witnessPress()
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
        .background(WV.parchment).presentationDetents([.height(420)])
    }

    private var atmosphereToggle: some View {
        Toggle(isOn: $enrichWithAtmosphere) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 13)).foregroundStyle(WV.gold)
                    Text("Personal atmosphere prompts").font(.system(size: 15, weight: .medium)).foregroundStyle(WT.ink)
                }
                Text("Before writing, add vivid world details per life period — what places looked like, daily routines, the feel of each era. This is what turns a generic memoir into a powerful one.")
                    .font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(WV.teal)
        .padding(14).background(WV.gold.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WV.gold.opacity(0.25), lineWidth: 1))
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MANUSCRIPT PREVIEW").font(.system(size: 11, weight: .semibold)).tracking(1.3).foregroundStyle(WT.ink.opacity(0.4))
            HStack(spacing: 0) {
                previewStat("\(words / 1000)k", "Words")
                Divider().frame(height: 34)
                previewStat("~\(estChapters)", "Chapters")
                Divider().frame(height: 34)
                previewStat(spanText, "Span")
            }
        }
        .padding(16).background(WV.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
    private func previewStat(_ n: String, _ label: String) -> some View {
        VStack(spacing: 3) { Text(n).font(.serif(20)).foregroundStyle(WV.teal); Text(label).font(.system(size: 11)).foregroundStyle(WT.ink.opacity(0.5)) }
            .frame(maxWidth: .infinity)
    }
    private var estChapters: Int { max(3, words / 2000) }
    private var spanText: String {
        let s = startYear.trimmingCharacters(in: .whitespaces), e = endYear.trimmingCharacters(in: .whitespaces)
        if s.isEmpty && e.isEmpty { return "Whole life" }
        return "\(s.isEmpty ? "…" : s)–\(e.isEmpty ? "now" : e)"
    }

    private func lengthCard(_ t: WordTarget) -> some View {
        let sel = words == t.value
        return Button { withAnimation(.easeOut(duration: 0.15)) { words = t.value } } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(t.label).font(.serif(18)).foregroundStyle(sel ? .white : WT.ink)
                        if t.needsBackend {
                            Text("needs cap raised").font(.system(size: 10, weight: .medium))
                                .foregroundStyle(sel ? .white.opacity(0.85) : WV.gold)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background((sel ? Color.white.opacity(0.18) : WV.gold.opacity(0.14)), in: Capsule())
                        }
                    }
                    Text(t.detail).font(.system(size: 13)).foregroundStyle(sel ? .white.opacity(0.85) : WT.ink.opacity(0.55))
                }
                Spacer()
                Text("\(t.value / 1000)k").font(.system(size: 15, weight: .semibold)).foregroundStyle(sel ? .white : WV.teal)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(sel ? WV.teal : WV.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(sel ? Color.clear : WT.ink.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func styleCard(_ st: MemoirStyle) -> some View {
        let sel = style == st.id
        return Button { withAnimation(.easeOut(duration: 0.15)) { style = st.id } } label: {
            HStack(spacing: 12) {
                Image(systemName: sel ? "largecircle.fill.circle" : "circle").font(.system(size: 18)).foregroundStyle(sel ? WV.teal : WT.ink.opacity(0.25))
                VStack(alignment: .leading, spacing: 2) {
                    Text(st.label).font(.serif(17)).foregroundStyle(WT.ink)
                    Text(st.desc).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(WV.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(sel ? WV.teal.opacity(0.4) : WT.ink.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Generating + Ready
    private var generatingBody: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 80)
            ProgressView().scaleEffect(1.4).tint(WV.teal)
            Text("Writing in progress").font(.serif(26)).foregroundStyle(WV.teal)
            Text("\(title.isEmpty ? "Your memoir" : title) is being written, chapter by chapter, from your memories\(enrichWithAtmosphere ? " and the world details you shared" : "").")
                .font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.6)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
    }

    private var readyBody: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 40)
            ZStack { Circle().fill(WV.teal.opacity(0.12)); Image(systemName: "book.fill").font(.system(size: 34)).foregroundStyle(WV.teal) }
                .frame(width: 90, height: 90)
            Text("Ready").font(.serif(30)).foregroundStyle(WV.teal)
            Text(title.isEmpty ? "Your memoir" : title).font(.serif(20)).foregroundStyle(WT.ink).multilineTextAlignment(.center)
            HStack(spacing: 0) {
                previewStat("\(words / 1000)k", "Words")
                Divider().frame(height: 34)
                previewStat("~\(estChapters)", "Chapters")
            }
            .padding(16).background(WV.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 30)
            VStack(spacing: 10) {
                Button { /* TODO: download PDF from result.download_url */ } label: {
                    HStack { Image(systemName: "arrow.down.doc"); Text("Download PDF") }
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 54).background(WV.teal, in: RoundedRectangle(cornerRadius: 16))
                }
                .witnessPress()
                Button { withAnimation { phase = .config } } label: {
                    Text("Create another memoir").font(.system(size: 15, weight: .medium)).foregroundStyle(WV.teal)
                }
                .witnessPress()
            }
            .padding(.horizontal, 30).padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Helpers
    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12, weight: .semibold)).tracking(1.3).foregroundStyle(WT.ink.opacity(0.45))
            content()
        }
    }
    private func field(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 16)).foregroundStyle(WT.ink).tint(WV.teal).keyboardType(keyboard)
            .padding(.horizontal, 14).frame(height: 50)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
    }

    private func startGenerate() {
        if enrichWithAtmosphere { showAtmosphere = true } else { runGenerate() }
    }
    private func runGenerate() {
        // Real: POST /memoir/generate { title, style, tone, word_target: words,
        //   start_year, end_year, include_images, dedication } (+ atmosphere already saved)
        withAnimation { phase = .generating }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { withAnimation { phase = .ready } }
    }
}

// MARK: - Presets (verbatim from web + an Epic option for a full life story)
struct WordTarget: Identifiable {
    let value: Int; let label: String; let detail: String; let needsBackend: Bool
    var id: Int { value }
    static let all: [WordTarget] = [
        .init(value: 3000,   label: "Short",    detail: "A focused keepsake essay", needsBackend: false),
        .init(value: 10000,  label: "Standard", detail: "A concise personal book", needsBackend: false),
        .init(value: 20000,  label: "Medium",   detail: "A fuller memoir draft", needsBackend: false),
        .init(value: 40000,  label: "Long",     detail: "A serious manuscript", needsBackend: false),
        .init(value: 70000,  label: "Book",     detail: "Full book-length memoir", needsBackend: false),
        .init(value: 150000, label: "Epic",     detail: "A complete life story", needsBackend: true),
    ]
}

struct MemoirStyle: Identifiable {
    let id: String; let label: String; let desc: String
    static let all: [MemoirStyle] = [
        .init(id: "narrative",   label: "Narrative",   desc: "Told as a flowing story, scene by scene."),
        .init(id: "reflective",  label: "Reflective",  desc: "Thoughtful and introspective, weighing meaning."),
        .init(id: "documentary", label: "Documentary", desc: "Factual and grounded, close to the record."),
        .init(id: "storyteller", label: "Storyteller", desc: "Vivid scenes with sensory detail and emotional pacing."),
        .init(id: "legacy",      label: "Legacy",      desc: "Family-focused, preserving values for future generations."),
    ]
}
