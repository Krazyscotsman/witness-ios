import SwiftUI

// MARK: - Atmosphere modal (the "Hope update"): collects vivid, period-aware world
// details before memoir generation — what places looked like, daily routines, the feel
// of each era. This is what turns a generic memoir into a powerful one.
//   GET  /api/v1/memoir/atmosphere-prompts  -> life periods, each with context-aware prompts
//   POST /api/v1/memoir/atmosphere          -> save answers, then generate
// Periods/prompts below are samples mirroring the backend's period-aware generation.
struct AtmosphereModal: View {
    var onComplete: () -> Void   // save + generate
    var onCancel: () -> Void

    @State private var periods: [AtmospherePeriod] = AtmospherePeriod.samples
    @State private var idx = 0

    private var period: AtmospherePeriod { periods[idx] }
    private var isLast: Bool { idx == periods.count - 1 }

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            VStack(spacing: 0) {
                topBar
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        intro
                        periodHeader
                        ForEach(Array(period.prompts.enumerated()), id: \.element.id) { j, prompt in
                            promptBlock(prompt.question, answer: binding(j))
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
                    .id(idx)
                }
                bottomBar
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button { onCancel() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.7))
                    .frame(width: 44, height: 44).background(Color.white, in: Circle())
                    .overlay(Circle().stroke(WT.ink.opacity(0.08), lineWidth: 1))
            }
            .witnessPress()
            Spacer()
            Button { /* POST /api/v1/memoir/atmosphere (skip) */ onComplete() } label: {
                Text("Skip All & Generate").font(.system(size: 14, weight: .medium)).foregroundStyle(WT.ink.opacity(0.55)).frame(height: 44)
            }
            .witnessPress()
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
            Text("A few vivid details about your world make the difference between a generic memoir and one that feels truly yours — what places looked like, the daily rhythm, the feel of each era. Even a few words help.")
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.6)).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var periodHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PERIOD \(idx + 1) OF \(periods.count)").font(.system(size: 11, weight: .semibold)).tracking(1.4).foregroundStyle(WV.gold)
                Spacer()
            }
            Text(period.lifePeriod).font(.serif(22)).foregroundStyle(WT.ink)
            Text("\(period.location) · ages \(period.ageStart)–\(period.ageEnd)")
                .font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.5))
            // progress dots
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
                .witnessPress()
            }
            Button {
                if isLast { /* POST /api/v1/memoir/atmosphere */ onComplete() }
                else { withAnimation { idx += 1 } }
            } label: {
                Text(isLast ? "Save & Generate" : "Next period")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(WV.teal, in: RoundedRectangle(cornerRadius: 16))
            }
            .witnessPress()
        }
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 12)
        .background(WV.parchment.overlay(alignment: .top) { Rectangle().fill(WT.ink.opacity(0.06)).frame(height: 1) })
    }

    private func binding(_ j: Int) -> Binding<String> {
        Binding(get: { periods[idx].prompts[j].answer }, set: { periods[idx].prompts[j].answer = $0 })
    }
}

// MARK: - Period + prompt models (backend returns these via atmosphere-prompts)
struct AtmospherePeriod: Identifiable {
    let id = UUID()
    let lifePeriod: String
    let location: String
    let ageStart: Int
    let ageEnd: Int
    let isMilitary: Bool
    let isSchoolAge: Bool
    var prompts: [AtmospherePromptItem]

    static let samples: [AtmospherePeriod] = [
        .init(lifePeriod: "Childhood", location: "your earliest home", ageStart: 0, ageEnd: 12, isMilitary: false, isSchoolAge: false,
              prompts: [
                .init("What did your home look like, inside and out?"),
                .init("What did an ordinary day look like, from morning to night?"),
                .init("What sounds, smells, and textures do you remember most?"),
              ]),
        .init(lifePeriod: "The base years", location: "the base where your family lived", ageStart: 12, ageEnd: 18, isMilitary: true, isSchoolAge: false,
              prompts: [
                .init("What did the base look like — the housing, the streets, the gates and checkpoints?"),
                .init("What was the daily rhythm of life on base?"),
                .init("Where did families and kids gather? What was the community like?"),
              ]),
        .init(lifePeriod: "High school", location: "your high school", ageStart: 14, ageEnd: 18, isMilitary: false, isSchoolAge: true,
              prompts: [
                .init("What did the school look like from the outside?"),
                .init("What did the inside look like — the hallways, the classrooms, the cafeteria, the gym?"),
                .init("What did a school day feel like, from the first bell to the last?"),
                .init("Who and what filled your days — friends, teachers, routines, rituals?"),
              ]),
        .init(lifePeriod: "Early adulthood", location: "where you set out on your own", ageStart: 18, ageEnd: 26, isMilitary: false, isSchoolAge: false,
              prompts: [
                .init("Where were you living, and what did the place look like?"),
                .init("What did your days revolve around — work, people, habits?"),
                .init("What did that chapter of life feel like at the time?"),
              ]),
    ]
}

struct AtmospherePromptItem: Identifiable {
    let id = UUID()
    let question: String
    var answer: String = ""
    init(_ question: String) { self.question = question }
}
