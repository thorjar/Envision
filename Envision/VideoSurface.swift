import SwiftUI
import AVFoundation

#if os(macOS)
import AppKit

/// AVPlayerLayer-backed video surface for macOS.
struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer
    var cornerRadius: CGFloat = 12
    /// Called once the backing view exists — hands the player the AVPlayerLayer
    /// (for picture-in-picture) and the NSView (for window fullscreen).
    var onAttach: ((PlayerLayerHostView) -> Void)?

    func makeNSView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView()
        view.player = player
        view.cornerRadius = cornerRadius
        view.onWindowAttached = onAttach
        return view
    }

    func updateNSView(_ view: PlayerLayerHostView, context: Context) {
        view.player = player
        view.cornerRadius = cornerRadius
    }
}

/// NSView whose backing layer is an AVPlayerLayer.
final class PlayerLayerHostView: NSView {
    private let playerLayer = AVPlayerLayer()
    var onWindowAttached: ((PlayerLayerHostView) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onWindowAttached?(self) }
    }

    /// The layer, exposed for picture-in-picture content sources.
    var currentPlayerLayer: AVPlayerLayer { playerLayer }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            guard playerLayer.player !== newValue else { return }
            playerLayer.player = newValue
        }
    }

    var cornerRadius: CGFloat = 12 {
        didSet {
            playerLayer.cornerRadius = cornerRadius
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUpLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpLayer()
    }

    private func setUpLayer() {
        wantsLayer = true

        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        playerLayer.cornerRadius = cornerRadius
        playerLayer.masksToBounds = true

        layer = playerLayer
    }
}

#elseif os(iOS)
import UIKit

/// AVPlayerLayer-backed video surface for iPhone/iPad.
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    var cornerRadius: CGFloat = 12
    /// Called once the backing view exists — hands the player the AVPlayerLayer
    /// for picture-in-picture content sources.
    var onAttach: ((PlayerLayerHostView) -> Void)?

    func makeUIView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView()
        view.player = player
        view.cornerRadius = cornerRadius
        view.onWindowAttached = onAttach
        return view
    }

    func updateUIView(_ view: PlayerLayerHostView, context: Context) {
        view.player = player
        view.cornerRadius = cornerRadius
    }
}

/// UIView whose backing layer is an AVPlayerLayer.
final class PlayerLayerHostView: UIView {
    var onWindowAttached: ((PlayerLayerHostView) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { onWindowAttached?(self) }
    }

    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    /// The layer, exposed for picture-in-picture content sources.
    var currentPlayerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            guard playerLayer.player !== newValue else { return }
            playerLayer.player = newValue
        }
    }

    var cornerRadius: CGFloat = 12 {
        didSet {
            playerLayer.cornerRadius = cornerRadius
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpLayer()
    }

    private func setUpLayer() {
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = UIColor.black.cgColor
        playerLayer.cornerRadius = cornerRadius
        playerLayer.masksToBounds = true
    }
}

#endif
