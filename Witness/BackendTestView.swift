import SwiftUI

// TEMP: three isolatable backend connection tests (item: networking foundation). This is a
// developer scratch view, NOT a shipped feature — remove once feature screens are wired.
struct BackendTestView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var health = "—"
    @State private var email = ""
    @State private var password = ""
    @State private var loginResult = "—"
    @State private var memoriesResult = "—"
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Base URL (DEV)") {
                    Text(APIClient.baseURL.absoluteString)
                        .font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                }

                Section("1 · GET /health (no auth)") {
                    Button("Run health check") { runHealth() }.disabled(busy)
                    Text(health).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                }

                Section("2 · POST /api/v1/auth/login") {
                    TextField("email", text: $email)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    SecureField("password", text: $password)
                    Button("Log in & store token") { runLogin() }
                        .disabled(busy || email.isEmpty || password.isEmpty)
                    Text(loginResult).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                }

                Section("3 · GET /api/v1/memories (uses stored token · one-shot)") {
                    Button("Fetch memories") { runMemories() }.disabled(busy)
                    Text(memoriesResult).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                }

                Section {
                    Button("Clear stored token", role: .destructive) {
                        KeychainStore.shared.clear(); loginResult = "token cleared"
                    }
                    Button("Close") { dismiss() }
                }
            }
            .navigationTitle("Backend Test (temp)")
        }
    }

    private func runHealth() {
        busy = true; health = "…"
        Task {
            do {
                let r: HealthResponse = try await APIClient.shared.get("/health", authorized: false)
                health = "OK · git_sha: \(r.gitSha ?? "nil")"
            } catch {
                health = "FAIL · \((error as? APIError)?.errorDescription ?? error.localizedDescription)"
            }
            busy = false
        }
    }

    private func runLogin() {
        busy = true; loginResult = "…"
        Task {
            do {
                let r: LoginResponse = try await APIClient.shared.post(
                    "/api/v1/auth/login",
                    body: LoginRequest(email: email, password: password),
                    authorized: false)
                KeychainStore.shared.save(token: r.token)
                loginResult = "OK · \(r.user.name ?? "user") · token stored (\(r.token.count) chars)"
            } catch {
                loginResult = "FAIL · \((error as? APIError)?.errorDescription ?? error.localizedDescription)"
            }
            busy = false
        }
    }

    private func runMemories() {
        busy = true; memoriesResult = "…"
        Task {
            do {
                let r: MemoriesResponse = try await APIClient.shared.get("/api/v1/memories")
                let titles = r.memories.prefix(5).map { "• \($0.title ?? "(untitled)")" }.joined(separator: "\n")
                memoriesResult = "OK · got \(r.memories.count) of \(r.total)\n\(titles)"
            } catch {
                memoriesResult = "FAIL · \((error as? APIError)?.errorDescription ?? error.localizedDescription)"
            }
            busy = false
        }
    }
}
