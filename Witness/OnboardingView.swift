import SwiftUI

// MARK: - First-run onboarding — replicates the web app's app/onboarding/page.tsx exactly:
// 4 steps (name, birthdate, details, voice), same eyebrows/titles/prompts/why-text,
// same 6 voices, same field rules. Audio prompts/previews are shown as text here; the
// real voice playback is the voice-loop unit (§5/§6).
// Completion now gates on an explicit agreement to Terms, Privacy, and Security.
// Save (at completion):
//   POST /api/v1/settings/profile { first_name, last_name, birthdate, birthCity,
//        birthState, gender (trim||null), selectedVoice, companionName }  (server builds name)
//   POST /api/v1/auth/complete-onboarding
struct OnboardingView: View {
    var onFinish: () -> Void

    // Persisted — single source of truth read elsewhere (You, Talk, Record, memory detail).
    @AppStorage(Profile.firstNameKey) private var firstName: String = ""
    @AppStorage(Profile.companionNameKey) private var companionName: String = Profile.defaultCompanionName

    // Held locally; posted to /settings/profile at completion.
    @State private var lastName = ""
    @State private var birthdate = OnboardingView.defaultBirthdate
    @State private var birthdateSet = false
    @State private var showDatePicker = false
    @State private var birthCity = ""
    @State private var birthState = ""
    @State private var gender = ""
    @State private var selectedVoice = "playful_female"

    @State private var step = 0
    @State private var completed = false
    private let lastStep = 3

    // Legal acceptance gate (shown on the completion screen, before "Begin").
    @State private var legalDoc: LegalDoc?
    @State private var agreeTerms = false
    @State private var agreePrivacy = false
    @State private var agreeSecurity = false

