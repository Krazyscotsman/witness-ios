import SwiftUI

// MARK: - Login / Create account. Still "the doorway." Buttons temporarily advance
// to Home so the flow is walkable; real auth wires in later.
struct LoginView: View {
    var onBack: () -> Void
    var onAuthenticated: () -> Void

    @State private var isRegistering = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

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
        Button {
            // TEMPORARY: advance to Home. Real: POST /api/v1/auth/login (or /register), then onAuthenticated().
            onAuthenticated()
        } label: {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(WV.teal)
                .clipShape(RoundedRectangle(cornerRadius: rControl, style: .continuous))
                .shadow(color: WV.teal.opacity(0.30), radius: 10, y: 6)
        }
        .buttonStyle(.plain)
    }

    private func providerButton<Icon: View>(_ title: String, @ViewBuilder icon: () -> Icon) -> some View {
        Button {
            // TEMPORARY: advance to Home. Real: POST /api/v1/auth/oauth, then onAuthenticated().
            onAuthenticated()
        } label: {
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
    }

    private var dividerOr: some View {
        HStack(spacing: 12) {
            Rectangle().fill(WT.ink.opacity(0.12)).frame(height: 1)
            Text("or").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.4))
            Rectangle().fill(WT.ink.opacity(0.12)).frame(height: 1)
        }
    }
}
