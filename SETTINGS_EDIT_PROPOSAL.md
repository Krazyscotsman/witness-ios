# Witness — Profile/Settings edit via PUT — Full implementation diffs (Option A)

Status: **PROPOSED — nothing applied, no build, no git.** Awaiting review/approval.
Approved basis: Option A (single "Edit profile" section, duplicate inline controls removed) + thread `auth` +
drop the manual "Custom voice name" field + any-2xx PUT. Voice mapping reused from onboarding.

---

## 1) APIClient.swift — add a body-ignoring PUT
Add after the `post(...)` method. Treats any 2xx as success; does NOT decode the response (tolerates
204/empty/ack bodies whose shape isn't documented). Still throws on 401 / non-2xx / transport.
```swift
    /// PUT that treats any 2xx as success and does NOT decode the response body (the PUT ack shape isn't
    /// guaranteed — could be {status,...}, empty, or 204). Throws APIError on 401 / non-2xx / transport,
    /// same as `request(...)`. Returns the raw bytes in case a caller wants to leniently try-decode.
    @discardableResult
    func putIgnoringResponseBody<Body: Encodable>(
        _ path: String, body: Body, authorized: Bool = true, timeout: TimeInterval? = nil
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: Self.baseURL) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        if let timeout { req.timeoutInterval = timeout }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do { req.httpBody = try JSONEncoder().encode(body) } catch { throw APIError.encoding(error) }
        if authorized, let token = tokenProvider() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch { throw APIError.network(error) }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network(URLError(.badServerResponse))
        }
        if http.statusCode == 401 {
            let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw APIError.unauthorized(detail: parsed?.detail, code: parsed?.code)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        return data   // any 2xx = success
    }
```
(Deliberate small transport duplication of `request(...)`'s setup — avoids refactoring the working
get/post path. `ErrorBody` is the fileprivate struct already in this file.)

## 2) APIModels.swift — ProfileUpdateRequest (partial)
Add after `ProfileCreateResponse`.
```swift
/// PUT /api/v1/settings/profile body (partial update). All optional → nil fields are omitted (synthesized
/// encodeIfPresent), so unmanaged fields are never sent and server-side nulls are avoided. The editor always
/// sends first_name/last_name/companion_name; it sends the three voice fields ONLY when the voice changed.
struct ProfileUpdateRequest: Encodable {
    let firstName: String?
    let lastName: String?
    let companionName: String?
    let companionVoice: String?
    let companionPersonality: String?
    let customVoiceName: String?

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case companionName = "companion_name"
        case companionVoice = "companion_voice"
        case companionPersonality = "companion_personality"
        case customVoiceName = "custom_voice_name"
    }
}
```

## 3) AuthManager.swift — updateProfile
Add near `saveOnboardingProfile`.
```swift
    /// Settings edit. PUT /settings/profile is a partial update; any 2xx is success (ack body not decoded).
    /// Throws APIError; the view maps it to friendly copy. Local @AppStorage is committed by the view on success.
    func updateProfile(_ body: ProfileUpdateRequest) async throws {
        _ = try await api.putIgnoringResponseBody("/api/v1/settings/profile", body: body, timeout: 20)
    }
```

## 4) MainTabView.swift — pass auth to YouView
```diff
-            case .you:      YouView(path: $youPath, onSignOut: onSignOut)
+            case .you:      YouView(auth: auth, path: $youPath, onSignOut: onSignOut)
```

## 5) YouView.swift — take auth, pass it to SettingsView
```diff
 struct YouView: View {
+    @ObservedObject var auth: AuthManager
     @Binding var path: NavigationPath
     var onSignOut: () -> Void
```
```diff
-            .navigationDestination(for: YouRoute.self) { _ in SettingsView() }
+            .navigationDestination(for: YouRoute.self) { _ in SettingsView(auth: auth) }
```

## 6) SettingsView.swift — Option A rework

### 6a) Take auth + draft/save state (add near the top, after the @AppStorage block)
```diff
 struct SettingsView: View {
     @Environment(\.dismiss) private var dismiss
+    @ObservedObject var auth: AuthManager
```
```swift
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
```

### 6b) body — add the Edit-profile section first + prefill + clear-on-edit
```diff
             VStack(spacing: 22) {
+                editProfileSection
                 profileSection
                 companionSection
                 conversationSection
                 appearanceSection
                 privacySection
                 hintsSection
                 moreSection
                 legalSection
             }
```
```diff
         .navigationBarBackButtonHidden(true)
         .toolbar(.hidden, for: .navigationBar)
         .sheet(isPresented: $showDatePicker) { datePickerSheet }
+        .onAppear {
+            guard !prefilled else { return }
+            draftFirst = firstName; draftLast = lastName
+            draftCompanion = companionName
+            draftVoice = selectedVoice; originalVoice = selectedVoice
+            prefilled = true
+        }
+        .onChange(of: draftFirst)     { _, _ in didSave = false; saveError = nil }
+        .onChange(of: draftLast)      { _, _ in didSave = false; saveError = nil }
+        .onChange(of: draftCompanion) { _, _ in didSave = false; saveError = nil }
+        .onChange(of: draftVoice)     { _, _ in didSave = false; saveError = nil }
```

### 6c) NEW editProfileSection + draft voice row + save/err + logic
```swift
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
```

### 6d) profileSection — remove the (now-duplicate) name rows
```diff
     private var profileSection: some View {
         sectionCard("Profile", hint: "Your identity anchors. Name and birthdate help Witness place every memory in time; place and identity add context.") {
-            textRow("First name", text: $firstName)
-            divider
-            textRow("Last name", text: $lastName)
-            divider
             Button { pickerDate = Self.date(fromISO: birthdateISO) ?? Self.defaultDOB; showDatePicker = true } label: {
```
(Everything from the DOB button down is unchanged.)

### 6e) companionSection — remove companion-name + voice list + manual custom-voice field; keep the toggle
```diff
-    // MARK: Companion & voice
-    private var companionSection: some View {
-        sectionCard("Companion & voice", hint: "Name your companion and choose how it sounds. You can change these any time.") {
-            textRow("Companion name", text: $companionName)
-            divider
-            VStack(alignment: .leading, spacing: 10) {
-                Text("VOICE").font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(WT.ink.opacity(0.4))
-                ForEach(VoiceOption.all) { v in voiceRow(v) }
-            }
-            .padding(.vertical, 4)
-            divider
-            textRow("Custom voice name (optional)", text: $customVoiceName)
-            divider
-            Toggle(isOn: $voiceConfirm) {
-                settingLabel("Voice confirmation", "Speak a short confirmation after voice actions.")
-            }
-            .tint(WV.teal)
-            .padding(.vertical, 6)
-        }
-    }
-
-    private func voiceRow(_ v: VoiceOption) -> some View {
-        let sel = selectedVoice == v.id
-        return Button { withAnimation(.easeOut(duration: 0.15)) { selectedVoice = v.id } } label: {
-            HStack(spacing: 12) {
-                Image(systemName: "waveform").font(.system(size: 15, weight: .medium))
-                    .foregroundStyle(sel ? .white : WV.teal)
-                    .frame(width: 34, height: 34)
-                    .background(sel ? WV.teal : WV.teal.opacity(0.1), in: Circle())
-                VStack(alignment: .leading, spacing: 1) {
-                    Text("\(v.label) · \(v.gender.capitalized)").font(.system(size: 15, weight: .medium)).foregroundStyle(WT.ink)
-                    Text(v.desc).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5))
-                }
-                Spacer()
-                if sel { Image(systemName: "checkmark.circle.fill").font(.system(size: 19)).foregroundStyle(WV.teal) }
-            }
-            .padding(.vertical, 6)
-            .contentShape(Rectangle())
-        }
-        .buttonStyle(.plain)
-    }
+    // MARK: Voice behavior (identity/voice selection now lives in "Edit profile")
+    private var companionSection: some View {
+        sectionCard("Voice", hint: "How your companion's voice behaves.") {
+            Toggle(isOn: $voiceConfirm) {
+                settingLabel("Voice confirmation", "Speak a short confirmation after voice actions.")
+            }
+            .tint(WV.teal)
+            .padding(.vertical, 6)
+        }
+    }
```
Note: `customVoiceName` (@AppStorage) is now written only by `saveProfile` (the derived Gemini name) — the
manual field is gone. `selectedVoice`/`companionName`/`firstName`/`lastName` @AppStorage remain (committed by
save, read app-wide). No other references to the removed `voiceRow` exist.

---

## Test path this unlocks (the point of doing this one)
Edit profile → pick a different voice → Save → (PUT 200) → local `Profile.voiceKey` updates → open a memory →
Read aloud → `Speaker.voiceSelection()` reads `profile.voice` → speaks in the new voice. Verifies
custom_voice_name/voice → playback end-to-end and exercises the shared onboarding mapping.

## Verification plan after approval
Build 0/0 + per-file diagnostics (APIClient, APIModels, AuthManager, MainTabView, YouView, SettingsView).
Honest note: live PUT round-trip (200/400/401) is a device/backend check — I'll flag it as not-yet-exercised.
No git.
```
