import SwiftUI
import AVKit
import UIKit

/// AVKit owns remote transport, scrubbing, and the stream's in-item menus. The
/// embedded audio/subtitle tracks live on the server (per-track HLS variants
/// and a VTT endpoint), so this view presents a focusable track picker of its
/// own.
struct TVPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var engine: PlaybackEngine
    @State private var showTracks = false
    /// Playback state captured when the picker opens, restored when it closes.
    @State private var wasPlayingBeforeTracks = false
    /// Transport bar visibility, reported by the representable.
    @State private var controlsUp = false
    let item: Item

    init(api: JellymaxAPI, item: Item) {
        self.item = item
        _engine = StateObject(wrappedValue: PlaybackEngine(api: api, item: item))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let error = engine.error {
                VStack(spacing: 28) {
                    Text("Playback unavailable").font(.title)
                    Text(error).multilineTextAlignment(.center)
                    Button("Try again") { engine.teardown(); engine.start() }
                        .buttonStyle(TVButtonStyle())
                    Button("Back") { dismiss() }
                        .buttonStyle(TVButtonStyle())
                }.padding(80)
            } else if let player = engine.player {
                // While the picker is open AVKit's view is made
                // non-interactive. Otherwise AVPlayerViewController keeps the
                // remote: arrows never entered the picker and MENU was
                // consumed as "exit playback" instead of closing it.
                TVNativePlayer(
                    player: player,
                    title: item.Name,
                    overview: item.Overview ?? "",
                    isInteractive: !showTracks,
                    // The entry point lives in the transport bar itself, so it
                    // appears and hides with the controls and is reachable
                    // with the same arrows that move through the bar's other
                    // buttons — no separate focus path to manage.
                    menuItems: engine.source == nil
                        ? nil
                        : [UIAction(
                            title: "Audio & Subtitles",
                            image: UIImage(systemName: "captions.bubble")
                        ) { _ in presentTracks() }],
                    // Empty while the picker is up so captions never ghost
                    // through the panel's dimmed backdrop.
                    captionText: showTracks ? "" : engine.captionText,
                    // Reports the transport bar's visibility (discovered and
                    // observed in the representable) so the caption can slide
                    // down out of the bar's way.
                    onControls: { controlsUp = $0 },
                    controlsUp: controlsUp
                ) { message in
                    engine.error = message
                    engine.player?.pause()
                }
                .ignoresSafeArea()
            } else {
                ProgressView("Preparing \(item.Name)…")
            }
        }
        .onAppear {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try AVAudioSession.sharedInstance().setActive(true)
                engine.start()
            } catch { engine.error = error.localizedDescription }
        }
        .onDisappear { engine.teardown() }
        // MENU while the picker is up is owned by the picker: as a presented
        // modal it is the topmost focus holder, so this handler only runs once
        // the picker is gone. Guarding on `showTracks` keeps a single press
        // from both closing the picker and leaving playback.
        .onExitCommand {
            if !showTracks { dismiss() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { engine.player?.pause() }
        }
    }

    /// The picker is presented as its own modal view controller rather than an
    /// overlay or a nested `fullScreenCover`. Drawn inside the player's cover,
    /// the picker shared a focus environment with AVKit's controller, which
    /// kept the remote: arrow keys never reached the rows and MENU was
    /// consumed as "exit playback". As a modal it is the topmost presentation,
    /// so it owns both. See `TVTracksPresentation`.
    private func presentTracks() {
        wasPlayingBeforeTracks = engine.isPlaying
        showTracks = TVTracksPresentation.present(engine: engine, api: engine.api, item: item) {
            showTracks = false
            // Opening and closing the picker must not cost the viewer their
            // place in the stream.
            if wasPlayingBeforeTracks { engine.player?.play() }
        }
    }
}

/// Presents the track picker as its own modal view controller. See
/// `TVPlayerView.presentTracks` for why a modal is required.
@MainActor
enum TVTracksPresentation {
    private static weak var presented: UIViewController?
    private static var onClose: (() -> Void)?