    var body: some View {
        ZStack {
            ParchmentBackground()
            if completed {
                completionView
            } else {
                VStack(spacing: 0) {
                    topBar
                    ScrollView(showsIndicators: false) {
                        stepContent
                            .padding(.horizontal, 28)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity))
                            .id(step)
                    }
                    bottomButton
                }
            }
        }
        .sheet(isPresented: $showDatePicker) { datePickerSheet }
    }

    // MARK: Top bar — numbered step dots (check when complete, gold ring active)
    private var topBar: some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(0...lastStep, id: \.self) { i in
                    stepDot(i)
                    if i < lastStep {
                        Rectangle().fill(i < step ? WV.teal : WT.ink.opacity(0.12))
                            .frame(width: 26, height: 1)
                    }
                }
            }
            HStack {
                if step > 0 {
                    Button { withAnimation { step -= 1 } } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.6))
                            .frame(width: 44, height: 44)
                    }
                    .witnessPress()
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
    }

    private func stepDot(_ i: Int) -> some View {
        let complete = i < step
        let active = i == step
        return ZStack {
            Circle()
                .fill(complete ? WV.teal : (active ? WV.gold : Color.white))
                .overlay(Circle().stroke(active ? WV.gold.opacity(0.35) : WT.ink.opacity(0.1),
                                         lineWidth: active ? 4 : 1))
            if complete {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            } else {
                Text("\(i + 1)").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(active ? WT.ink : WT.ink.opacity(0.4))
            }
        }
        .frame(width: 34, height: 34)
    }

    // MARK: Step content
    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0: nameStep
        case 1: birthdateStep
        case 2: detailsStep
        default: voiceStep
        }
    }

    // Shared header: eyebrow + title + the companion's prompt + the "why" line.
    private func stepHeader(eyebrow: String, title: String, prompt: String, why: String, whyHint: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .semibold)).tracking(1.6).foregroundStyle(WV.gold)
            Text(title).font(.serif(28)).foregroundStyle(WT.ink)
                .fixedSize(horizontal: false, vertical: true)
            companionPrompt(prompt)
            HStack(alignment: .top, spacing: 6) {
                Text(why).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .witnessHint(whyHint, at: .topTrailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func companionPrompt(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SCARLETT  ✦").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(WV.gold)
            Text(text).font(.serif(16)).foregroundStyle(WT.ink.opacity(0.8)).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xfaf7f0), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.06), lineWidth: 1))
    }

    // MARK: Step 1 — name
    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader(eyebrow: "Identity Anchor", title: "Begin with your name.",
                       prompt: "Hi there. I'm Scarlett — I'll be your companion as you preserve your life story. Let's start simple. What's your name?",
                       why: "Your name becomes the first anchor in the archive.",
                       whyHint: "Your name is the first anchor in your archive — everything else is organized around you.")
            field("First name", text: $firstName, autocap: .words)
            field("Last name", text: $lastName, autocap: .words)
        }
    }

    // MARK: Step 2 — birthdate
    private var birthdateStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader(eyebrow: "Chronological Truth", title: "Place your life on the timeline.",
                       prompt: "Nice to meet you. Now — when were you born?",
                       why: "Your birthdate helps Witness calculate age, sequence, and memory context.",
                       whyHint: "Your birth year lets Witness place every memory in time. “When I was 5” becomes a real date — so your whole life lines up in order, automatically.")
            Button { showDatePicker = true } label: {
                HStack {
                    Image(systemName: "calendar").font(.system(size: 17)).foregroundStyle(WV.teal)
                    Text(birthdateSet ? Self.dateFormatter.string(from: birthdate) : "Select your date of birth")
                        .font(.system(size: 16)).foregroundStyle(birthdateSet ? WT.ink : WT.ink.opacity(0.35))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
                }
                .padding(.horizontal, 16).frame(height: 56)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.12), lineWidth: 1))
            }
            .witnessPress()
        }
    }

    private var datePickerSheet: some View {
        VStack(spacing: 16) {
            Capsule().fill(WT.ink.opacity(0.15)).frame(width: 36, height: 5).padding(.top, 10)
            Text("Date of birth").font(.serif(22)).foregroundStyle(WV.teal)
            DatePicker("", selection: $birthdate, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel).labelsHidden()
            Button { birthdateSet = true; showDatePicker = false } label: {
                Text("Done").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(WV.teal, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .witnessPress()
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
        .background(WV.parchment)
        .presentationDetents([.height(420)])
    }

    // MARK: Step 3 — details (all optional)
    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader(eyebrow: "Origin Context", title: "Add the first traces of home.",
                       prompt: "Where were you born, or where do you consider home? And how do you identify — share however feels right, or skip this entirely.",
                       why: "Optional details help Scarlett understand place, background, and identity context.",
                       whyHint: "All optional. Place helps when Witness writes your memoir, grounding your story somewhere real. Identity is only for context — share however you like, or skip it.")
            field("City of birth (optional)", text: $birthCity, autocap: .words)
                .witnessHint("Optional. Where you're from helps Witness ground your memoir in a real place.")
            field("State or region (optional)", text: $birthState, autocap: .words)
            VStack(alignment: .leading, spacing: 5) {
                field("How do you identify? (optional)", text: $gender, autocap: .sentences)
                    .onChange(of: gender) { _, v in if v.count > 20 { gender = String(v.prefix(20)) } }
                    .witnessHint("Optional, and only for context. Share however feels right, or skip it entirely.")
                Text("\(gender.count)/20").font(.system(size: 11)).foregroundStyle(WT.ink.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: Step 4 — voice + companion name
    private var voiceStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader(eyebrow: "Scarlett Setup", title: "Choose the voice that will witness with you.",
                       prompt: "Last thing. You can choose how I sound and what you'd like to call me. Pick the voice that feels right.",
                       why: "This sets the tone for the companion who will help preserve and explore your memories.",
                       whyHint: "Just pick what you'd like your companion to sound like. You can change it any time later.")

            VStack(alignment: .leading, spacing: 7) {
                Text("WHAT WOULD YOU LIKE TO CALL YOUR COMPANION?")
                    .font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(WT.ink.opacity(0.45))
                field("Companion name", text: $companionName, autocap: .words)
                    .onChange(of: companionName) { _, v in if v.count > 30 { companionName = String(v.prefix(30)) } }
                    .witnessHint("Your companion answers to whatever you name it. Default is Scarlett — make it yours.")
            }

            VStack(alignment: .leading, spacing: 14) {
                voiceGroup("Female voices", gender: "female")
                voiceGroup("Male voices", gender: "male")
            }
            .padding(.top, 4)
            .witnessHint("Pick the voice you'd most like to hear. Previews play once the voice system is connected.")

            Text("Voice previews play once the voice system is connected.")
                .font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.4))
                .padding(.top, 2)
        }
    }

    private func voiceGroup(_ title: String, gender: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(WV.gold)
            ForEach(VoiceOption.all.filter { $0.gender == gender }) { v in
                voiceCard(v)
            }
        }
    }

    private func voiceCard(_ v: VoiceOption) -> some View {
        let sel = selectedVoice == v.id
        return Button { withAnimation(.easeOut(duration: 0.15)) { selectedVoice = v.id } } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(sel ? Color.white.opacity(0.2) : WV.teal.opacity(0.1))
                    Image(systemName: "waveform").font(.system(size: 16, weight: .medium))
                        .foregroundStyle(sel ? .white : WV.teal)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(v.label).font(.serif(18)).foregroundStyle(sel ? .white : WT.ink)
                    Text(v.desc).font(.system(size: 13)).foregroundStyle(sel ? .white.opacity(0.85) : WT.ink.opacity(0.55))
                }
                Spacer()
                if sel { Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(sel ? WV.teal : WV.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(sel ? Color.clear : WT.ink.opacity(0.08), lineWidth: 1))
            .shadow(color: WT.ink.opacity(sel ? 0.12 : 0.04), radius: sel ? 10 : 6, y: sel ? 5 : 3)
        }
        .witnessPress(scale: 0.98)
    }

    // MARK: Completion (web's warm greeting; now gated on legal agreement)
    private var completionView: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 16)
            CompassMark(color: WV.gold).frame(width: 56, height: 56)
            Text(firstName.trimmingCharacters(in: .whitespaces).isEmpty ? "Welcome." : "Welcome, \(firstName).")
                .font(.serif(30)).foregroundStyle(WV.teal).multilineTextAlignment(.center)
            Text("It's good to finally be here with you. A few quick agreements, and we'll begin.")
                .font(.serif(18)).foregroundStyle(WT.ink.opacity(0.7))
                .multilineTextAlignment(.center).lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 36)
            Spacer(minLength: 16)

            agreementCard.padding(.horizontal, 24)

            Button {
                // Real: POST /api/v1/settings/profile {first_name,last_name,birthdate,birthCity,
                //   birthState, gender: gender.trimmed || nil, selectedVoice, companionName}
                // then POST /api/v1/auth/complete-onboarding.
                onFinish()
            } label: {
                Text("Begin your witness")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(allAgreed ? WV.teal : WV.teal.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: WV.teal.opacity(allAgreed ? 0.3 : 0), radius: 10, y: 6)
            }
            .witnessPress()
            .disabled(!allAgreed)
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .sheet(item: $legalDoc) { LegalView(doc: $0) }
    }

    // The agreement gate: one "I agree" checkbox per document, each name tappable to read it.
    private var agreementCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BEFORE YOU BEGIN").font(.system(size: 11, weight: .semibold)).tracking(1.4).foregroundStyle(WV.gold)
            agreeRow(.terms, "Terms of Service", isOn: $agreeTerms)
            agreeRow(.privacy, "Privacy Policy", isOn: $agreePrivacy)
            agreeRow(.security, "Security policy", isOn: $agreeSecurity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
    }

    private func agreeRow(_ doc: LegalDoc, _ label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Button { withAnimation(.easeOut(duration: 0.12)) { isOn.wrappedValue.toggle() } } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(isOn.wrappedValue ? WV.teal : Color.white)
                    RoundedRectangle(cornerRadius: 7).stroke(isOn.wrappedValue ? WV.teal : WT.ink.opacity(0.25), lineWidth: 1.5)
                    if isOn.wrappedValue { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white) }
                }
                .frame(width: 28, height: 28)
            }
            .witnessPress(scale: 0.9)
            HStack(spacing: 0) {
                Text("I agree to the ").font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.7))
                Button { legalDoc = doc } label: {
                    Text(label).font(.system(size: 14, weight: .semibold)).foregroundStyle(WV.teal).underline()
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var allAgreed: Bool { agreeTerms && agreePrivacy && agreeSecurity }

    // MARK: Bottom button
    private var bottomButton: some View {
        Button { advance() } label: {
            Text("Continue")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(canAdvance ? WV.teal : WV.teal.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: WV.teal.opacity(canAdvance ? 0.3 : 0), radius: 10, y: 6)
        }
        .witnessPress()
        .disabled(!canAdvance)
        .padding(.horizontal, 24).padding(.bottom, 20).padding(.top, 4)
    }

    // MARK: Logic (matches web canAdvance)
    private var canAdvance: Bool {
        switch step {
        case 0: return !firstName.trimmingCharacters(in: .whitespaces).isEmpty
        case 1: return birthdateSet
        case 2: return true
        default: return !selectedVoice.isEmpty
        }
    }

    private func advance() {
        if step < lastStep {
            withAnimation { step += 1 }
        } else {
            if companionName.trimmingCharacters(in: .whitespaces).isEmpty {
                companionName = Profile.defaultCompanionName
            }
            withAnimation { completed = true }
        }
    }

    // MARK: Reusable field
    private func field(_ placeholder: String, text: Binding<String>, autocap: TextInputAutocapitalization) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 16)).foregroundStyle(WT.ink).tint(WV.teal)
            .textInputAutocapitalization(autocap)
            .padding(.horizontal, 16).frame(height: 54)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(WT.ink.opacity(0.12), lineWidth: 1))
    }

    // MARK: Helpers
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .long; return f
    }()
    static var defaultBirthdate: Date {
        var c = DateComponents(); c.year = 1970; c.month = 1; c.day = 1
        return Calendar.current.date(from: c) ?? Date()
    }
}

// MARK: - The six voices (verbatim from the web's VOICE_OPTIONS).
struct VoiceOption: Identifiable {
    let id: String
    let label: String
    let gender: String
    let desc: String
    static let all: [VoiceOption] = [
        .init(id: "warm_female",    label: "Warm",    gender: "female", desc: "Gentle and reassuring"),
        .init(id: "direct_female",  label: "Direct",  gender: "female", desc: "Clear and confident"),
        .init(id: "playful_female", label: "Playful", gender: "female", desc: "Light and energetic"),
        .init(id: "warm_male",      label: "Warm",    gender: "male",   desc: "Calm and steady"),
        .init(id: "direct_male",    label: "Direct",  gender: "male",   desc: "Strong and focused"),
        .init(id: "playful_male",   label: "Playful", gender: "male",   desc: "Friendly and upbeat"),
    ]
}
