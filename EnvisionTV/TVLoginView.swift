import SwiftUI

struct TVLoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    /// Set once the server address checks out and the user chose a code sign-in.
    @State private var pairingServer: URL?

    var body: some View {
        Group {
            if let pairingServer {
                TVPairingView(serverURL: pairingServer) { self.pairingServer = nil }
            } else {
                credentials
            }
        }
        .onAppear {
            server = auth.baseURL.host == "127.0.0.1" ? "" : auth.baseURL.absoluteString
        }
    }

    private var credentials: some View {
        HStack(spacing: 100) {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "play.rectangle.fill").font(.system(size: 90)).foregroundStyle(.pink)
                Text("Envision").font(.largeTitle.bold())
                Text("Your media. On the big screen.").font(.title2)
                Text("Enter your media server’s network address—not localhost. You can use your iPhone to enter text on Apple TV.")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 620)
            VStack(spacing: 24) {
                TextField("Server URL (https://media.example.com)", text: $server)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password).textContentType(.password)
                if let error { Text(error).foregroundStyle(.red).font(.callout) }
                Button(busy ? "Connecting…" : "Sign in") { Task { await signIn() } }
                    .buttonStyle(TVButtonStyle())
                    .disabled(busy || username.trimmingCharacters(in: .whitespaces).isEmpty || server.isEmpty)
                Button("Sign in with a code") { Task { await startPairing() } }
                    .buttonStyle(TVButtonStyle())
                    .disabled(busy || server.isEmpty)
                if busy { ProgressView() }
            }
            .frame(width: 650)
            .disabled(busy)
        }
        .padding(80)
    }

    private func signIn() async {
        guard let url = TVServerAddress.parse(server) else {
            error = "Enter an HTTP or HTTPS server URL without a username, password, query, or fragment."
            return
        }
        busy = true
        error = nil
        defer { busy = false }
        do {
            auth.setServer(url)
            let info = try await auth.api.systemInfo()
            guard info.StartupWizardCompleted != false else {
                error = "Complete server setup using Envision on your Mac, iPad, or iPhone first."
                return
            }
            try await auth.login(username: username.trimmingCharacters(in: .whitespaces), password: password)
            password = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Codes are approved by an already signed-in client, so the TV only needs a
    /// reachable, set-up server before it can ask for one.
    private func startPairing() async {
        guard let url = TVServerAddress.parse(server) else {
            error = "Enter an HTTP or HTTPS server URL without a username, password, query, or fragment."
            return
        }
        busy = true
        error = nil
        defer { busy = false }
        do {
            auth.setServer(url)
            let info = try await auth.api.systemInfo()
            guard info.StartupWizardCompleted != false else {
                error = "Complete server setup using Envision on your Mac, iPad, or iPhone first."
                return
            }
            pairingServer = url
        } catch {
            self.error = error.localizedDescription
        }
    }
}