    /// Returns whether the picker is on screen, so the caller's own state
    /// cannot claim it is up when presenting failed.
    @discardableResult
    static func present(engine: PlaybackEngine, api: JellymaxAPI, item: Item, onClose: @escaping () -> Void) -> Bool {
        guard presented == nil, let host = topmostController() else { return false }
        Self.onClose = onClose
        let panel = TVTracksPanel(engine: engine, api: api, item: item) { TVTracksPresentation.dismiss() }
        let controller = TVPanelHostingController(rootView: AnyView(panel))
        controller.onMenu = { TVTracksPresentation.dismiss() }
        controller.onClosed = { TVTracksPresentation.notifyClosed() }
        // Clear so playback stays visible behind the panel's dimmed backdrop.
        controller.view.backgroundColor = .clear
        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve
        presented = controller
        host.present(controller, animated: true)
        return true
    }

    /// Closes the picker and reports that once, whichever way it closed —
    /// including UIKit's own modal dismissal, which it does not announce.
    static func dismiss() {
        let controller = presented
        presented = nil
        let handler = onClose
        onClose = nil
        handler?()
        controller?.dismiss(animated: true)
    }

    /// Called from the hosting controller as it goes away.
    fileprivate static func notifyClosed() {
        guard let handler = onClose else { return }
        presented = nil
        onClose = nil
        handler()
    }

    /// Hands focus back to the picker after a panel presented on top of it —
    /// the OpenSubtitles search — closes. SwiftUI does not reliably restore
    /// focus to the scope underneath on its own, leaving the remote dead until
    /// something is tapped.
    static func restoreFocus() {
        guard let controller = presented else { return }
        controller.setNeedsFocusUpdate()
        controller.updateFocusIfNeeded()
    }

    /// The topmost view controller, following any presented modals — this is
    /// how a panel presented on top of the picker still finds its host.
    static func topmostController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var current = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let next = current?.presentedViewController { current = next }
        return current
    }
}

/// Hosting controller for the player's modal panels (track picker,
/// OpenSubtitles search). Intercepts the Menu press so it closes the panel
/// rather than reaching the player underneath, and reports any dismissal back
/// to the presentation that owns it — through a closure, because a panel can
/// host another (the picker opens the subtitle search on top of itself).
final class TVPanelHostingController: UIHostingController<AnyView> {
    var onMenu: (() -> Void)?
    var onClosed: (() -> Void)?

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .menu }) {
            onMenu?()
            return
        }
        super.pressesBegan(presses, with: event)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onClosed?()
    }
}

