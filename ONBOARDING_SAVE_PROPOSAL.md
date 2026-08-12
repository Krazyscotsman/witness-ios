# Witness — Wire onboarding save (POST /api/v1/settings/profile) — Proposal

Status: **PROPOSED — nothing applied. Awaiting approval (esp. decision #1, the 204 question).** No git.
One call only — POST /settings/profile saves the profile AND flips onboarding_completed. Do NOT call
/auth/complete-onboarding.

## Read-first findings
- Completion: completionView "Begin your witness" Button { onFinish() }, disabled(!allAgreed). onFinish
  (ContentView) routes to .main; no network. OnboardingView has no `auth` today.
- Fields: firstName @AppStorage(firstNameKey); lastName @State; birthdate:Date + birthdateSet @State (default
  1970-01-01, only a .long display formatter); birthCity/birthState/gender @State (gender ≤20); companionName
  @AppStorage(companionNameKey) (empty → "Scarlett" in advance()); selectedVoice @State id (default
  "playful_female"). VoiceOption.all: id/label/gender/desc — no Gemini name/map.
- Profile keys: lastNameKey/birthdateKey/voiceKey/customVoiceNameKey/defaultCompanionName. APIClient.post
  throws APIError (.unauthorized/.http(status,_)/.network/.decoding).

## Decisions (baked in; change any)
1. POST returns a JSON object (decoded lenient as ProfileDTO). RISK: 204/empty → APIClient decode throws →
   false failure. Confirm JSON, else add empty-tolerant path.
2. 401 → auth.logout() → ContentView isLoggedIn watcher routes to .threshold (behind a "Sign in" button).
3. Optional details nil-when-empty (omitted); last_name always "" (never omitted); companion_name always sent.
4. Persist exactly lastName/birthdate/selectedVoice/geminiName to Profile keys; details POSTed but not stored.
5. badDate action → back to DOB step (completed=false; step=1), not a bare retry.
6. Save timeout 20s.

---

## APIModels.swift — ProfileCreateRequest
```swift
/// POST /api/v1/settings/profile body. Saves the profile AND flips onboarding_completed (one call).
/// first_name / last_name / birth_date are ALWAYS sent (last_name "" when empty — never omitted).
/// Optional details are omitted when nil (synthesized encodeIfPresent). All three voice fields always sent;
/// custom_voice_name (Gemini name) is what drives playback.
struct ProfileCreateRequest: Encodable {
    let firstName: String
    let lastName: String
    let birthDate: String            // yyyy-MM-dd (en_US_POSIX)
    let birthCity: String?
    let birthState: String?
    let gender: String?
    let companionName: String
    let companionVoice: String
    let companionPersonality: String
    let customVoiceName: String

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case birthDate = "birth_date"
        case birthCity = "birth_city"
        case birthState = "birth_state"
        case gender
        case companionName = "companion_name"
        case companionVoice = "companion_voice"
        case companionPersonality = "companion_personality"
        case customVoiceName = "custom_voice_name"
    }
}
```

## AuthManager.swift — save method
```swift
    /// Onboarding save. POST /settings/profile persists the profile AND flips onboarding_completed server-side
    /// (single call — no /auth/complete-onboarding). Throws APIError; the view maps it to friendly copy.
    func saveOnboardingProfile(_ body: ProfileCreateRequest) async throws {
        let resp = try await api.post("/api/v1/settings/profile", body: body, timeout: 20, as: ProfileDTO.self)
        onboardingCompleted = resp.onboardingCompleted ?? true
    }
```
(NOTE: assumes a JSON-object response — see decision #1.)

## OnboardingView.swift — voice mapping (VERBATIM), request build, save + errors

### VoiceOption helpers
```swift
extension VoiceOption {
    /// Gemini voice name that actually drives playback. Authoritative mapping — do not guess.
    static func geminiName(for id: String) -> String {
        switch id {
        case "warm_female":    return "Kore"
        case "direct_female":  return "Leda"
        case "playful_female": return "Aoede"
        case "warm_male":      return "Orus"
        case "direct_male":    return "Charon"
        case "playful_male":   return "Puck"
        default:               return "Aoede"   // playful_female fallback; never crash on unknown id
        }
    }
    /// Personality/style token from the id (warm/direct/playful).
    static func personality(for id: String) -> String {
        String(id.split(separator: "_").first ?? "playful")
    }
}
```

### New state + auth + ISO formatter
```diff
 struct OnboardingView: View {
+    @ObservedObject var auth: AuthManager
     var onFinish: () -> Void
```
```swift
    @State private var isSaving = false
    @State private var saveError: SaveError?

    private enum SaveError: Equatable {
        case sessionExpired, badDate, network, generic
        var message: String {
            switch self {
            case .sessionExpired: return "Your session has timed out. Please sign in again to finish setting up."
            case .badDate:        return "There was a problem with your date of birth. Please check it and try again."
            case .network:        return "We couldn't save your details. Please check your connection and try again."
            case .generic:        return "Something went wrong saving your details. Please try again."
            }
        }
        var actionTitle: String {
            switch self {
            case .sessionExpired: return "Sign in"
            case .badDate:        return "Review my details"
            default:              return "Try again"
            }
        }
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
```

### Completion button → save (busy) + error banner
```diff
-            Button {
-                // Real: POST /api/v1/settings/profile {...} then POST /api/v1/auth/complete-onboarding.
-                onFinish()
-            } label: {
-                Text("Begin your witness")
-                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
-                    .frame(maxWidth: .infinity).frame(height: 56)
-                    .background(allAgreed ? WV.teal : WV.teal.opacity(0.4),
-                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
-                    .shadow(color: WV.teal.opacity(allAgreed ? 0.3 : 0), radius: 10, y: 6)
-            }
-            .witnessPress()
-            .disabled(!allAgreed)
-            .padding(.horizontal, 24).padding(.bottom, 10)
+            Button { Task { await save() } } label: {
+                Group {
+                    if isSaving { ProgressView().tint(.white) }
+                    else { Text("Begin your witness").font(.system(size: 17, weight: .semibold)) }
+                }
+                .foregroundStyle(.white)
+                .frame(maxWidth: .infinity).frame(height: 56)
+                .background((allAgreed && !isSaving) ? WV.teal : WV.teal.opacity(0.4),
+                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
+                .shadow(color: WV.teal.opacity(allAgreed ? 0.3 : 0), radius: 10, y: 6)
+            }
+            .witnessPress()
+            .disabled(!allAgreed || isSaving)
+            .padding(.horizontal, 24).padding(.bottom, 10)
```
Insert the banner in the completion VStack (after agreementCard):
```swift
            if saveError != nil { errorBanner.padding(.top, 4) }
```
```swift
    private var errorBanner: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle").font(.system(size: 26)).foregroundStyle(WV.danger)
            Text(saveError?.message ?? "")
                .font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.75))
                .multilineTextAlignment(.center).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Button { handleErrorAction() } label: {
                Text(saveError?.actionTitle ?? "Try again")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(WV.teal, in: RoundedRectangle(cornerRadius: 14))
            }
            .witnessPress()
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        .padding(.horizontal, 24)
    }

    private func handleErrorAction() {
        switch saveError {
        case .sessionExpired:
            auth.logout()                                   // ContentView isLoggedIn watcher → .threshold
        case .badDate:
            saveError = nil
            withAnimation { completed = false; step = 1 }   // back to the birthdate step to fix it
        default:
            Task { await save() }                           // network/generic → retry the POST
        }
    }
```

### save() / buildRequest() / persistLocal() / mapError()
```swift
    private func save() async {
        saveError = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let body = buildRequest()
            try await auth.saveOnboardingProfile(body)
            persistLocal(body)
            onFinish()                                      // success → route to main
        } catch {
            saveError = Self.mapError(error)                // stay on completion screen
        }
    }

    private func buildRequest() -> ProfileCreateRequest {
        func opt(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespaces); return t.isEmpty ? nil : t
        }
        let cName = companionName.trimmingCharacters(in: .whitespaces)
        return ProfileCreateRequest(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),     // "" allowed, always sent
            birthDate: Self.isoFormatter.string(from: birthdate),
            birthCity: opt(birthCity),
            birthState: opt(birthState),
            gender: opt(gender),
            companionName: cName.isEmpty ? Profile.defaultCompanionName : cName,
            companionVoice: selectedVoice,
            companionPersonality: VoiceOption.personality(for: selectedVoice),
            customVoiceName: VoiceOption.geminiName(for: selectedVoice)
        )
    }

    private func persistLocal(_ body: ProfileCreateRequest) {
        let d = UserDefaults.standard
        d.set(body.lastName, forKey: Profile.lastNameKey)
        d.set(body.birthDate, forKey: Profile.birthdateKey)
        d.set(body.companionVoice, forKey: Profile.voiceKey)
        d.set(body.customVoiceName, forKey: Profile.customVoiceNameKey)
        // firstName + companionName are already @AppStorage-backed.
    }

    private static func mapError(_ error: Error) -> SaveError {
        if let api = error as? APIError {
            switch api {
            case .unauthorized:        return .sessionExpired
            case .http(let s, _):      return s == 400 ? .badDate : .generic
            case .network:             return .network
            default:                   return .generic
            }
        }
        return .generic
    }
```

## ContentView.swift — pass auth
```diff
             case .onboarding:
-                OnboardingView(onFinish: {
+                OnboardingView(auth: auth, onFinish: {
                     // Backend onboarding_completed is flipped by the POST above; this only routes.
                     withAnimation(.easeInOut(duration: 0.6)) { route = .main }
                 })
```

---

## After approval
Apply; build 0/0 + diagnostics; report honestly. Not calling /auth/complete-onboarding. No git.
```
