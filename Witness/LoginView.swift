import SwiftUI

// MARK: - Login / Create account. Still "the doorway." Buttons temporarily advance
// to Home so the flow is walkable; real auth wires in later.
struct LoginView: View {
    @ObservedObject var auth: AuthManager
    var onBack: () -> Void
    var onAuthenticated: () -> Void

    @State private var isRegistering = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorText: String?

    private let rControl: CGFloat = 14
    private let fieldFill = Color(hex: 0xfaf7f0)

    var body: some View {
        ZStack {
            ParchmentDoorBackground(fade: 0.16, inkContrast: 1.20)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack {
                        Button { onBack() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(WT.ink.opacity(0.55))
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.top, 4)

                    CompassMark(color: WV.gold).frame(width: 34, height: 34).padding(.top, 6)
                    Text(isRegistering ? "Create your account" : "Welcome back")
                        .font(.serif(26)).foregroundStyle(WV.teal).padding(.top, 12)
                    Text(isRegistering ? "Begin your witness." : "Continue your witness.")
                        .font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.5)).padding(.top, 6)

                    VStack(spacing: 12) {
                        if isRegistering { textField("Name", text: $name) }
                        textField("Email", text: $email, isEmail: true)
                        secureField("Password", text: $password)
                    }
                    .padding(.top, 28)

                    primaryButton(isRegistering ? "Create account" : "Sign in")
                        .padding(.top, 18)
                        .disabled(busy || email.isEmpty || password.isEmpty)
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 13)).foregroundStyle(WV.danger)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                    }

                    dividerOr.padding(.vertical, 20)

                    VStack(spacing: 10) {
                        providerButton("Continue with Apple") {
                            Image(systemName: "applelogo").font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.85))
                        }
                        providerButton("Continue with Google") { GoogleGIcon(size: 18) }
                        providerButton("Continue with Facebook") { FacebookIcon(size: 18) }
                        providerButton("Continue with Microsoft") { MicrosoftIcon(size: 18) }
                    }

                    Button { withAnimation(.easeInOut(duration: 0.2)) { isRegistering.toggle() } } label: {
                        Text(isRegistering ? "Have an account?  Sign in" : "New here?  Create account")
                            .font(.system(size: 13))
                            .foregroundStyle(WV.teal)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 24)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
    }

    private func textField(_ placeholder: String, text: Binding<String>, isEmail: Bool = false) -> some View {
        TextField(placeholder, text: text)
            .textInputAutocapitalization(isEmail ? .never : .words)
            .autocorrectionDisabled(isEmail)
            .keyboardType(isEmail ? .emailAddress : .default)
            .font(.system(size: 16))
            .foregroundStyle(WT.ink)
            .padding(.horizontal, 16).frame(height: 52)
            .background(fieldFill, in: RoundedRectangle(cornerRadius: rControl))
            .overlay(RoundedRectangle(cornerRadius: rControl).stroke(WT.ink.opacity(0.15), lineWidth: 1))
    }

    private func secureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .textInputAutocapitalization(.never)
            .font(.system(size: 16))
            .foregroundStyle(WT.ink)
            .padding(.horizontal, 16).frame(height: 52)
            .background(fieldFill, in: RoundedRectangle(cornerRadius: rControl))
            .overlay(RoundedRectangle(cornerRadius: rControl).stroke(WT.ink.opacity(0.15), lineWidth: 1))
    }

    private func primaryButton(_ title: String) -> some View {
        Button { submit() } label: {
            Text(busy ? "Signing in…" : title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(WV.teal)
                .clipShape(RoundedRectangle(cornerRadius: rControl, style: .continuous))
                .shadow(color: WV.teal.opacity(0.30), radius: 10, y: 6)
        }
        .buttonStyle(.plain)
    }

    // Real login (Sign-in mode). Registration/OAuth aren't wired yet — see submit()/providerButton.
    private func submit() {
        guard !isRegistering else { errorText = "Account creation isn’t available yet."; return }
        let e = email.trimmingCharacters(in: .whitespaces)
        guard !e.isEmpty, !password.isEmpty else { return }
        busy = true; errorText = nil
        Task {
            do {
                try await auth.login(email: e, password: password)
                onAuthenticated()
            } catch {
                errorText = Self.message(for: error)
                busy = false
            }
        }
    }

    private static func message(for error: Error) -> String {
        if let api = error as? APIError {
            if case .unauthorized(let detail, _) = api { return detail ?? "Incorrect email or password." }
            return api.errorDescription ?? "Something went wrong."
        }
        return error.localizedDescription
    }

    private func providerButton<Icon: View>(_ title: String, @ViewBuilder icon: () -> Icon) -> some View {
        // OAuth isn't wired yet (later item). Disabled so it can't grant tokenless entry past the gate.
        Button { } label: {
            HStack(spacing: 10) {
                icon().frame(width: 18, height: 18)
                Text(title).font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(WT.ink.opacity(0.85))
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: rControl))
            .overlay(RoundedRectangle(cornerRadius: rControl).stroke(WT.ink.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(true)
        .opacity(0.5)
    }

    private var dividerOr: some View {
        HStack(spacing: 12) {
            Rectangle().fill(WT.ink.opacity(0.12)).frame(height: 1)
            Text("or").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.4))
            Rectangle().fill(WT.ink.opacity(0.12)).frame(height: 1)
        }
    }
}