/// Two-column track picker shown over the player. Embedded soundtracks switch
/// the stream server-side (`AudioTrackUrls`), embedded subtitles load through
/// the server's windowed VTT endpoint — both via the shared PlaybackEngine.
/// MENU closes the panel (back to the entry button); Select applies a row.
private struct TVTracksPanel: View {
    @ObservedObject var engine: PlaybackEngine
    let api: JellymaxAPI
    let item: Item
    let onClose: () -> Void
    /// Arrow keys need somewhere to start. Marking a row as the scope's
    /// preferred default puts focus on it the moment the panel appears, so the
    /// very first swipe moves between rows instead of doing nothing.
    @Namespace private var focusScope

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            HStack(alignment: .top, spacing: 56) {
                column(title: "Audio", loading: false) { audioRows }
                column(title: "Subtitles", loading: engine.isSubtitleLoading) { subtitleRows }
            }
            .padding(64)
        }
        .focusScope(focusScope)
        // MENU closes the panel, never playback. The hosting controller
        // intercepts the press first; this is the SwiftUI-level backstop for
        // any press that reaches the panel's own responder chain instead.
        // `dismiss()` clears its close handler, so both firing is harmless.
        .onExitCommand { onClose() }
    }

    @ViewBuilder
    private func column<Rows: View>(
        title: String,
        loading: Bool,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Text(title).font(.title2.bold())
                if loading { ProgressView().controlSize(.small) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) { rows() }
            }
            .frame(maxHeight: 520)
        }
        .frame(maxWidth: 460, alignment: .leading)
    }

    /// Whether the Audio column has selectable rows. When it does not, the
    /// Subtitles column provides the panel's initial focus instead.
    private var audioColumnHasRows: Bool {
        engine.serverAudioStreams.count > 1 || engine.audioTracks.count > 1
    }

    /// Server-side embedded soundtracks win when several exist; otherwise the
    /// stream's native options (direct-play files) are listed.
    @ViewBuilder
    private var audioRows: some View {
        if engine.serverAudioStreams.count > 1 {
            ForEach(
                Array(engine.serverAudioStreams.enumerated()),
                id: \.element.Index
            ) { ordinal, stream in
                trackRow(
                    engine.mediaStreamLabel(stream, ordinal: ordinal),
                    selected: engine.selectedServerAudioIndex == stream.Index
                ) {
                    onClose()
                    Task { await engine.selectServerAudio(stream.Index ?? 0) }
                }
                .modifier(TVDefaultFocus(isDefault: ordinal == 0, scope: focusScope))
            }
        } else if engine.audioTracks.count > 1 {
            ForEach(Array(engine.audioTracks.enumerated()), id: \.element) { ordinal, option in
                trackRow(option.displayName, selected: engine.selectedAudio == option) {
                    engine.selectAudio(option)
                    onClose()
                }
                .modifier(TVDefaultFocus(isDefault: ordinal == 0, scope: focusScope))
            }
        } else {
            Text("One soundtrack in this stream.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var subtitleRows: some View {
        let noneSelected = engine.selectedSubtitle == nil
            && engine.selectedServerSubtitleIndex == nil
            && engine.externalSubtitleName == nil
        trackRow("Off", selected: noneSelected) {
            engine.clearSubtitle()
            engine.selectSubtitle(nil)
            onClose()
        }
        .modifier(TVDefaultFocus(isDefault: !audioColumnHasRows, scope: focusScope))
        ForEach(engine.subtitleTracks, id: \.self) { option in
            trackRow(option.displayName, selected: engine.selectedSubtitle == option) {
                engine.clearSubtitle()
                engine.selectSubtitle(option)
                onClose()
            }
        }
        ForEach(engine.serverSubtitleStreams, id: \.Index) { stream in
            trackRow(
                engine.mediaStreamLabel(stream),
                selected: engine.selectedServerSubtitleIndex == stream.Index
            ) {
                onClose()
                Task { await engine.selectServerSubtitle(stream) }
            }
        }
        // A subtitle downloaded from OpenSubtitles, shown like the phone's
        // player menu does. Pressing it returns to playback with captions on.
        if let name = engine.externalSubtitleName {
            trackRow(name, selected: true) { onClose() }
        }
        // OpenSubtitles search: the server holds the API key and serves the
        // results, so the TV only presents them (same flow as the phone's
        // player menu). Presented as its own modal — see
        // `TVOpenSubtitlesPresentation`.
        trackRow("Search OpenSubtitles…", selected: false) {
            TVOpenSubtitlesPresentation.present(engine: engine, api: api, item: item)
        }
        if engine.subtitleTracks.isEmpty && engine.serverSubtitleStreams.isEmpty {
            Text("No subtitles in this stream. Search OpenSubtitles for more.")
                .foregroundStyle(.secondary)
        }
    }

    private func trackRow(
        _ label: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(selected ? "✓ \(label)" : label)
                .lineLimit(1)
        }
        .buttonStyle(TVTrackRowStyle(isSelected: selected))
    }
}

/// Applies a panel's preferred default focus only to the row that should
/// receive it: `prefersDefaultFocus(in:)` is conditional, so a plain
/// `.prefersDefaultFocus` on every row would leave the starting point to
/// chance. Shared by the track picker and the OpenSubtitles search panel.
struct TVDefaultFocus: ViewModifier {
    var isDefault: Bool
    var scope: Namespace.ID

    func body(content: Content) -> some View {
        if isDefault {
            content.prefersDefaultFocus(in: scope)
        } else {
            content
        }
    }
}

/// Row style for the track picker: the accent fills the focused row, labels
/// stay white, and the active track keeps a faint highlight while unfocused.
struct TVTrackRowStyle: ButtonStyle {
    var isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        TVTrackRowBody(label: configuration.label, isSelected: isSelected)
    }
}

