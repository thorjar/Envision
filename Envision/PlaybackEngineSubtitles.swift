import Foundation

// External subtitle handling for PlaybackEngine (port of the subtitle parts of
// components/Player.tsx: parsed WebVTT overlay, OpenSubtitles search/download).
extension PlaybackEngine {
    /// Parse and activate subtitle content (SRT or VTT text).
    func loadSubtitle(content: String, name: String) throws {
        let vtt = try toWebVtt(content, fileName: name)
        let parsed = parseWebVtt(vtt)
        guard !parsed.isEmpty else {
            throw APIError.failed(0, "This subtitle file contains no readable cues.")
        }
        cues = parsed
        externalSubtitleName = name
        updateCaption(for: currentTime)
    }

    /// Turn external subtitles off.
    func clearSubtitle() {
        cues = []
        externalSubtitleName = nil
        captionText = ""
        selectedServerSubtitleIndex = nil
        serverSubtitleDelivery = nil
        subtitleWindowStart = nil
        subtitleWindowTask?.cancel()
        subtitleWindowTask = nil
        isSubtitleLoading = false
    }

    /// Activate an embedded subtitle track through the server's `DeliveryUrl`
    /// endpoint (served as WebVTT), mirroring the web player's subtitle loading.
    /// Remote items are extracted by jellymax in 90-second windows, so the
    /// request carries `StartSeconds` and a fresh window is fetched as playback
    /// approaches the end of the current one — exactly like the web player.
    func selectServerSubtitle(_ stream: MediaStream) async {
        subtitleWindowTask?.cancel()
        subtitleWindowTask = nil
        clearSubtitle()
        selectSubtitle(nil)
        guard let delivery = stream.DeliveryUrl, let index = stream.Index else { return }
        serverSubtitleDelivery = delivery
        selectedServerSubtitleIndex = index
        await fetchServerSubtitleWindow(at: max(0, currentTime - 15))
    }

    /// Fetch one subtitle window. Local items get the complete track (the
    /// server ignores `StartSeconds` for seekable files); remote items get a
    /// 90-second window that must be refreshed as playback advances.
    private func fetchServerSubtitleWindow(at seconds: Double) async {
        guard let delivery = serverSubtitleDelivery,
              selectedServerSubtitleIndex != nil else { return }
        isSubtitleLoading = true
        defer { isSubtitleLoading = false }
        var address = delivery
        address += (delivery.contains("?") ? "&" : "?")
            + "StartSeconds=\(Int(max(0, seconds)))"
        do {
            let content = try await api.fetchText(address)
            guard selectedServerSubtitleIndex != nil, serverSubtitleDelivery != nil else { return }
            subtitleWindowStart = max(0, seconds)
            cues = parseWebVtt(content)
            updateCaption(for: currentTime)
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            playbackWarning = "This subtitle track could not be loaded."
            selectedServerSubtitleIndex = nil
        }
    }

    /// Keep the active window current: refresh when the playhead nears the end
    /// of the fetched span or a seek lands far outside it. Called from
    /// `updateCaption`, which the 250 ms time observer drives.
    func checkSubtitleWindow(for time: TimeInterval) {
        guard let windowStart = subtitleWindowStart,
              selectedServerSubtitleIndex != nil,
              !isSubtitleLoading else { return }
        let drift = time - windowStart
        guard drift > 80 || drift < -40 else { return }
        subtitleWindowTask?.cancel()
        let position = max(0, time - 15)
        subtitleWindowTask = Task { await fetchServerSubtitleWindow(at: position) }
    }

    /// True when the external subtitle with this name is active.
    func isExternalSubtitleActive(_ name: String) -> Bool {
        externalSubtitleName == name
    }

    /// Refresh the caption overlay from the active cue list.
    func updateCaption(for time: TimeInterval) {
        checkSubtitleWindow(for: time)
        captionText = cues.isEmpty ? "" : visibleSubtitle(cues, at: time)
    }

    /// Download a subtitle from OpenSubtitles via the backend and activate it.
    func downloadAndLoadSubtitle(itemId: String, result: SubtitleSearchResult) async throws {
        let payload = try await api.downloadSubtitle(itemId, fileId: result.FileId)
        guard let content = payload["Content"] else {
            throw APIError.failed(0, "The subtitle download returned no content.")
        }
        let format = payload["Format"] ?? "srt"
        try loadSubtitle(content: content, name: "OpenSubtitles-\(result.Language).\(format)")
    }
}
