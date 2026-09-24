import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Port of the Player.tsx UI: video surface, transport controls, track menus.
struct PlayerView: View {
    let item: Item
    @StateObject private var engine: PlaybackEngine
    @State private var fullScreen = false
    @State private var automaticFullScreen = false

    init(item: Item) {
        self.item = item
        _engine = StateObject(wrappedValue: PlaybackEngine(api: AuthStoreLocator.api, item: item))
    }

    var body: some View {
        PlaybackContent(item: item, engine: engine, fullScreen: inlineFullScreen,
                        hideSurface: presentingCover, toggleFullScreen: toggleFullScreen)
            .preference(key: PlaybackFullScreenPreference.self, value: inlineFullScreen)
            .onAppear { engine.start() }
            .onDisappear {
                // Only an iOS cover temporarily hides the inline player.
                // Mac window fullscreen must not suppress navigation teardown.
                if !presentingCover { engine.teardown() }
            }
        #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
                fullScreen = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
                fullScreen = false
            }
        #endif
        #if os(iOS)
            .fullScreenCover(isPresented: $fullScreen) {
                PlaybackContent(item: item, engine: engine, fullScreen: true,
                                toggleFullScreen: { fullScreen = false; automaticFullScreen = false })
                    .background(.black)
                    .preferredColorScheme(.dark)
                    .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                        updateOrientation()
                    }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                updateOrientation()
            }
            .onAppear {
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                updateOrientation()
            }
            .onDisappear {
                if !fullScreen { UIDevice.current.endGeneratingDeviceOrientationNotifications() }
            }
        #endif
    }

    private var inlineFullScreen: Bool {
        #if os(macOS)
        fullScreen
        #else
        false
        #endif
    }

    private var presentingCover: Bool {
        #if os(macOS)
        false
        #else
        fullScreen
        #endif
    }

    private func toggleFullScreen() {
        #if os(macOS)
        NSApp.keyWindow?.toggleFullScreen(nil)
        #else
        automaticFullScreen = false
        fullScreen.toggle()
        #endif
    }

    #if os(iOS)
    private func updateOrientation() {
        let orientation = UIDevice.current.orientation
        if orientation.isLandscape {
            if !fullScreen { automaticFullScreen = true; fullScreen = true }
        } else if orientation.isPortrait, automaticFullScreen {
            fullScreen = false
            automaticFullScreen = false
        }
    }
    #endif
}

/// Presentation only: full-screen and inline views share one playback engine.
private struct PlaybackContent: View {
    let item: Item
    @ObservedObject var engine: PlaybackEngine
    var fullScreen: Bool
    var hideSurface = false
    var toggleFullScreen: () -> Void

