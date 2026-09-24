import Foundation
import AVFoundation
import AVKit

// Controls + track selection for PlaybackEngine (extension keeps files small).
extension PlaybackEngine {
    func togglePlayPause() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    /// Optimistic seek, mirroring the web player's `seek()`: the UI adopts the
    /// requested position immediately, and the periodic observer defers to
    /// `pendingSeek` until AVPlayer confirms the jump. Rapid successive seeks
    /// are safe — a completion only clears the pending value it matches.
    func seek(to seconds: Double) {
        guard let player, seconds.isFinite else { return }
        let limit = duration.isFinite && duration > 0 ? duration : .infinity
        let target = min(max(seconds, 0), limit)
        let requestID = UUID()
        seekID = requestID
        playbackWarning = nil
        currentTime = target
        pendingSeek = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] finished in
            Task { @MainActor [weak self, weak player] in
                guard let self, let player, self.player === player,
                      self.seekID == requestID else { return }
                self.pendingSeek = nil
                if finished {
                    self.currentTime = target
                    self.updateCaption(for: target)
                } else {
                    let actual = player.currentTime().seconds
                    if actual.isFinite { self.currentTime = actual }
                    self.playbackWarning = "This stream could not seek to that position. Please try again."
                }
            }
        }
    }

    func skip(by seconds: Double) {
        seek(to: max(0, currentTime + seconds))
    }

    /// Available audio tracks, populated asynchronously once the asset's
    /// media selection groups finish loading (see `loadSelectionGroups`).
    var audioTracks: [AVMediaSelectionOption] {
        audioSelectionGroup?.options ?? []
    }

    /// Available subtitle tracks (external HLS/WebVTT subtitle renditions).
    var subtitleTracks: [AVMediaSelectionOption] {
        legibleSelectionGroup?.options ?? []
    }

    func selectAudio(_ option: AVMediaSelectionOption?) {
        guard let item = player?.currentItem, let group = audioSelectionGroup else { return }
        item.select(option, in: group)
        selectionRevision += 1
    }

    func selectSubtitle(_ option: AVMediaSelectionOption?) {
        guard let item = player?.currentItem, let group = legibleSelectionGroup else { return }
        item.select(option, in: group)
        selectionRevision += 1
    }

    var selectedAudio: AVMediaSelectionOption? {
        guard let item = player?.currentItem, let group = audioSelectionGroup else { return nil }
        return item.currentMediaSelection.selectedMediaOption(in: group)
    }

    var selectedSubtitle: AVMediaSelectionOption? {
        guard let item = player?.currentItem, let group = legibleSelectionGroup else { return nil }
        return item.currentMediaSelection.selectedMediaOption(in: group)
    }

    // MARK: Server-side tracks (embedded audio + subtitles)

    /// Embedded soundtracks reported by the server for this item.
    var serverAudioStreams: [MediaStream] {
        source?.MediaStreams.filter { $0.streamType == "Audio" && $0.Index != nil } ?? []
    }

    /// Embedded text subtitles the server can deliver via its subtitle
    /// endpoint (`DeliveryUrl`), like the web player's subtitle menu.
    var serverSubtitleStreams: [MediaStream] {
        source?.MediaStreams.filter {
            $0.streamType == "Subtitle" && $0.Index != nil && $0.DeliveryUrl != nil
        } ?? []
    }

    /// Human label for a server stream, mirroring the web player's menu entries:
    /// `LANGUAGE · Title · Default · CODEC`, falling back to `Track N`.
    func mediaStreamLabel(_ stream: MediaStream, ordinal: Int = 0) -> String {
        let language = stream.Language?.lowercased() == "und" ? nil : stream.Language
        var parts: [String] = []
        if let language, !language.isEmpty {
            parts.append(language.uppercased())
        } else {
            parts.append("Track \(ordinal + 1)")
        }
        if let title = stream.Title, !title.isEmpty { parts.append(title) }
        if stream.IsDefault == true { parts.append("Default") }
        if let codec = stream.Codec, !codec.isEmpty { parts.append(codec.uppercased()) }
        return parts.joined(separator: " · ")
    }

    /// Switch the embedded soundtrack. jellymax exposes one audio rendition per
    /// HLS variant, so switching means restarting the stream with the chosen
    /// `AudioStreamIndex` at the current position (web `selectAudioTrack`).
    func selectServerAudio(_ index: Int) async {
        guard index != selectedServerAudioIndex else { return }
        guard let path = source?.AudioTrackUrls?["\(index)"] else {
            playbackWarning = "This soundtrack is unavailable."
            return
        }
        // Re-issue the session id and resume from the segment containing the
        // playhead, exactly like the web player does before swapping the URL.
        var components = URLComponents(string: path)
        var query = (components?.queryItems ?? []).filter {
            $0.name != "PlaySessionId" && $0.name != "StartIndex"
        }
        query.append(URLQueryItem(
            name: "PlaySessionId",
            value: UUID().uuidString.replacingOccurrences(of: "-", with: "")
        ))
        query.append(URLQueryItem(
            name: "StartIndex",
            value: String(Int(currentTime / 6))
        ))
        components?.queryItems = query
        selectedServerAudioIndex = index
        await switchStream(to: components?.url?.absoluteString ?? path, resumingAt: currentTime)
    }

    // MARK: Picture in Picture

    /// True once the surface's AVPlayerLayer is attached AND ready for
    /// picture-in-picture (drives the PiP button's visibility).
    func preparePiP(for layer: AVPlayerLayer) {
        guard pipController?.playerLayer !== layer,
              pipController?.isPictureInPictureActive != true,
              AVPictureInPictureController.isPictureInPictureSupported()
        else { return }
        pipObservation?.invalidate()
        let controller = AVPictureInPictureController(
            contentSource: .init(playerLayer: layer)
        )
        pipObservation = controller.observe(
            \.isPictureInPicturePossible, options: [.initial, .new]
        ) { [weak self] controller, _ in
            Task { @MainActor [weak self, weak controller] in
                guard let self, let controller, self.pipController === controller else { return }
                self.canStartPiP = controller.isPictureInPicturePossible
            }
        }
        controller.delegate = self
        pipController = controller
    }

    func togglePiP() {
        guard let controller = pipController else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
            return
        }
        guard controller.isPictureInPicturePossible else { return }
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            playbackWarning = "Could not enable Picture in Picture audio: \(error.localizedDescription)"
            return
        }
        #endif
        playbackWarning = nil
        controller.startPictureInPicture()
    }
}