/// Focus state comes from the environment because this SDK's
/// ButtonStyleConfiguration does not expose isFocused.
private struct TVTrackRowBody<Content: View>: View {
    let label: Content
    var isSelected: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        label
            .font(.system(size: 24, weight: isSelected ? .semibold : .regular))
            .multilineTextAlignment(.leading)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? Color.accentColor : Color.white.opacity(isSelected ? 0.16 : 0.08))
            )
            .scaleEffect(isFocused ? 1.03 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

/// Renders the active embedded-subtitle caption inside AVKit's content
/// overlay view. It rests bottom-center, 130 pt up from the view's bottom
/// edge — deliberately NOT the safe-area guide, which AVKit moves when the
/// transport bar appears and pushes the caption too high over the video.
final class TVCaptionView: UIView {
    private let plate = UIView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Captions must never take focus or presses away from the player.
        isUserInteractionEnabled = false
        plate.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        plate.layer.cornerRadius = 10
        // The bottom margin is smaller than the top on purpose: the label's
        // line box always reserves the font's descent space (~8 pt below the
        // baseline at this size) even when the line ends in a letter with no
        // descender, so a symmetric margin made the plate read as extending
        // well past the text. Lines that do have descenders (g/y/p) only
        // reach ~7 pt into that space, so they stay covered.
        plate.layoutMargins = UIEdgeInsets(top: 10, left: 18, bottom: 3, right: 18)
        // AVKit grows the overlay's bottom safe-area inset while the
        // transport bar is up. With UIKit's default
        // insetsLayoutMarginsFromSafeArea that silently inflates the plate's
        // bottom margin by however far the plate overlaps the grown safe
        // area, pushing the label up inside the plate and leaving a large
        // black band beneath the text. Keep the margins above literal so the
        // plate hugs the text whether the bar is up or not.
        plate.insetsLayoutMarginsFromSafeArea = false
        label.font = .systemFont(ofSize: 34, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 3
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 1
        label.layer.shadowRadius = 5
        label.layer.shadowOffset = .zero
        plate.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(plate)
        plate.addSubview(label)
        // Label fills the plate either way.
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: plate.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: plate.layoutMarginsGuide.trailingAnchor),
            label.topAnchor.constraint(equalTo: plate.layoutMarginsGuide.topAnchor),
            label.bottomAnchor.constraint(equalTo: plate.layoutMarginsGuide.bottomAnchor),
        ])
        // Bottom-center on the video, fixed to the view's own bottom edge.
        NSLayoutConstraint.activate([
            plate.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 160),
            plate.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -160),
            plate.centerXAnchor.constraint(equalTo: centerXAnchor),
            plate.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -130),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setText(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard label.text != value else { return }
        label.text = value
        isHidden = value.isEmpty
    }
}