    @State private var showPlaybackOptions = false
    @State private var showAudioOptions = false
    @State private var showSubtitleMenu = false
    @State private var showOpenSubtitles = false
    @State private var showSubtitleImporter = false
    @State private var subtitleError: String?
    @State private var controlsVisible = true
    @State private var isScrubbing = false
    @State private var hideControlsTask: Task<Void, Never>?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var body: some View {
        GeometryReader { geometry in
        if fullScreen {
            fullScreenVideo
        } else {
        VStack(alignment: .leading, spacing: 12) {
            if let message = engine.error {
                Text(message)
                    .foregroundStyle(.red)

            } else if let player = engine.player {
                ZStack {
                    Color.black
                    if !hideSurface {
                        VideoSurface(player: player, cornerRadius: fullScreen ? 0 : 12) { view in
                            Task { @MainActor in engine.preparePiP(for: view.currentPlayerLayer) }
                        }
                    }
                }
                    .frame(maxWidth: .infinity)
                    .frame(height: min(geometry.size.width / videoAspectRatio,
                                       max(80, geometry.size.height - 160)))
                    .clipShape(
                        RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay(alignment: .bottom) {
                        captionOverlay
                            .padding(.bottom, 34)
                    }
                    .overlay {
                        if engine.isBuffering {
                            ProgressView()
                                .controlSize(.large)
                        }
                    }
                    .overlay { playbackGestureLayer }

                controls

            } else {
                ZStack {
                    Color.black
                        .opacity(0.85)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 12)
                        )

                    ProgressView("Preparing playback…")
                        .controlSize(.large)
                }
                .frame(maxWidth: .infinity)
            }

            HStack {
                Text(item.Name)
                    .bold()

                Spacer()

                Text(statusLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        }
        .onAppear { revealControls() }
        .onDisappear { hideControlsTask?.cancel() }
        .onChange(of: fullScreen) { _, _ in revealControls() }
        .onChange(of: engine.isPlaying) { _, _ in revealControls() }
        .onChange(of: showPlaybackOptions) { _, _ in revealControls() }
        .onChange(of: showAudioOptions) { _, _ in revealControls() }
        .onChange(of: showOpenSubtitles) { _, _ in revealControls() }
        .onChange(of: showSubtitleImporter) { _, _ in revealControls() }
        .onChange(of: engine.playbackWarning) { _, _ in revealControls() }
        .onChange(of: voiceOverEnabled) { _, _ in revealControls() }
        .sheet(isPresented: $showOpenSubtitles) {
            OpenSubtitlesSheet(
                item: item,
                engine: engine
            )
        }
        .fileImporter(
            isPresented: $showSubtitleImporter,
            allowedContentTypes: subtitleContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleSubtitleImport(result)
        }
    }

    private var usesCenteredTransport: Bool {
        #if os(iOS)
        fullScreen && UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    /// The media owns the entire full-screen canvas; controls never reduce it.
    private var fullScreenVideo: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = engine.player, !hideSurface {
                VideoSurface(player: player, cornerRadius: 0) { view in
                    Task { @MainActor in engine.preparePiP(for: view.currentPlayerLayer) }
                }
                .ignoresSafeArea()
            }

            // Below the controls so button clicks never also toggle playback.
            playbackGestureLayer

            if engine.isBuffering || engine.player == nil {
                ProgressView().tint(.white).allowsHitTesting(false)
            }
            if let error = engine.error {
                Text(error).foregroundStyle(.red).padding()
            }
        }
        .overlay {
            if usesCenteredTransport && controlsVisible {
                transportControls(compact: false, overVideo: true)
                    .foregroundStyle(.white)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            captionOverlay
                .padding(.bottom, controlsVisible ? 160 : 20)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            if controlsVisible {
                VStack(spacing: 0) {
                    HStack {
                        Text(item.Name).font(.callout.bold()).lineLimit(1)
                        Spacer(minLength: 12)
                        Text(statusLine).font(.caption.monospacedDigit())
                    }
                    controls
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(.white)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .simultaneousGesture(TapGesture().onEnded { revealControls() })
                .transition(.opacity)
            }
        }
        .onContinuousHover { phase in
            if case .active = phase { revealControls() }
        }
    }

    private var playbackGestureLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                guard !showPlaybackOptions, !showAudioOptions else { return }
                engine.togglePlayPause()
                revealControls()
            }
            .onContinuousHover { phase in
                if case .active = phase { revealControls() }
            }
            .accessibilityLabel(engine.isPlaying ? "Pause video" : "Play video")
            .accessibilityAddTraits(.isButton)
    }

    private func revealControls() {
        hideControlsTask?.cancel()
        if !controlsVisible {
            withAnimation(.easeOut(duration: 0.2)) { controlsVisible = true }
        }
        guard fullScreen, !isScrubbing, !voiceOverEnabled,
              !showPlaybackOptions, !showAudioOptions, !showOpenSubtitles, !showSubtitleImporter else { return }
        hideControlsTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(4)) }
            catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { controlsVisible = false }
        }
    }

    private var videoAspectRatio: CGFloat {
        engine.videoSize.height > 0 ? engine.videoSize.width / engine.videoSize.height : 16 / 9
    }

    // MARK: - Captions

    /// Parsed WebVTT caption overlay for externally loaded subtitles.
    @ViewBuilder
    private var captionOverlay: some View {
        if !engine.captionText.isEmpty {
            Text(engine.captionText)
                .font(.system(size: 20, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .shadow(
                    color: .black,
                    radius: 3
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    .black.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Status

    /// Elapsed / total runtime for the item being played.
    private var statusLine: String {
        var parts = [
            formatSeconds(engine.currentTime)
        ]

        if engine.duration > 0 {
            parts.append(
                formatSeconds(engine.duration)
            )
        }

        return parts.joined(separator: " / ")
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: fullScreen ? 0 : 8) {
            PlaybackTimeline(position: engine.currentTime, duration: engine.duration,
                             onEditingChanged: { editing in
                                 isScrubbing = editing
                                 revealControls()
                             }) {
                engine.seek(to: $0)
                revealControls()
            }

            if usesCenteredTransport {
                HStack {
                    Spacer(minLength: 0)
                    secondaryControls
                }
            } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Color.clear.frame(width: 132, height: 1)
                    Spacer(minLength: 8)
                    transportControls(compact: fullScreen)
                    Spacer(minLength: 8)
                    secondaryControls
                }
                HStack(spacing: 0) {
                    transportControls(compact: true)
                    Spacer(minLength: 0)
                    secondaryControls
                }
            }
            }

            if let warning = engine.playbackWarning {
                Text(warning).font(.caption).foregroundStyle(.orange)
            }
            if let subtitleError {
                Text(subtitleError).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func transportControls(compact: Bool, overVideo: Bool = false) -> some View {
            HStack(spacing: overVideo ? 24 : (compact ? 2 : 8)) {
                Button {
                    engine.skip(by: -10)
                    revealControls()
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: compact ? 23 : 28, weight: .semibold))
                        .frame(width: compact ? 44 : 56, height: compact ? 44 : 56)
                        .background(Color.black.opacity(overVideo ? 0.4 : 0), in: Circle())
                        .contentShape(Circle())
                }
                .accessibilityLabel("Back 10 seconds")

                Button {
                    engine.togglePlayPause()
                    revealControls()
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: compact ? 26 : 34, weight: .semibold))
                        .frame(width: compact ? 48 : 68, height: compact ? 48 : 68)
                        .background(overVideo ? Color.black.opacity(0.4) : Color.primary.opacity(0.12), in: Circle())
                        .contentShape(Circle())
                }
                .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")

                Button {
                    engine.skip(by: 30)
                    revealControls()
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.system(size: compact ? 23 : 28, weight: .semibold))
                        .frame(width: compact ? 44 : 56, height: compact ? 44 : 56)
                        .background(Color.black.opacity(overVideo ? 0.4 : 0), in: Circle())
                        .contentShape(Circle())
                }
                .accessibilityLabel("Forward 30 seconds")
            }
            .buttonStyle(.plain)
            .disabled(engine.player == nil)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var secondaryControls: some View {
        HStack(spacing: 0) {
            if engine.serverAudioStreams.count > 1 || engine.audioTracks.count > 1 {
                Button {
                    showAudioOptions = true
                } label: {
                    Label("Audio", systemImage: "speaker.fill")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .popover(isPresented: $showAudioOptions) {
                    audioOptionsPopover
                }
            }

            Button {
                hideControlsTask?.cancel()
                showPlaybackOptions = true
            } label: {
                Label("Subtitles", systemImage: "captions.bubble")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .popover(isPresented: $showPlaybackOptions) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        subtitleOptions
                    }
                    .padding(20)
                }
                .frame(width: 280, height: 300)
                .buttonStyle(.plain)
                .labelStyle(.titleAndIcon)
                .background(Color.black)
                .foregroundStyle(.white)
                .preferredColorScheme(.dark)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(Color.black)
                .transaction { $0.animation = nil }
            }

            Button {
                engine.togglePiP()
                revealControls()
            } label: {
                Label(engine.isPiPActive ? "Exit Picture in Picture" : "Picture in Picture",
                      systemImage: engine.isPiPActive ? "pip.exit" : "pip.enter")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!engine.canStartPiP && !engine.isPiPActive)
            .opacity(engine.canStartPiP || engine.isPiPActive ? 1 : 0.4)

            Button(action: toggleFullScreen) {
                Label(fullScreen ? "Exit full screen" : "Full screen",
                      systemImage: fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .font(.system(size: 18))
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .fixedSize()
    }

    @ViewBuilder
    private var audioOptionsPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Audio").font(.headline)

                if engine.serverAudioStreams.count > 1 {
                    // Embedded soundtracks: switching restarts the stream with
                    // the chosen AudioStreamIndex (server-side selection).
                    ForEach(
                        Array(engine.serverAudioStreams.enumerated()),
                        id: \.element.Index
                    ) { ordinal, stream in
                        Button(
                            engine.selectedServerAudioIndex == stream.Index
                                ? "✓ \(engine.mediaStreamLabel(stream, ordinal: ordinal))"
                                : engine.mediaStreamLabel(stream, ordinal: ordinal)
                        ) {
                            showAudioOptions = false
                            Task { await engine.selectServerAudio(stream.Index ?? 0) }
                        }
                    }
                } else {
                    Button(engine.selectedAudio == nil ? "✓ Off" : "Off") {
                        engine.selectAudio(nil)
                        showAudioOptions = false
                    }

                    ForEach(engine.audioTracks, id: \.self) { option in
                        Button(
                            trackLabel(option, selected: engine.selectedAudio == option)
                        ) {
                            engine.selectAudio(option)
                            showAudioOptions = false
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 280, height: 240)
        .buttonStyle(.plain)
        .labelStyle(.titleAndIcon)
        .background(Color.black)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .presentationCompactAdaptation(.popover)
        .presentationBackground(Color.black)
        .transaction { $0.animation = nil }
    }

    // MARK: - Subtitle Menu

    /// Subtitle menu: embedded tracks, imported files, OpenSubtitles search.
    @ViewBuilder
    private var subtitleOptions: some View {
            Text("Subtitles").font(.headline)
            Button(
                engine.selectedSubtitle == nil &&
                engine.externalSubtitleName == nil &&
                engine.selectedServerSubtitleIndex == nil
                    ? "✓ Off"
                    : "Off"
            ) {
                engine.clearSubtitle()
                engine.selectSubtitle(nil)
            }

            ForEach(
                engine.subtitleTracks,
                id: \.self
            ) { option in
                Button(
                    trackLabel(
                        option,
                        selected:
                            engine.selectedSubtitle == option
                    )
                ) {
                    engine.clearSubtitle()
                    engine.selectSubtitle(option)
                }
            }

            // Embedded text subtitles delivered through the server's subtitle
            // endpoint, like the web player's subtitle menu.
            ForEach(engine.serverSubtitleStreams, id: \.Index) { stream in
                Button(
                    engine.selectedServerSubtitleIndex == stream.Index
                        ? "✓ \(engine.mediaStreamLabel(stream))"
                        : engine.mediaStreamLabel(stream)
                ) {
                    showPlaybackOptions = false
                    Task { await engine.selectServerSubtitle(stream) }
                }
            }

            if let name = engine.externalSubtitleName {
                Button("✓ \(name)") {}
            }

            Divider()

            Button("Import SRT/VTT file…") {
                showSubtitleImporter = true
            }

            Button("Get more from OpenSubtitles…") {
                showOpenSubtitles = true
            }

    }

    // MARK: - Track Helpers

    /// Menu label for a media selection option.
    private func trackName(
        _ option: AVMediaSelectionOption?,
        fallback: String
    ) -> String {
        guard let option else {
            return fallback
        }

        return option.displayName.isEmpty
            ? fallback
            : option.displayName
    }

    /// Menu entry for a media selection option, ticked when active.
    private func trackLabel(
        _ option: AVMediaSelectionOption,
        selected: Bool
    ) -> String {
        let name = option.displayName.isEmpty
            ? "Track"
            : option.displayName

        return selected
            ? "✓ \(name)"
            : name
    }

    // MARK: - Subtitle File Import

    /// Content types accepted by the subtitle importer.
    private var subtitleContentTypes: [UTType] {
        ["srt", "vtt"].compactMap {
            UTType(filenameExtension: $0)
        }
    }

    /// Handle the result returned by SwiftUI's cross-platform file importer.
    private func handleSubtitleImport(
        _ result: Result<[URL], Error>
    ) {
        do {
            let urls = try result.get()

            guard let url = urls.first else {
                return
            }

            try loadSubtitleFile(url)

        } catch {
            subtitleError = error.localizedDescription
        }
    }

    /// Read an imported SRT/VTT file and activate it.
    ///
    /// iOS/iPadOS document picker URLs may be security scoped, so access
    /// is explicitly requested before reading the file.
    private func loadSubtitleFile(
        _ url: URL
    ) throws {
        let accessing =
            url.startAccessingSecurityScopedResource()

        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let content = try String(
            contentsOf: url,
            encoding: .utf8
        )

        try engine.loadSubtitle(
            content: content,
            name: url.lastPathComponent
        )

        // Disable any embedded subtitle track when using an
        // externally imported subtitle file.
        engine.selectSubtitle(nil)

        subtitleError = nil
    }
}


// MARK: - OpenSubtitles

/// Port of the Player.tsx OpenSubtitles search panel.
struct OpenSubtitlesSheet: View {
    let item: Item

    @ObservedObject var engine: PlaybackEngine

    @Environment(\.dismiss)
    private var dismiss

    @State private var language = "en"
    @State private var results: [SubtitleSearchResult] = []
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            HStack {
                Text("OpenSubtitles")
                    .font(.title3)
                    .bold()

                Spacer()

                Button("Done") {
                    dismiss()
                }
            }

            HStack {
                Text("Language")
                    .foregroundStyle(.secondary)

                TextField(
                    "en",
                    text: $language
                )
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)

                Button("Search") {
                    Task {
                        await search()
                    }
                }
                .disabled(
                    loading ||
                    language.isEmpty
                )

                if loading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            List(results) { result in
                Button {
                    Task {
                        await download(result)
                    }
                } label: {
                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(result.FileName)
                            .lineLimit(1)

                        Text(
                            "\(result.Language.uppercased()) · " +
                            "\(result.DownloadCount) downloads" +
                            "\(result.HearingImpaired ? " · SDH" : "")"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 260)
        }
        .padding(20)
        .frame(
            maxWidth: 520,
            minHeight: 420
        )
        .task {
            await search()
        }
    }

    private func search() async {
        loading = true
        message = nil

        defer {
            loading = false
        }

        do {
            results =
                try await AuthStoreLocator.api
                    .subtitleSearch(
                        item.Id,
                        language: language
                    )

            if results.isEmpty {
                message =
                    "Search by language to find subtitles."
            }

        } catch {
            message = error.localizedDescription
        }
    }

    private func download(
        _ result: SubtitleSearchResult
    ) async {
        loading = true
        message = nil

        defer {
            loading = false
        }

        do {
            try await engine
                .downloadAndLoadSubtitle(
                    itemId: item.Id,
                    result: result
                )

            engine.selectSubtitle(nil)

            dismiss()

        } catch {
            message = error.localizedDescription
        }
    }
}


// MARK: - Auth Store Locator

/// Minimal service locator so the player can build its engine before the
/// environment is available (init context cannot read @EnvironmentObject).
@MainActor
enum AuthStoreLocator {
    static var shared: AuthStore = AuthStore()

    static var api: JellymaxAPI {
        shared.api
    }
}
