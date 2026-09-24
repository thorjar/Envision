import SwiftUI
import Combine

/// Router shared by the sidebar and content column (React Router equivalent).
@MainActor
final class Router: ObservableObject {
    @Published var selection: Route = .home
    @Published var path: [Route] = []

    func go(_ route: Route) {
        // List re-asserts its selection binding during view updates (e.g.
        // whenever .searchable refreshes the toolbar). Re-publishing — and
        // especially tearing down active playback — from inside an update is
        // not allowed, so a navigation that changes nothing is skipped.
        guard selection != route || !path.isEmpty else { return }
        PlaybackEngine.stopActivePlayback()
        selection = route
        path = []
    }

    func push(_ route: Route) {
        // Stop before changing the route, not after the next page finishes loading.
        PlaybackEngine.stopActivePlayback()
        path.append(route)
    }

    func search(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        go(.search(trimmed))
    }
}

/// Top-level structure: login gate + sidebar/content split (components/Layout.tsx).
struct RootView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var router = Router()
    @State private var searchText = ""
    @State private var playbackFullScreen = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var previousColumnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        if auth.isRestoring {
            ProgressView("Connecting to server…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if auth.user == nil {
            LoginView()
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
            } detail: {
                NavigationStack(path: $router.path) {
                    content
                        .navigationDestination(for: Route.self) { route in
                            RouteView(route: route)
                        }
                        .searchable(text: $searchText, placement: .toolbar,
                                    prompt: "Search movies, episodes, songs…")
                        .onSubmit(of: .search) {
                            router.search(searchText)
                            searchText = ""
                        }
                }
            }
            .environmentObject(router)
            #if os(macOS)
            .environment(\.macPlaybackFullScreen, playbackFullScreen)
            .background(playbackFullScreen ? Color.black : Color.clear)
            .toolbar(playbackFullScreen ? .hidden : .automatic, for: .windowToolbar)
            .onPreferenceChange(PlaybackFullScreenPreference.self) { isFullScreen in
                guard playbackFullScreen != isFullScreen else { return }
                playbackFullScreen = isFullScreen
                if isFullScreen {
                    previousColumnVisibility = columnVisibility
                    columnVisibility = .detailOnly
                } else {
                    columnVisibility = previousColumnVisibility
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private var content: some View {
        switch router.selection {
        case .home: HomeView()
        case .libraries: LibrariesView()
        case .resume: ResumeView()
        case .favorites: FavoritesView()
        case .playlists: PlaylistsView()
        case .admin: AdminView()
        case .library(let id): LibraryView(libraryId: id)
        case .item(let id): ItemDetailView(itemId: id)
        case .play(let id): PlayerPage(itemId: id)
        case .playlist(let id): PlaylistDetailView(playlistId: id)
        case .search(let query): SearchView(query: query)
        }
    }
}

/// Pushed-route renderer (the navigationDestination switch).
struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .home: HomeView()
        case .libraries: LibrariesView()
        case .resume: ResumeView()
        case .favorites: FavoritesView()
        case .playlists: PlaylistsView()
        case .admin: AdminView()
        case .library(let id): LibraryView(libraryId: id)
        case .item(let id): ItemDetailView(itemId: id)
        case .play(let id): PlayerPage(itemId: id)
        case .playlist(let id): PlaylistDetailView(playlistId: id)
        case .search(let query): SearchView(query: query)
        }
    }
}
