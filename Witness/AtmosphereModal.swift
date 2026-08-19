import SwiftUI

// MARK: - Atmosphere interview (optional, best-effort). Consumes the real prompts (MemoirPeriodDTO, already
// loaded by the VM) and POSTs each non-empty answer via /api/v1/memoir/atmosphere before generation. One period
// at a time, dot progress, multi-line fields, "optional but encouraged" framing; skip a question (leave blank),
// skip a period (Next), or Skip All — all supported. Any failure is swallowed (the interview is optional).
struct AtmosphereModal: View {
    @ObservedObject var vm: MemoirAtmosphereViewModel
    let auth: AuthManager
    var onComplete: () -> Void   // save (best-effort) + generate
    var onCancel: () -> Void

    @State private var idx = 0
    @State private var answers: [[String]] = []   // [periodIndex][promptIndex]
    @State private var submitting = false

    private var periods: [MemoirPeriodDTO] { vm.periods }
    private var isLast: Bool { idx >= periods.count - 1 }

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            VStack(spacing: 0) {
                topBar
                if periods.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            intro
                            periodHeader
                            let prompts = periods[idx].prompts ?? []
                            ForEach(Array(prompts.enumerated()), id: \.offset) { j, prompt in
                                promptBlock(prompt.promptText ?? "Tell me about this time.", answer: binding(j))
                            }
                        }
                        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
                        .id(idx)
                    }
                    bottomBar
                }
            }
        }
        .onAppear(perform: ensureAnswers)
    }

    private var topBar: some View {
        HStack {
            Button { onCancel() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.7))
                    .frame(width: 44, height: 44).background(Color.white, in: Circle())
                    .overlay(Circle().stroke(WT.ink.opacity(0.08), lineWidth: 1))
            }
            .witnessPress()
            .disabled(submitting)
            Spacer()
            Button { finish() } label: {
                Text("Skip All & Generate").font(.system(size: 14, weight: .medium)).foregroundStyle(WT.ink.opacity(0.55)).frame(height: 44)
            }
            .witnessPress()
            .disabled(submitting)
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles").font(.system(size: 16)).foregroundStyle(WV.gold)
                Text("Help Us Bring Your Memoir to Life").font(.serif(24)).foregroundStyle(WV.teal)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("A few vivid details about your world make the difference between a generic memoir and one that feels truly yours — what places looked like, the daily rhythm, the feel of each era. Optional, but even a few words help.")
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.6)).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var periodHeader: some View {
        let p = periods[idx]
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PERIOD \(idx + 1) OF \(periods.count)").font(.system(size: 11, weight: .semibold)).tracking(1.4).foregroundStyle(WV.gold)
                Spacer()
            }
            Text(p.lifePeriod ?? "This period").font(.serif(22)).foregroundStyle(WT.ink)
            if let sub = periodSubtitle(p) {
                Text(sub).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.5))
            }
            HStack(spacing: 6) {
                ForEach(0..<periods.count, id: \.self) { i in
                    Capsule().fill(i == idx ? WV.teal : (i < idx ? WV.teal.opacity(0.4) : WT.ink.opacity(0.12)))
                        .frame(width: i == idx ? 20 : 7, height: 7)
                }
            }
            .padding(.top, 4)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private func periodSubtitle(_ p: MemoirPeriodDTO) -> String? {
        var parts: [String] = []
        if let loc = p.location?.trimmingCharacters(in: .whitespaces), !loc.isEmpty { parts.append(loc) }
        switch (p.yearStart, p.yearEnd) {
        case let (s?, e?): parts.append("\(s)–\(e)")
        case let (s?, nil): parts.append("\(s)–now")
        case let (nil, e?): parts.append("…–\(e)")
        default: break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func promptBlock(_ question: String, answer: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question).font(.serif(17)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
            ZStack(alignment: .topLeading) {
                if answer.wrappedValue.isEmpty {
                    Text("Write anything you remember — even a few words help…")
                        .font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.35))
                        .padding(.horizontal, 14).padding(.vertical, 12)
                }
                TextEditor(text: answer)
                    .font(.system(size: 15)).foregroundStyle(WT.ink).tint(WV.teal)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10).padding(.vertical, 6).frame(minHeight: 96)
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(WT.ink.opacity(0.12), lineWidth: 1))
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if idx > 0 {
                Button { withAnimation { idx -= 1 } } label: {
                    Text("Back").font(.system(size: 16, weight: .medium)).foregroundStyle(WT.ink.opacity(0.6))
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.12), lineWidth: 1))
                }
                .witnessPress().disabled(submitting)
            }
            Button {
                if isLast { finish() } else { withAnimation { idx += 1 } }
            } label: {
                HStack(spacing: 8) {
                    if submitting && isLast { ProgressView().tint(.white) }
                    Text(isLast ? "Save & Generate" : "Next period")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(WV.teal, in: RoundedRectangle(cornerRadius: 16))
            }
            .witnessPress().disabled(submitting)
        }
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 12)
        .background(WV.parchment.overlay(alignment: .top) { Rectangle().fill(WT.ink.opacity(0.06)).frame(height: 1) })
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("No atmosphere prompts right now").font(.serif(20)).foregroundStyle(WT.ink)
            Text("You can still generate your memoir from your memories.")
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 30)
            Button { finish() } label: {
                Text("Continue to generate").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 24).frame(height: 52).background(WV.teal, in: RoundedRectangle(cornerRadius: 16))
            }
            .witnessPress().padding(.top, 4)
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: state helpers
    private func ensureAnswers() {
        guard answers.isEmpty else { return }
        answers = periods.map { ($0.prompts ?? []).map { _ in "" } }
    }
    private func binding(_ j: Int) -> Binding<String> {
        Binding(
            get: { (idx < answers.count && j < answers[idx].count) ? answers[idx][j] : "" },
            set: { if idx < answers.count && j < answers[idx].count { answers[idx][j] = $0 } }
        )
    }
    private func finish() {
        guard !submitting else { return }
        submitting = true
        Task {
            await vm.submit(collectAnswers(), auth: auth)
            submitting = false
            onComplete()
        }
    }
    private func collectAnswers() -> [MemoirAtmosphereRequest] {
        var out: [MemoirAtmosphereRequest] = []
        for (i, p) in periods.enumerated() {
            let prompts = p.prompts ?? []
            for (j, prompt) in prompts.enumerated() {
                guard i < answers.count, j < answers[i].count else { continue }
                let text = answers[i][j].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                out.append(MemoirAtmosphereRequest(
                    lifePeriod: p.lifePeriod ?? "", location: p.location ?? "",
                    yearStart: p.yearStart, yearEnd: p.yearEnd,
                    promptCategory: prompt.promptCategory ?? "", promptText: prompt.promptText ?? "",
                    responseText: text))
            }
        }
        return out
    }
}
