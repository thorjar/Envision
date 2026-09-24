#if os(iOS)
import AVFoundation
import AudioToolbox
import SwiftUI

/// Camera QR scanner for the pairing sheet. UIKit + AVFoundation because
/// SwiftUI has no scanner, and because this must work on iPhone as well as iPad.
struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> Scanner {
        let scanner = Scanner()
        scanner.onCode = onCode
        return scanner
    }

    func updateUIViewController(_ controller: Scanner, context: Context) {}

    final class Scanner: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?

        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        /// A camera keeps emitting frames; the first readable code wins.
        private var delivered = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            preview = layer
            // startRunning() blocks; it must not run on the main thread.
            let session = session
            DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            let session = session
            DispatchQueue.global(qos: .userInitiated).async {
                if session.isRunning { session.stopRunning() }
            }
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !delivered,
                  let value = metadataObjects
                      .compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
                      .first(where: { $0.type == .qr })?
                      .stringValue else { return }
            delivered = true
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            onCode?(value)
        }
    }
}
#endif
