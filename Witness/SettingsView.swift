import SwiftUI

// MARK: - Consolidated Settings — mirrors the web settings page + backend ProfileUpdate.
// Reads/writes locally for now; once wired: GET /api/v1/settings/profile (load),
// PUT /api/v1/settings/profile (save). Bigger sub-features link to placeholders.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var auth: AuthManager

    @AppStorage(Profile.firstNameKey) private var firstName: String = ""
    @AppStorage(Profile.lastNameKey) private var lastName: String = ""
    @AppStorage(Profile.companionNameKey) private var companionName: String = Profile.defaultCompanionName
    @AppStorage(Profile.birthdateKey) private var birthdateISO: String = ""
    @AppStorage(Profile.genderKey) private var gender: String = ""
    @AppStorage(Profile.birthCityKey) private var birthCity: String = ""
    @AppStorage(Profile.birthStateKey) private var birthState: String = ""
    @AppStorage(Profile.voiceKey) private var selectedVoice: String = "playful_female"
    @AppStorage(Profile.customVoiceNameKey) private var customVoiceName: String = ""
    @AppStorage(Profile.conversationModeKey) private var conversationMode: String = "text"
    @AppStorage(Profile.vadSilenceKey) private var vadSilence: Int = 10
    @AppStorage(Profile.textSizeKey) private var textSize: String = "medium"
    @AppStorage(Profile.themeKey) private var theme: String = "system"
    @AppStorage(Profile.memoryPrivacyKey) private var memoryPrivacy: String = "open"
    @AppStorage(Profile.enableDetailsKey) private var enableDetails: Bool = false
    @AppStorage(HintSettings.key) private var showHints: Bool = true

    @State private var savingDetails = false
    @State private var detailsError = false

    @State private var showDatePicker = false
    @State private var pickerDate = Date()

    // Edit-profile drafts (staged; committed to @AppStorage only on a successful PUT).
    @State private var draftFirst = ""
    @State private var draftLast = ""
    @State private var draftCompanion = ""
    @State private var draftVoice = "playful_female"
    @State private var originalVoice = "playful_female"   // to detect a voice change
    @State private var prefilled = false
    @State private var isSaving = false
    @State private var didSave = false
    @State private var saveError: SaveError?

    private enum SaveError: Equatable {
        case sessionExpired, validation, network, generic
        var message: String {
            switch self {
            case .sessionExpired: return "Your session has timed out. Please sign in again to save changes."
            case .validation:     return "Some details couldn't be saved. Please check them and try again."
            case .network:        return "We couldn't save your changes. Please check your connection and try again."
            case .generic:        return "Something went wrong saving your changes. Please try again."
            }
        }
        var actionTitle: String { self == .sessionExpired ? "Sign in" : "Try again" }
    }

    private var canSave: Bool { !draftFirst.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    editProfileSection
                    profileSection
                    conversationSection
                    appearanceSection
                    privacySection
                    advancedSection
                    hintsSection
                    moreSection
                    legalSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 120)
            }
            navBar
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showDatePicker) { datePickerSheet }
        .onAppear {
            guard !prefilled else { return }
            draftFirst = firstName; draftLast = lastName
            draftCompanion = companionName
            draftVoice = selectedVoice; originalVoice = selectedVoice
            prefilled = true
        }
        .onChange(of: draftFirst)     { _, _ in didSave = false; saveError = nil }
        .onChange(of: draftLast)      { _, _ in didSave = false; saveError = nil }
        .onChange(of: draftCompanion) { _, _ in didSave = false; saveError = nil }
        .onChange(of: draftVoice)     { _, _ in didSave = false; saveError = nil }
    }

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                    Text("You").font(.system(size: 16))
                }
                .foregroundStyle(WV.teal)
                .frame(height: 44)
            }
            .witnessPress()
            Spacer()
            Text("Settings").font(.serif(20)).foregroundStyle(WT.ink)
            Spacer()
            Color.clear.frame(width: 60, height: 44)
        }
        .padding(.horizontal, 16)
        .background(WV.parchment.opacity(0.96))
    }

    // MARK: Profile
    private var profileSection: some View {
        sectionCard("Profile", hint: "Your identity anchors. Name and birthdate help Witness place every memory in time; place and identity add context.") {
            Button { pickerDate = Self.date(fromISO: birthdateISO) ?? Self.defaultDOB; showDatePicker = true } label: {
                HStack {
                    Text("Date of birth").font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.7))
                    Spacer()
                    Text(birthdateISO.isEmpty ? "Set" : Self.displayDate(birthdateISO))
                        .font(.system(size: 15)).foregroundStyle(birthdateISO.isEmpty ? WV.teal : WT.ink)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
                }
                .frame(height: 48)
            }
            .buttonStyle(.plain)
            divider
            textRow("How you identify (optional)", text: $gender)
            divider
            textRow("City of birth (optional)", text: $birthCity)
            divider
            textRow("State or region (optional)", text: $birthState)
        }
    }

    // MARK: Edit profile (name + companion + voice) — the only section that saves to the backend (PUT).
    private var editProfileSection: some View {
        sectionCard("Edit profile", hint: "Your name, your companion's name, and the voice it speaks in. These are saved to your account.") {
            textRow("First name", text: $draftFirst)
            divider
            textRow("Last name", text: $draftLast)
            divider
            textRow("Companion name", text: $draftCompanion)
            divider
            VStack(alignment: .leading, spacing: 10) {
                Text("VOICE").font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(WT.ink.opacity(0.4))
                ForEach(VoiceOption.all) { v in draftVoiceRow(v) }
            }
            .padding(.vertical, 4)
            divider
            saveRow
        }
    }

    private func draftVoiceRow(_ v: VoiceOption) -> some View {
        let sel = draftVoice == v.id
        return Button { withAnimation(.easeOut(duration: 0.15)) { draftVoice = v.id } } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(sel ? .white : WV.teal)
                    .frame(width: 34, height: 34)
                    .background(sel ? WV.teal : WV.teal.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(v.label) · \(v.gender.capitalized)").font(.system(size: 15, weight: .medium)).foregroundStyle(WT.ink)
                    Text(v.desc).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5))
                }
                Spacer()
                if sel { Image(systemName: "checkmark.circle.fill").font(.system(size: 19)).foregroundStyle(WV.teal) }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var saveRow: some View {
        if let e = saveError {
            VStack(spacing: 10) {
                Text(e.message)
                    .font(.system(size: 13)).foregroundStyle(WV.danger)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button { handleErrorAction(e) } label: {
                    Text(e.actionTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(WV.teal, in: RoundedRectangle(cornerRadius: 14))
                }
                .witnessPress()
            }
            .padding(.vertical, 6)
        } else {
            Button { Task { await saveProfile() } } label: {
                Group {
                    if isSaving { ProgressView().tint(.white) }
                    else if didSave { Label("Saved", systemImage: "checkmark") }
                    else { Text("Save changes") }
                }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background((canSave && !isSaving) ? WV.teal : WV.teal.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!canSave || isSaving)
            .witnessPress()
            .padding(.vertical, 6)
        }
    }

    private func handleErrorAction(_ e: SaveError) {
        switch e {
        case .sessionExpired: auth.logout()          // ContentView's isLoggedIn watcher routes to the door
        default:              Task { await saveProfile() }   // validation/network/generic → retry (drafts preserved)
        }
    }

    private func saveProfile() async {
        saveError = nil; didSave = false; isSaving = true
        defer { isSaving = false }

        let voiceChanged = draftVoice != originalVoice
        let cName = draftCompanion.trimmingCharacters(in: .whitespaces)
        let companion = cName.isEmpty ? Profile.defaultCompanionName : cName
        let req = ProfileUpdateRequest(
            firstName: draftFirst.trimmingCharacters(in: .whitespaces),
            lastName: draftLast.trimmingCharacters(in: .whitespaces),
            companionName: companion,
            companionVoice: voiceChanged ? draftVoice : nil,
            companionPersonality: voiceChanged ? VoiceOption.personality(for: draftVoice) : nil,
            customVoiceName: voiceChanged ? VoiceOption.geminiName(for: draftVoice) : nil
        )
        do {
            try await auth.updateProfile(req)
            // Commit locally so the app reflects immediately (companion display + read-aloud/Talk voice).
            firstName = req.firstName ?? firstName
            lastName = req.lastName ?? lastName
            companionName = companion
            draftCompanion = companion                 // reflect the Scarlett default back into the field
            if voiceChanged {
                selectedVoice = draftVoice
                customVoiceName = VoiceOption.geminiName(for: draftVoice)
                originalVoice = draftVoice
            }
            didSave = true
        } catch {
            saveError = Self.mapError(error)           // stay put; drafts preserved
        }
    }

    private static func mapError(_ error: Error) -> SaveError {
        if let api = error as? APIError {
            switch api {
            case .unauthorized:   return .sessionExpired
            case .http(let s, _): return s == 400 ? .validation : .generic
            case .network:        return .network
            default:              return .generic
            }
        }
        return .generic
    }

    // MARK: Conversation
    private var conversationSection: some View {
        sectionCard("Conversation", hint: "How talking with your companion behaves by default.") {
            segmentedRow("Default mode", options: [("Text", "text"), ("Voice", "voice")], selection: $conversationMode)
            divider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    settingLabel("Silence before reply", "In voice mode, how long to wait once you stop speaking.")
                    Spacer()
                    Text("\(vadSilence)s").font(.system(size: 15, weight: .medium)).foregroundStyle(WV.teal)
                }
                Slider(value: Binding(get: { Double(vadSilence) }, set: { vadSilence = Int($0) }), in: 3...20, step: 1)
                    .tint(WV.teal)
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: Appearance
    private var appearanceSection: some View {
        sectionCard("Appearance", hint: "Text size and theme. (Applies app-wide once wired into the type system.)") {
            segmentedRow("Text size", options: [("Small", "small"), ("Medium", "medium"), ("Large", "large")], selection: $textSize)
            divider
            segmentedRow("Theme", options: [("System", "system"), ("Light", "light"), ("Dark", "dark")], selection: $theme)
        }
    }

    // MARK: Privacy
    private var privacySection: some View {
        sectionCard("Privacy", hint: "Whether new memories are open to your companion by default, or kept private.") {
            segmentedRow("New memories", options: [("Open", "open"), ("Private", "private")], selection: $memoryPrivacy)
        }
    }

    // MARK: Advanced (Enable Details View — saved to the profile as enable_graph_view)
    private var advancedSection: some View {
        sectionCard("Advanced", hint: "Extra detail surfaces for exploring the story more deeply.") {
            Toggle(isOn: Binding(get: { enableDetails }, set: { setEnableDetails($0) })) {
                settingLabel("Enable Details View", "Show entity details and advanced panels.")
            }
            .tint(WV.teal)
            .disabled(savingDetails)
            .padding(.vertical, 6)
            if detailsError {
                Text("Couldn’t save that setting — check your connection and try again.")
                    .font(.system(size: 12)).foregroundStyle(WV.danger).fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
            }
        }
    }

    private func setEnableDetails(_ on: Bool) {
        let previous = enableDetails
        enableDetails = on                         // optimistic local mirror (instant UI)
        detailsError = false; savingDetails = true
        Task {
            do {
                try await auth.updateProfile(ProfileUpdateRequest(
                    firstName: nil, lastName: nil, companionName: nil,
                    companionVoice: nil, companionPersonality: nil, customVoiceName: nil,
                    enableGraphView: on))
            } catch {
                enableDetails = previous           // revert on failure
                detailsError = true
            }
            savingDetails = false
        }
    }

    // MARK: Hints
    private var hintsSection: some View {
        sectionCard("Help", hint: nil) {
            Toggle(isOn: $showHints) {
                settingLabel("Show helpful hints", "Adds “?” badges that explain what controls do.")
            }
            .tint(WV.teal)
            .padding(.vertical, 6)
        }
    }

    // MARK: More (bigger features → placeholders)
    private var moreSection: some View {
        sectionCard("More", hint: nil) {
            NavigationLink { EntityAtlasView() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill").font(.system(size: 16, weight: .medium)).foregroundStyle(WV.teal)
                        .frame(width: 34, height: 34).background(WV.teal.opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Entity Atlas").font(.system(size: 15, weight: .medium)).foregroundStyle(WT.ink)
                        Text("Review every person and place — and merge duplicates into one.")
                            .font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
                }
                .padding(.vertical, 8).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            divider
            navRow("photo.on.rectangle.angled", "Visual identity timeline", "How you've looked over time — anchors image generation.",
                   endpoint: "GET /api/v1/settings/appearance-timeline")
            divider
            navRow("externaldrive", "Data & account", "Manage what's stored, and remove anything you choose.", endpoint: nil)
                    }
                }

            // MARK: Legal
            private var legalSection: some View {
                sectionCard("Legal", hint: nil) {
                    legalRow("Privacy Policy", doc: .privacy)
                    divider
                    legalRow("Security", doc: .security)
                    divider
                    legalRow("Terms of Service", doc: .terms)
                }
            }
            private func legalRow(_ title: String, doc: LegalDoc) -> some View {
                NavigationLink { LegalView(doc: doc) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: doc.icon).font(.system(size: 16, weight: .medium)).foregroundStyle(WV.teal)
                            .frame(width: 34, height: 34).background(WV.teal.opacity(0.1), in: Circle())
                        Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(WT.ink)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
                    }
                    .padding(.vertical, 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

    // MARK: Building blocks
    private func sectionCard<Content: View>(_ title: String, hint: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(1.4).foregroundStyle(WV.gold)
            }
            .modifier(OptionalHint(text: hint))
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 16).padding(.vertical, 4)
                .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
                .shadow(color: WT.ink.opacity(0.04), radius: 8, y: 4)
        }
    }

    private var divider: some View { Rectangle().fill(WT.ink.opacity(0.06)).frame(height: 1) }

    private func settingLabel(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(WT.ink)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func textRow(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 15)).foregroundStyle(WT.ink).tint(WV.teal)
            .textInputAutocapitalization(.words)
            .frame(height: 48)
    }

    private func segmentedRow(_ title: String, options: [(String, String)], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(WT.ink)
            HStack(spacing: 4) {
                ForEach(options, id: \.1) { opt in
                    let sel = selection.wrappedValue == opt.1
                    Text(opt.0)
                        .font(.system(size: 14, weight: sel ? .semibold : .regular))
                        .foregroundStyle(sel ? .white : WT.ink.opacity(0.6))
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(sel ? WV.teal : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { selection.wrappedValue = opt.1 } }
                }
            }
            .padding(4)
            .background(WT.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.vertical, 8)
    }

    private func navRow(_ icon: String, _ title: String, _ subtitle: String, endpoint: String?) -> some View {
        NavigationLink { SettingsDetailPlaceholder(icon: icon, title: title, subtitle: subtitle, endpoint: endpoint) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .medium)).foregroundStyle(WV.teal)
                    .frame(width: 34, height: 34).background(WV.teal.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(WT.ink)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var datePickerSheet: some View {
        VStack(spacing: 16) {
            Capsule().fill(WT.ink.opacity(0.15)).frame(width: 36, height: 5).padding(.top, 10)
            Text("Date of birth").font(.serif(22)).foregroundStyle(WV.teal)
            DatePicker("", selection: $pickerDate, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel).labelsHidden()
            Button { birthdateISO = Self.iso(pickerDate); showDatePicker = false } label: {
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

    // MARK: Date helpers
    static func iso(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d) }
    static func date(fromISO s: String) -> Date? { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: s) }
    static func displayDate(_ iso: String) -> String {
        guard let d = date(fromISO: iso) else { return iso }
        let f = DateFormatter(); f.dateStyle = .long; return f.string(from: d)
    }
    static var defaultDOB: Date {
        var c = DateComponents(); c.year = 1970; c.month = 1; c.day = 1
        return Calendar.current.date(from: c) ?? Date()
    }
}

// Shows a "?" hint next to a section title only when hint text is present.
private struct OptionalHint: ViewModifier {
    let text: String?
    func body(content: Content) -> some View {
        if let text { content.witnessHint(text, at: .trailing) } else { content }
    }
}

struct SettingsDetailPlaceholder: View {
    let icon: String; let title: String; let subtitle: String; let endpoint: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            VStack(spacing: 16) {
                Spacer()
                ZStack { Circle().fill(WV.teal.opacity(0.12)); Image(systemName: icon).font(.system(size: 30, weight: .medium)).foregroundStyle(WV.teal) }
                    .frame(width: 76, height: 76)
                Text(title).font(.serif(28)).foregroundStyle(WV.teal).multilineTextAlignment(.center)
                Text(subtitle).font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.6))
                    .multilineTextAlignment(.center).lineSpacing(3).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 40)
                Text("This view is coming together.").font(.system(size: 13, weight: .medium)).foregroundStyle(WT.ink.opacity(0.4)).padding(.top, 4)
                if let endpoint {
                    Text(endpoint).font(.system(size: 11, design: .monospaced)).foregroundStyle(WT.ink.opacity(0.35))
                        .padding(.horizontal, 12).padding(.vertical, 6).background(WV.card, in: Capsule())
                        .overlay(Capsule().stroke(WT.ink.opacity(0.08), lineWidth: 1)).padding(.top, 2)
                }
                Spacer(); Spacer()
            }
            .frame(maxWidth: .infinity)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.8))
                        .frame(width: 44, height: 44).background(Color.white, in: Circle())
                        .overlay(Circle().stroke(WT.ink.opacity(0.08), lineWidth: 1)).shadow(color: WT.ink.opacity(0.1), radius: 4, y: 2)
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
