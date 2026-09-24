import SwiftUI

/// Tracks the active tab and per-tab navigation paths. Pressing MENU on a
/// pushed page pops it (SwiftUI default); pressing MENU at a non-Home tab's
/// root is intercepted to switch to the Home tab instead of leaving the app.
@MainActor
final class TVRouter: ObservableObject {
    enum Tab: Hashable, CaseIterable { case home, libraries, favorites, playlists, search, settings }

    @Published private(set) var tab: Tab = .home
    /// Bumped whenever a tab's stack must be discarded. Mutating a bound
    /// NavigationPath does not reliably pop view-destination links, so
    /// TVNavigation rebuilds its NavigationStack on this id to guarantee a
    /// fresh root whenever the tab is (re)opened.
    @Published private var generations: [Tab: Int] = [:]
    // Paths must be publicly settable: NavigationStack writes pushes and pops
    // through its path binding.
    @Published var homePath = NavigationPath()
    @Published var librariesPath = NavigationPath()
    @Published var favoritesPath = NavigationPath()
    @Published var playlistsPath = NavigationPath()
    @Published var searchPath = NavigationPath()

    func generation(for tab: Tab) -> Int { generations[tab, default: 0] }

    /// Open a tab at its root, discarding whatever was pushed there earlier.
    /// TabView re-asserts its selection binding during view updates, so
    /// re-selecting the visible tab is a no-op: publishing during an update
    /// is not allowed, and a redundant reset would needlessly rebuild the
    /// tab's stack (focus churn on tvOS).
    func open(_ tab: Tab) {
        guard tab != self.tab else { return }
        reset(tab)
        self.tab = tab
    }

    /// Land on the Home tab with every navigation stack reset to its root.
    /// Returning to an already-empty Home skips the publish entirely (MENU
    /// echo at the Home root must not churn the stacks).
    func goHome() {
        let allAtRoot = homePath.isEmpty && librariesPath.isEmpty
            && favoritesPath.isEmpty && playlistsPath.isEmpty && searchPath.isEmpty
        guard tab != .home || !allAtRoot else { return }
        for tab in TVRouter.Tab.allCases { reset(tab) }
        tab = .home
    }

    private func reset(_ tab: Tab) {
        generations[tab, default: 0] += 1
        switch tab {
        case .home: homePath = NavigationPath()
        case .libraries: librariesPath = NavigationPath()
        case .favorites: favoritesPath = NavigationPath()
        case .playlists: playlistsPath = NavigationPath()
        case .search: searchPath = NavigationPath()
        case .settings: break
        }
    }
}

struct TVRootView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var router = TVRouter()

    var body: some View {
        Group {
            if auth.isRestoring {
                ProgressView("Connecting to server…")
            } else if auth.user == nil {
                TVLoginView()
            } else {
                TabView(selection: Binding(
                    get: { router.tab },
                    set: { router.open($0) }
                )) {
                    TVNavigation(router: router, tab: .home, path: $router.homePath) { TVHomeView() }
                        .tabItem { Label("Home", systemImage: "house") }
                        .tag(TVRouter.Tab.home)
                    TVNavigation(router: router, tab: .libraries, path: $router.librariesPath) { TVLibrariesView() }
                        .tabItem { Label("Libraries", systemImage: "square.stack") }
                        .tag(TVRouter.Tab.libraries)
                    TVNavigation(router: router, tab: .favorites, path: $router.favoritesPath) {
                        TVMoviesSeriesView(title: "Favorites", source: .favorites)
                    }
                    .tabItem { Label("Favorites", systemImage: "heart") }
                    .tag(TVRouter.Tab.favorites)
                    TVNavigation(router: router, tab: .playlists, path: $router.playlistsPath) { TVPlaylistsView() }
                        .tabItem { Label("Playlists", systemImage: "list.bullet") }
                        .tag(TVRouter.Tab.playlists)
                    TVNavigation(router: router, tab: .search, path: $router.searchPath) { TVSearchView() }
                        .tabItem { Label("Search", systemImage: "magnifyingglass") }
                        .tag(TVRouter.Tab.search)
                    TVSettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(TVRouter.Tab.settings)
                }
                .id(auth.user?.Id)
                .tint(.pink)
                .environmentObject(router)
            }
        }
    }
}

/// Per-tab navigation stack. The menu-press interception is attached only while
/// the stack is at its root, so pushed pages keep the standard pop behavior.
struct TVNavigation<Content: View>: View {
    @ObservedObject var router: TVRouter
    let tab: TVRouter.Tab
    @Binding var path: NavigationPath
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack(path: $path) {
            if path.isEmpty {
                // At the root of a non-Home tab, MENU means "go Home", not
                // "quit Envision". The Home tab keeps the system behavior.
                content()
                    .onExitCommand {
                        if tab != .home { router.goHome() }
                    }
            } else {
                content()
            }
        }
        // Rebuilding the stack guarantees the tab opens at its root; simply
        // emptying the path does not pop view-destination links reliably.
        .id(router.generation(for: tab))
    }
}

struct TVSettingsView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var router: TVRouter
    @State private var signingOut = false
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 32) {
            Text("Envision").font(.largeTitle.bold())
            Text("Signed in as \(auth.user?.Name ?? "")")
            Text(auth.baseURL.absoluteString).foregroundStyle(.secondary)
            Text("Manage servers and libraries from Envision on your Mac, iPad, or iPhone.")
                .foregroundStyle(.secondary)
            Button(signingOut ? "Signing out…" : "Sign out / Change server") { confirm = true }
                .buttonStyle(TVButtonStyle())
                .disabled(signingOut)
        }
        // Settings has no navigation stack, so MENU always goes Home.
        .onExitCommand { router.goHome() }
        .confirmationDialog("Sign out of Envision?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                signingOut = true
                PlaybackEngine.stopActivePlayback()
                Task {
                    await auth.logout()
                    CatalogCache.shared.clear()
                    router.goHome()
                    signingOut = false
                }
            }
        }
    }
}

struct TVErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Label("Unable to load", systemImage: "exclamationmark.triangle")
                .font(.title2)
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Try again", action: retry)
                .buttonStyle(TVButtonStyle())
        }
        .padding(40)
    }
}
