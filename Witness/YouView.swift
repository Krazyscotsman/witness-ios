import SwiftUI

// MARK: - Profile + settings keys. The companion name remains the single source of truth
// read across the app; the rest back the Settings page. Once wired, all of these load
// from GET /api/v1/settings/profile and save via PUT.
enum Profile {
    static let firstNameKey = "profile.firstName"
    static let lastNameKey = "profile.lastName"
    static let companionNameKey = "profile.companionName"
    static let defaultCompanionName = "Scarlett"

    static let birthdateKey = "profile.birthdate"          // ISO yyyy-MM-dd
    static let genderKey = "profile.gender"
    static let birthCityKey = "profile.birthCity"
    static let birthStateKey = "profile.birthState"

    static let voiceKey = "profile.voice"                  // e.g. "warm_female"
    static let customVoiceNameKey = "profile.customVoiceName"
    static let voiceConfirmKey = "settings.voiceConfirm"   // Bool
    static let conversationModeKey = "settings.conversationMode" // "text" | "voice"
    static let vadSilenceKey = "settings.vadSilenceSeconds"      // Int

    static let textSizeKey = "settings.textSize"           // "small" | "medium" | "large"
    static let themeKey = "settings.theme"                 // "system" | "light" | "dark"
    static let memoryPrivacyKey = "settings.memoryPrivacy" // "open" | "private"
}

struct YouView: View {
    var onSignOut: () -> Void

    @AppStorage(Profile.firstNameKey) private var firstName: String = ""
    @AppStorage(Profile.lastNameKey) private var lastName: String = ""
    @AppStorage(Profile.companionNameKey) private var companionName: String = Profile.defaultCompanionName

    var body: some View {
        NavigationStack {
            ZStack {
                ParchmentBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        profileHeader
                        NavigationLink { SettingsView() } label: { settingsRow }
                            .witnessPress()
                        signOutButton
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var displayName: String {
        let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? "Your profile" : full
    }
    private var displayCompanion: String {
        let t = companionName.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? Profile.defaultCompanionName : t
    }

    private var profileHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(WV.teal.opacity(0.12))
                CompassMark(color: WV.gold).frame(width: 34, height: 34)
            }
            .frame(width: 84, height: 84)
            Text(displayName).font(.serif(26)).foregroundStyle(WT.ink)
            Text("Your witness: \(displayCompanion)")
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    private var settingsRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(WV.teal.opacity(0.12))
                Image(systemName: "gearshape.fill").font(.system(size: 18, weight: .medium)).foregroundStyle(WV.teal)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings").font(.serif(19)).foregroundStyle(WT.ink)
                Text("Profile, companion, voice, appearance, privacy")
                    .font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.55))
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

    private var signOutButton: some View {
        Button { onSignOut() } label: {
            Text("Sign out")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(WV.danger)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(WV.danger.opacity(0.3), lineWidth: 1))
        }
        .witnessPress()
        .witnessHint("Signs you out and returns you to the front door.")
        .padding(.top, 4)
    }
}
