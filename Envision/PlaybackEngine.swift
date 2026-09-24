import Foundation
import AVFoundation
import AVKit
import Combine

/// Port of components/Player.tsx playback logic: fetch playback info, pick the
/// best source (direct stream, else HLS transcoding), drive an AVPlayer, and
/// report progress/stopped to the backend.
@MainActor
final class PlaybackEngine: NSObject, ObservableObject {
    @Published var player: AVPlayer?
    @Published var source: MediaSource?
    @Published var error: String?
    @Published var duration = 0.0
    @Published var currentTime = 0.0
    @Published var isPlaying = false
    // External subtitle state (parsed WebVTT/SRT rendered as an overlay,
    // mirroring the web player's caption handling).
    @Published var captionText = ""
    @Published var externalSubtitleName: String?
    var cues: [SubtitleCue] = []

    /// Media selection groups are loaded asynchronously after the item exists —
    /// the synchronous `mediaSelectionGroup(forMediaCharacteristic:)` accessor
    /// is deprecated as of macOS 13.
    @Published var audioSelectionGroup: AVMediaSelectionGroup?
    @Published var legibleSelectionGroup: AVMediaSelectionGroup?
    /// Bumped whenever the active media selection changes so the track pickers
    /// re-read `selectedAudio` / `selectedSubtitle`.
    @Published var selectionRevision = 0
    /// Embedded audio/subtitle selection lives on the server, not in the HLS
    /// stream AVPlayer inspects: jellymax packs one soundtrack per HLS variant
    /// (`AudioTrackUrls`) and delivers text subtitles via a `DeliveryUrl`
    /// endpoint. Both are managed here, mirroring components/Player.tsx.
    @Published var selectedServerAudioIndex: Int?
    @Published var selectedServerSubtitleIndex: Int?
    @Published var isSubtitleLoading = false
    /// Server-delivered subtitle bookkeeping: the DeliveryUrl of the active
    /// track and the fetched window, so the 250 ms observer can pull the next
    /// 90-second remote window before captions run out.
    var serverSubtitleDelivery: String?
    var subtitleWindowStart: Double?
    var subtitleWindowTask: Task<Void, Never>?
    /// True while AVPlayer is stalling to buffer (drives the spinner the AVKit
    /// player used to supply itself).
    @Published var isBuffering = false
    /// Picture-in-picture controller, created once the video surface hands
    /// back its AVPlayerLayer (see `VideoSurface.onAttach`).
    @Published var pipController: AVPictureInPictureController?
    @Published var canStartPiP = false
    @Published var isPiPActive = false
    var pipObservation: NSKeyValueObservation?
    @Published var playbackWarning: String?
    var seekID = UUID()
    /// The position requested by an in-flight seek. The timeline shows it
    /// optimistically — exactly like the web player's `seek()` — so dragging
    /// never snaps back to the stale player time before AVPlayer confirms.
    @Published var pendingSeek: Double?
    /// Decoded video dimensions (drives the surface's aspect ratio).
    @Published var videoSize: CGSize = .zero

    let api: JellymaxAPI
    private let item: Item
    private var playSessionId: String?
    private var timeObserver: Any?
    private var periodicReporter: Any?
    private var endObserver: NSObjectProtocol?
    private var selectionObserver: NSObjectProtocol?
    private var reportedStopped = false
    private var startTimeTicks: Int64 = 0
    private var preparationTask: Task<Void, Never>?
    private var started = false

    init(api: JellymaxAPI, item: Item) {
        self.api = api
        self.item = item
    }

    /// Only one episode may own playback, even while navigation retains old pages.
    private static weak var activeEngine: PlaybackEngine?

    static func stopActivePlayback() {
        activeEngine?.teardown()
    }

    func start() {
        guard !started else { return }
        if let previous = Self.activeEngine, previous !== self {
            previous.teardown()
        }
        Self.activeEngine = self
        started = true
        reportedStopped = false
        preparationTask = Task { await prepareAndPlay() }
    }

