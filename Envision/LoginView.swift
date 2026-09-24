import SwiftUI

/// Port of pages/LoginPage.tsx: connects, offers first-run admin setup, signs in.
struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var setupRequired: Bool?
    @State private var error: String?
    @State private var busy = false
    @State private var serverAddress = ""

    var body: some View {
        VStack {
            switch setupRequired {
            case nil:
                if error != nil {
                    connectionFailed
                } else {
                    ProgressView("Connecting to server…")
                }

            default:
                form
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task {
            await loadSystemInfo()
        }
    }

    private var connectionFailed: some View {
        VStack(spacing: 16) {
            Text(error ?? "Could not reach the server.")
                .foregroundStyle(.red)
            Button("Retry connection") { Task { await loadSystemInfo() } }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

    private var form: some View {
        VStack(spacing: 18) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.pink)
            Text("Envision").font(.title2).bold()
            Text(setupRequired == true
                 ? "Create the first administrator to finish setup."
                 : "Sign in to your media server.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Server").font(.caption).foregroundStyle(.secondary)
                TextField("http://127.0.0.1:8097", text: $serverAddress)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await changeServer() } }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Username").font(.caption).foregroundStyle(.secondary)
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Password").font(.caption).foregroundStyle(.secondary)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            if setupRequired == true {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Confirm password").font(.caption).foregroundStyle(.secondary)
                    SecureField("Confirm password", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                    Text("Use at least 12 characters. You can add media libraries after signing in.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            Button {
                Task { await submit() }
            } label: {
                HStack {
                    if busy { ProgressView().controlSize(.small) }
                    Text(busy
                         ? (setupRequired == true ? "Creating administrator…" : "Signing in…")
                         : (setupRequired == true ? "Create administrator" : "Sign in"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || username.isEmpty || password.isEmpty)
        }
        .padding(32)
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.3), radius: 18)
    }

    private func loadSystemInfo() async {
        error = nil
        do {
            let info = try await auth.api.systemInfo()
            setupRequired = !(info.StartupWizardCompleted ?? false)
            if setupRequired == true { username = "admin" }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func changeServer() async {
        let trimmed = serverAddress.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), url.scheme != nil else {
            error = "Enter a valid server URL."
            return
        }
        auth.setServer(url)
        setupRequired = nil
        await loadSystemInfo()
    }

    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            if setupRequired == true {
                guard password == confirmPassword else {
                    throw APIError.failed(0, "Passwords do not match.")
                }
                guard password.count >= 12 else {
                    throw APIError.failed(0, "Use at least 12 characters.")
                }
                _ = try await auth.api.setupAdmin(name: username, password: password)
                setupRequired = false
            }
            try await auth.login(username: username, password: password)
        } catch {
            self.error = error.localizedDescription
            if setupRequired != nil {
                if let info = try? await auth.api.systemInfo() {
                    setupRequired = !(info.StartupWizardCompleted ?? false)
                }
            }
        }
    }
}
