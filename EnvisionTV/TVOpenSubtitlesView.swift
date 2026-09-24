import SwiftUI

/// OpenSubtitles search for the TV player, mirroring the phone's
/// `OpenSubtitlesSheet`: pick a language, search through the server (which
/// holds the API key and calls OpenSubtitles itself), and pick a result to
/// download and activate. The shared `PlaybackEngine` does the parsing and
/// caption rendering, so this panel is only search results and focus handling.
struct TVOpenSubtitlesPanel: View {
    @ObservedObject var engine: PlaybackEngine
    let api: JellymaxAPI
    let item: Item
    /// MENU: back to the track picker.
    let onClose: () -> Void
    /// A subtitle was downloaded and activated: the picker closes too, back to
    /// playback.
    let onApproved: () -> Void

    @State private var language = "en"
    @State private var results: [SubtitleSearchResult] = []
    @State private var loading = false
    @State private var message: String?
    @Namespace private var focusScope

    var body: some View {
        ZStack {
            // A shade deeper than the track picker's, so the two panels read
            // as separate layers when the search sits on top of it.
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    Text("OpenSubtitles").font(.title2.bold())
                    if loading { ProgressView().controlSize(.small) }
                }
                HStack(spacing: 18) {
                    Text("Language")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    languageField
                    Button("Search") { Task { await search() } }
                        .buttonStyle(TVTrackRowStyle(isSelected: false))
                        .frame(width: 220)
                        .disabled(language.isEmpty)
                }
                if let message {
                    Text(message)
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                resultsList
            }
            .padding(64)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .focusScope(focusScope)
        // MENU closes the search and returns to the picker underneath; the
        // hosting controller intercepts the press first, this is the backstop.
        .onExitCommand { onClose() }
        // Search the default language right away, like the phone's sheet.
        .task { await search() }
    }

    /// The server is case-insensitive about language codes, but the remote
    /// keyboard is slow, so a short monospaced field with the common default
    /// prefilled keeps most searches to a single Search press.
    private var languageField: some View {
        TextField("en", text: $language)
            .font(.system(size: 24, design: .monospaced))
            .onSubmit { Task { await search() } }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .frame(width: 220)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
            )
            .modifier(TVDefaultFocus(isDefault: true, scope: focusScope))
    }

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty {
            if message == nil {
                Text(loading ? "Searching…" : "No subtitles found for that language.")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(results) { result in
                        Button {
                            Task { await download(result) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.FileName)
                                    .lineLimit(1)
                                Text("\(result.Language.uppercased()) · \(result.DownloadCount) downloads\(result.HearingImpaired ? " · SDH" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(TVTrackRowStyle(isSelected: false))
                        .disabled(loading)
                    }
                }
            }
            .frame(maxHeight: 460)
        }
    }

    private func search() async {
        let term = language.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, !loading else { return }
        loading = true
        message = nil
        defer { loading = false }
        do {
            results = try await api.subtitleSearch(item.Id, language: term)
            if results.isEmpty {
                message = "No subtitles found for “\(term)”. Check the language code — it is a two-letter code like en, de, or ja."
            }
        } catch {
            results = []
            message = error.localizedDescription
        }
    }

    private func download(_ result: SubtitleSearchResult) async {
        guard !loading else { return }
        loading = true
        message = nil
        defer { loading = false }
        do {
            // The engine fetches the file through the server, parses it, and
            // starts rendering captions — exactly the phone's path.
            try await engine.downloadAndLoadSubtitle(itemId: item.Id, result: result)
            // An external file replaces any embedded selection, as on the phone.
            engine.selectSubtitle(nil)
            onApproved()
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Presents the OpenSubtitles search as its own modal view controller, for the
/// same reason the track picker is one: panels drawn inside the player's cover
/// share AVKit's focus environment and the remote never reaches them. It sits
/// on top of the track picker, so dismissing it returns there; the picker's
/// close handler still owns resuming playback.
@MainActor
enum TVOpenSubtitlesPresentation {
    private static weak var presented: UIViewController?

    /// Returns whether the panel was presented — the picker ignores the press
    /// when the search is somehow already up.
    @discardableResult
    static func present(engine: PlaybackEngine, api: JellymaxAPI, item: Item) -> Bool {
        guard presented == nil, let host = TVTracksPresentation.topmostController() else { return false }
        let panel = TVOpenSubtitlesPanel(
            engine: engine,
            api: api,
            item: item,
            onClose: { TVOpenSubtitlesPresentation.dismiss() },
            onApproved: { TVOpenSubtitlesPresentation.finishAndClosePicker() }
        )
        let controller = TVPanelHostingController(rootView: AnyView(panel))
        controller.onMenu = { TVOpenSubtitlesPresentation.dismiss() }
        controller.onClosed = { presented = nil }
        // Clear so the picker stays visible behind the panel's dimmed backdrop.
        controller.view.backgroundColor = .clear
        // overFullScreen, so the picker's view never disappears and its focus
        // scope survives underneath.
        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve
        presented = controller
        host.present(controller, animated: true)
        return true
    }

    /// MENU or back: close the search, restore the picker's focus.
    static func dismiss() {
        guard let controller = presented else { return }
        presented = nil
        controller.dismiss(animated: true) {
            TVTracksPresentation.restoreFocus()
        }
    }

    /// A subtitle was approved: back to playback. The search closes without
    /// waiting for its animation and the picker goes with it — its close
    /// handler resumes playback when it runs.
    static func finishAndClosePicker() {
        guard let controller = presented else { return }
        presented = nil
        controller.dismiss(animated: false)
        TVTracksPresentation.dismiss()
    }
}