    func teardown() {
        if Self.activeEngine === self { Self.activeEngine = nil }
        preparationTask?.cancel()
        preparationTask = nil
        started = false
        seekID = UUID()
        pendingSeek = nil
        pipController?.stopPictureInPicture()
        removeObservers()
        if !reportedStopped {
            reportedStopped = true
            let ticks = Int64(currentTime * Double(TICKS_PER_SECOND))
            let session = playSessionId
            let id = item.Id
            Task { try? await api.reportStopped(itemId: id, positionTicks: ticks, playSessionId: session) }
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        isPlaying = false
        isBuffering = false
        clearSubtitle()
        pipObservation?.invalidate()
        pipObservation = nil
        pipController = nil
        canStartPiP = false
        isPiPActive = false
    }

    func prepareAndPlay() async {
        error = nil
        let resumeTicks = item.UserData?.PlaybackPositionTicks ?? 0
        let played = item.UserData?.Played ?? false
        startTimeTicks = (resumeTicks > 0 && !played) ? resumeTicks : 0
        do {
            let info = try await api.playbackInfo(item.Id, startTimeTicks: startTimeTicks)
            try Task.checkCancellation()
            guard let source = info.MediaSources.first else {
                throw APIError.failed(0, "No playable media sources were returned for this item.")
            }
            self.source = source
            playSessionId = info.PlaySessionId
            // Default to the container's first soundtrack, like the web player.
            selectedServerAudioIndex = source.MediaStreams.first { $0.streamType == "Audio" }?.Index

            var path: String?
            if source.SupportsDirectPlay || source.SupportsDirectStream, !source.DirectStreamUrl.isEmpty {
                path = source.DirectStreamUrl
                if startTimeTicks > 0 { path = appendStartTime(path, startTimeTicks) }
            } else if let transcoding = source.TranscodingUrl {
                path = transcoding
            } else if let fallback = source.FallbackTranscodingUrl {
                path = fallback
            } else if let audioOnly = source.AudioTranscodingUrl {
                path = audioOnly
            }
            guard let path, let url = api.resolveURL(path) else {
                throw APIError.failed(0, "The server did not provide a playable stream URL.")
            }

            let playerItem = AVPlayerItem(asset: AVURLAsset(url: url))
            let newPlayer = AVPlayer(playerItem: playerItem)
            if startTimeTicks > 0 {
                await newPlayer.seek(to: CMTime(seconds: Double(startTimeTicks) / Double(TICKS_PER_SECOND), preferredTimescale: 600))
            }
            #if os(iOS)
            // Background audio / PiP requires an active playback session.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            #endif

            try Task.checkCancellation()
            installObservers(player: newPlayer, playerItem: playerItem)
            player = newPlayer
            newPlayer.play()
        } catch is CancellationError {
            // Navigating away must not publish a playback error or start audio.
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func appendStartTime(_ path: String?, _ ticks: Int64) -> String? {
        guard var path else { return nil }
        let separator = path.contains("?") ? "&" : "?"
        path += "\(separator)StartTimeTicks=\(ticks)"
        return path
    }

    private func installObservers(player: AVPlayer, playerItem: AVPlayerItem) {
        installPlayerObservers(player)
        installItemObservers(playerItem)
    }

    private func installPlayerObservers(_ player: AVPlayer) {
        // 250 ms cadence keeps external-subtitle cues reasonably in sync
        // (the web player drives captions from requestAnimationFrame).
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 10), queue: .main
        ) { [weak self] time in
            // Observer blocks are @Sendable; queue: .main guarantees the main
            // actor is current, so re-enter it before touching engine state.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlaying = player.timeControlStatus == .playing
                self.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                // While a scrub is in flight the requested position wins:
                // publishing the player's (not-yet-updated) time would snap
                // the knob backwards until the seek lands.
                if self.pendingSeek == nil {
                    let actual = player.currentTime().seconds
                    let seconds = actual.isFinite ? actual : 0
                    self.currentTime = seconds
                    self.updateCaption(for: seconds)
                }
                if let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0 {
                    self.duration = duration
                }
                let presentation = player.currentItem?.presentationSize ?? .zero
                if presentation.width > 0, presentation.height > 0, presentation != self.videoSize {
                    self.videoSize = presentation
                }
            }
        }
        periodicReporter = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 10, preferredTimescale: 1), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                let ticks = Int64(time.seconds * Double(TICKS_PER_SECOND))
                let session = self.playSessionId
                let id = self.item.Id
                Task { try? await self.api.reportProgress(itemId: id, positionTicks: ticks, playSessionId: session) }
            }
        }
    }

    /// Item-scoped observers plus the async media-selection group load. Re-run
    /// for every `replaceCurrentItem`, including audio-track switches.
    private func installItemObservers(_ playerItem: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main
        ) { [weak self] _ in
            // The notification block is @Sendable, so hop back onto the main
            // actor (queue: .main above guarantees this is safe) before
            // touching actor-isolated state.
            MainActor.assumeIsolated { self?.handlePlayedToEnd() }
        }
        selectionObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.mediaSelectionDidChangeNotification, object: playerItem, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.selectionRevision += 1 }
        }
        loadSelectionGroups(for: playerItem)
    }

    /// Swap the current item for a new stream without rebuilding the AVPlayer:
    /// the video surface and PiP controller keep their layer, item observers
    /// and selection groups are re-attached, and playback resumes at
    /// `position`. Mirrors the web player swapping `playbackUrl`.
    func switchStream(to path: String, resumingAt position: Double) async {
        guard let player, let url = api.resolveURL(path) else { return }
        let wasPlaying = isPlaying || player.timeControlStatus == .playing
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let selectionObserver { NotificationCenter.default.removeObserver(selectionObserver) }
        endObserver = nil
        selectionObserver = nil
        audioSelectionGroup = nil
        legibleSelectionGroup = nil
        let newItem = AVPlayerItem(asset: AVURLAsset(url: url))
        installItemObservers(newItem)
        player.replaceCurrentItem(with: newItem)
        seek(to: position)
        if wasPlaying { player.play() }
    }

    /// The player finished the item: report the runtime as the final position
    /// and mark it stopped so `teardown()` does not report again.
    func handlePlayedToEnd() {
        isPlaying = false
        isBuffering = false
        pendingSeek = nil
        reportedStopped = true
        let session = playSessionId
        let id = item.Id
        let ticks = Int64(item.RunTimeTicks ?? 0)
        Task { try? await api.reportStopped(itemId: id, positionTicks: ticks, playSessionId: session) }
    }

    /// Load the audible/legible media selection groups asynchronously (macOS 13+
    /// replacement for the deprecated synchronous accessor).
    private func loadSelectionGroups(for playerItem: AVPlayerItem) {
        let asset = playerItem.asset
        Task { [weak self] in
            let audible = try? await asset.loadMediaSelectionGroup(for: .audible)
            let legible = try? await asset.loadMediaSelectionGroup(for: .legible)
            guard let self, self.player?.currentItem === playerItem else { return }
            self.audioSelectionGroup = audible
            self.legibleSelectionGroup = legible
            self.selectionRevision += 1
        }
    }

    private func removeObservers() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let periodicReporter { player?.removeTimeObserver(periodicReporter) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let selectionObserver { NotificationCenter.default.removeObserver(selectionObserver) }
        timeObserver = nil
        periodicReporter = nil
        endObserver = nil
        selectionObserver = nil
    }
}
