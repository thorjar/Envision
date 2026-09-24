import CoreImage
import SwiftUI

/// Sign-in for a TV without a keyboard. The server issues a short code, the TV
/// shows it with a QR payload another Envision client can scan, and the moment
/// that client approves the code the TV adopts the resulting session — exactly
/// the session a password login would have created, as the approving user.
struct TVPairingView: View {
    let serverURL: URL
    var onCancel: () -> Void

    @EnvironmentObject private var auth: AuthStore
    @State private var code: String?
    @State private var error: String?
    /// True once a code expired (or was claimed) and a fresh one was requested.
    @State private var refreshed = false
    @State private var claimed = false

    var body: some View {
        HStack(spacing: 90) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Sign in with a code").font(.title.bold())
                Text("1. Open Envision on your iPhone, iPad, or Mac — signed in to \(host).")
                Text("2. Tap “Pair Apple TV” and scan the code on this screen, or type it in.")
                Text("3. Your Apple TV signs in as that account. No password is typed on the TV.")
                if refreshed { Text("The previous code expired; this is a new one.").foregroundStyle(.secondary) }
            }
            .frame(width: 640, alignment: .leading)
            VStack(spacing: 22) {
                if let code {
                    Text(grouped(code))
                        .font(.system(size: 72, weight: .semibold, design: .monospaced))
                        .tracking(6)
                    if let image = QRCode.image(for: payload(code)) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 300, height: 300)
                            .padding(16)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if claimed {
                        ProgressView("Signing in…")
                    } else {
                        ProgressView("Waiting for approval…")
                    }
                } else if error == nil {
                    ProgressView("Requesting a code…")
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.callout).multilineTextAlignment(.center)
                }
                Button(error == nil ? "Back to password sign-in" : "Try again") {
                    if error == nil { onCancel() } else { error = nil; Task { await run() } }
                }
                .buttonStyle(TVButtonStyle())
            }
            .frame(width: 620)
        }
        .padding(80)
        .task { await run() }
    }

    private var host: String { serverURL.host ?? serverURL.absoluteString }

    /// Ask for a code and poll it until a client approves or the code expires.
    /// `pairingStatus` answers 404 for an expired or already-claimed code, which
    /// is not an error here: it just means this screen needs a fresh code.
    private func run() async {
        while !Task.isCancelled {
            do {
                let session = try await auth.api.initiatePairing(deviceName: "Apple TV")
                code = session.Code
                error = nil
                let deadline = Date().addingTimeInterval(TimeInterval(session.ExpiresIn))
                var polling = true
                while polling, Date() < deadline, !Task.isCancelled {
                    try await Task.sleep(for: .seconds(3))
                    do {
                        let status = try await auth.api.pairingStatus(code: session.Code)
                        if status.Authenticated, let token = status.AccessToken, let user = status.User {
                            claimed = true
                            auth.adoptSession(token: token, user: user)
                            return
                        }
                    } catch let APIError.failed(status, _) where status == 404 {
                        polling = false
                    }
                }
                refreshed = true
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
                return
            }
        }
    }

    /// The QR encodes the server as well as the code, so the scanning client can
    /// tell whether it is signed in to the right server.
    private func payload(_ code: String) -> String {
        var components = URLComponents()
        components.scheme = "envision"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "server", value: serverURL.absoluteString),
            URLQueryItem(name: "code", value: code),
        ]
        return components.string ?? code
    }

    /// Codes are read off a screen from across a room; a gap helps.
    private func grouped(_ code: String) -> String {
        guard code.count > 4 else { return code }
        let split = code.index(code.startIndex, offsetBy: 4)
        return "\(code[..<split]) \(code[split...])"
    }
}

/// Renders a QR image for the pairing payload shown on the TV side. Core Image
/// is available on tvOS, iOS, and macOS, so this stays shared-friendly.
enum QRCode {
    static func image(for text: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