struct TVNativePlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let title: String
    let overview: String
    /// False while the track picker is presented. AVKit's controller is a
    /// UIKit focus environment of its own: left interactive it keeps the
    /// remote, so arrows never reach the picker and MENU is consumed as
    /// "exit playback". A non-user-interaction-enabled view is not focusable.
    var isInteractive: Bool
    /// Custom transport-bar items (tvOS 15+). Installed once — the player
    /// view re-evaluates on every time tick, and reassigning the array each
    /// time would make AVKit rebuild the bar and drop bar focus.
    var menuItems: [UIMenuElement]?
    /// Active embedded-subtitle caption. Rendered inside AVKit's content
    /// overlay view, not as a SwiftUI sibling: it rests bottom-center, 130 pt
    /// up from the overlay's bottom edge (its own bottom anchor, not the
    /// safe-area guide, so the transport bar can never push it up over the
    /// video).
    var captionText: String
    /// Called when the transport bar's visibility changes, discovered by
    /// watching the bar's own view (this AVKit build does not move the
    /// overlay's safe areas, so they cannot report it).
    var onControls: ((Bool) -> Void)?
    /// Latest reported transport-bar visibility, applied to the caption.
    var controlsUp: Bool
    var onError: (String) -> Void

    final class Coordinator {
        var observation: NSKeyValueObservation?
        var installedMenuItems = false
        var captionView: TVCaptionView?
        var barObservations: [NSKeyValueObservation] = []
        var pendingDiscoveries: [DispatchWorkItem] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        // Navigation owns lifetime; PiP would otherwise outlive this cover.
        controller.allowsPictureInPicturePlayback = false
        controller.view.isUserInteractionEnabled = isInteractive
        let titleMetadata = AVMutableMetadataItem()
        titleMetadata.identifier = .commonIdentifierTitle
        titleMetadata.value = title as NSString
        let descriptionMetadata = AVMutableMetadataItem()
        descriptionMetadata.identifier = .commonIdentifierDescription
        descriptionMetadata.value = overview as NSString
        player.currentItem?.externalMetadata = [titleMetadata, descriptionMetadata]
        context.coordinator.observation = player.currentItem?.observe(\.status, options: [.initial, .new]) { item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "This stream cannot be played on Apple TV."
            Task { @MainActor in onError(message) }
        }
        scheduleTransportBarDiscovery(controller, context.coordinator)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        if controller.view.isUserInteractionEnabled != isInteractive {
            controller.view.isUserInteractionEnabled = isInteractive
        }
        // Assigned the first time an item exists; the action closure captures
        // the view's own state, so it stays valid for the player's lifetime.
        if !context.coordinator.installedMenuItems, let menuItems = menuItems {
            controller.transportBarCustomMenuItems = menuItems
            context.coordinator.installedMenuItems = true
        }
        // The caption lives in AVKit's content overlay view ("between the
        // video content and the controls"), resting bottom-center of the
        // screen. It is created only once there is caption text to show:
        // creating it on the first update would insert it mid-transition,
        // and framework snapshot code then logs _UIReplicantView warnings
        // about content found in the hosting controller's view. Items
        // without embedded subtitles never build the view at all.
        guard !captionText.isEmpty || context.coordinator.captionView != nil,
              let overlay = controller.contentOverlayView else { return }
        let caption = context.coordinator.captionView ?? {
            let caption = TVCaptionView(frame: overlay.bounds)
            caption.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.addSubview(caption)
            context.coordinator.captionView = caption
            return caption
        }()
        caption.setText(captionText)
    }

    /// The transport bar's view is built lazily on first display, so look for
    /// it a few times before giving up; once found, its alpha (and hidden
    /// state) is the bar's visibility signal. Only public APIs are used —
    /// class names are compared as strings, never invoked.
    private func scheduleTransportBarDiscovery(_ controller: AVPlayerViewController, _ coordinator: Coordinator) {
        let onControls = self.onControls
        for delay in [0.5, 1.5, 3.0, 6.0] {
            let work = DispatchWorkItem { [weak controller, weak coordinator] in
                guard let controller, let coordinator, coordinator.barObservations.isEmpty else { return }
                coordinator.barObservations = Self.observeTransportBar(of: controller) { visible in
                    onControls?(visible)
                }
            }
            coordinator.pendingDiscoveries.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private static func observeTransportBar(
        of controller: AVPlayerViewController,
        onChange: @escaping (Bool) -> Void
    ) -> [NSKeyValueObservation] {
        var observations: [NSKeyValueObservation] = []
        var queue: [UIView] = [controller.view]
        while let view = queue.popLast() {
            for subview in view.subviews {
                let name = NSStringFromClass(type(of: subview)).lowercased()
                if name.contains("transportbar") {
                    let report = { (bar: UIView) in
                        let visible = bar.alpha > 0.5 && !bar.isHidden
                        Task { @MainActor in onChange(visible) }
                    }
                    observations.append(subview.observe(\.alpha, options: [.new]) { bar, _ in report(bar) })
                    observations.append(subview.observe(\.isHidden, options: [.new]) { bar, _ in report(bar) })
                }
                queue.append(subview)
            }
        }
        return observations
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.observation?.invalidate()
        coordinator.observation = nil
        coordinator.barObservations.forEach { $0.invalidate() }
        coordinator.barObservations = []
        coordinator.pendingDiscoveries.forEach { $0.cancel() }
        coordinator.pendingDiscoveries = []
        controller.player = nil
    }
}
