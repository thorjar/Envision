import SwiftUI

/// Port of components/Sidebar.tsx: primary nav, per-server library groups, admin + logout.
struct SidebarView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var router: Router
    @State private var libraries: [Library] = CatalogCache.shared.read([Library].self, forKey: "libraries") ?? []
    @State private var serverName = "This server"
    @State private var showPairing = false

    var body: some View {
        List(selection: Binding(
            get: { router.selection },
            set: { router.go($0 ?? .home) }
        )) {
            Section {
                Label("Home", systemImage: "house").tag(Route.home)
                Label("Libraries", systemImage: "folder").tag(Route.libraries)
                Label("Resume", systemImage: "play.fill").tag(Route.resume)
                Label("Favorites", systemImage: "star").tag(Route.favorites)
                Label("Playlists", systemImage: "list.bullet").tag(Route.playlists)
            }
            ForEach(groups, id: \.key) { group in
                Section {
                    ForEach(group.libraries) { library in
                        Label(library.Name, systemImage: libraryIcon(library.CollectionType))
                            .tag(Route.library(library.ItemId))
                    }
                } header: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(group.isLocal ? Color.pink : Color.green)
                            .frame(width: 6, height: 6)
                        Text(group.name).lineLimit(1)
                    }
                }
            }
            if auth.isAdmin {
                Section("Administration") {
                    Label("Dashboard", systemImage: "shield")
                        .tag(Route.admin)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(auth.user?.Name ?? "…")
                    .font(.callout).bold()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(auth.isAdmin ? "Administrator" : "User")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    showPairing = true
                } label: {
                    Label("Pair Apple TV", systemImage: "qrcode")
                        .font(.callout.bold())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Button {
                    Task {
                        await auth.logout()
                        router.go(.home)
                    }
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.callout.bold())
                        .foregroundStyle(Color(red: 1, green: 0.23, blue: 0.19))
                }
                .buttonStyle(.plain)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.65))
        }
        .task {
            await refresh()
        }
        .sheet(isPresented: $showPairing) { PairTVView() }
        .onReceive(NotificationCenter.default.publisher(for: .librariesChanged)) { _ in
            Task { await refresh() }
        }
    }

    /// Per-server groupings (shared with the admin panel via `LibraryGrouping`).
    private var groups: [LibraryGroup] {
        LibraryGrouping.groups(libraries, localServerName: serverName)
    }

    private func refresh() async {
        if let info = try? await auth.api.systemInfo() {
            serverName = info.ServerName
        }
        if let libs = try? await auth.api.libraries() {
            libraries = libs
            CatalogCache.shared.write("libraries", libs)
        }
    }

    private func libraryIcon(_ type: String) -> String {
        switch type {
        case "movies": return "film"
        case "tvshows": return "tv"
        case "music": return "music.note"
        default: return "folder"
        }
    }
}
