import SwiftUI

#if os(iOS)
import AVFoundation
#endif

/// Approves a code shown by a device that cannot type credentials (an Apple TV).
/// The approved device signs in as this user — the session the server creates is
/// the same one a password login would produce.
struct PairTVView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var busy = false
    @State private var message: Message?

    private enum Message: Equatable {
        case success(String), failure(String), notice(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Pair a device").font(.title2.bold())
            Text("On the other device choose “Sign in with a code”, then enter or scan the code it shows. It signs in as \(auth.user?.Name ?? "you").")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Code (for example ABCD 2345)", text: $code)
                .font(.system(.title3, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
                .onSubmit { Task { await approve() } }
            #if os(iOS)
            Button {
                Task { await scan() }
            } label: {
                Label("Scan the QR code instead", systemImage: "qrcode.viewfinder")
            }
            #endif
            HStack(spacing: 12) {
                Button("Approve") { Task { await approve() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(enteredCode.count != 8 || busy)
                Button("Close") { dismiss() }
                    .disabled(busy)
                if busy { ProgressView().controlSize(.small) }
            }
            if let message {
                Text(text(for: message))
                    .font(.callout)
                    .foregroundStyle(color(for: message))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(24)
        .frame(minWidth: 380, minHeight: 300)
        #if os(iOS)
        .sheet(isPresented: $scanning) {
            QRScannerView { payload in
                scanning = false
                adopt(payload)
            }
            .ignoresSafeArea()
        }
        #endif
    }

    #if os(iOS)
    @State private var scanning = false
    #endif

    /// The server accepts codes with or without spacing, in any case.
    private var enteredCode: String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private func approve() async {
        busy = true
        defer { busy = false }
        do {
            try await auth.api.approvePairing(code: enteredCode)
            message = .success("Approved. The device is signing in now.")
            code = ""
        } catch {
            message = .failure(error.localizedDescription)
        }
    }

    #if os(iOS)
    /// Scanning needs the camera; ask before presenting the scanner so a refusal
    /// shows an explanation instead of an empty black screen.
    private func scan() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            scanning = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { scanning = true } else { message = .failure("Camera access is off. Allow it in Settings, or type the code instead.") }
        default:
            message = .failure("Camera access is off. Allow it in Settings, or type the code instead.")
        }
    }

    /// A scanned payload carries both the server and the code, so a code for a
    /// server this app is not signed in to can be explained rather than failing
    /// with a confusing "not found".
    private func adopt(_ payload: String) {
        guard let url = URL(string: payload), url.scheme == "envision", url.host == "pair",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let scanned = items.first(where: { $0.name == "code" })?.value else {
            message = .notice("That QR code is not an Envision pairing code.")
            return
        }
        if let server = items.first(where: { $0.name == "server" })?.value,
           let scannedURL = URL(string: server),
           scannedURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            != auth.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
            code = scanned
            message = .notice("That code is for \(scannedURL.host ?? server). Sign in to that server in Envision first, then scan again.")
            return
        }
        code = scanned
        message = .notice("Code filled in. Tap Approve to sign that device in.")
    }
    #endif

    private func text(for message: Message) -> String {
        switch message {
        case .success(let text), .failure(let text), .notice(let text): return text
        }
    }

    private func color(for message: Message) -> Color {
        switch message {
        case .success: return .green
        case .failure: return .red
        case .notice: return .secondary
        }
    }
}
