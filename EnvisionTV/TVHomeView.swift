import SwiftUI

struct TVHomeView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var resume: [Item] = []
    @State private var recent: [Item] = []
    @State private var favorites: [Item] = []
    @State private var recommended: [Item] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Envision").font(.largeTitle.bold())
                    Text("What will you watch?").font(.title2).foregroundStyle(.secondary)
                    NavigationLink("Continue watching") {
                        TVCatalogView(title: "Continue watching", source: .resume)
                    }
                    .buttonStyle(TVButtonStyle())
                }.padding(64)
                if loading { ProgressView("Loading your library…").padding(64) }
                if let error { TVErrorView(message: error) { Task { await load() } } }
                TVMediaRow(title: "Continue watching", items: resume, layout: .landscape)
                TVMediaRow(title: "Recently added", items: recent)
                TVMediaRow(title: "Favorites", items: favorites, layout: .landscape)
                TVMediaRow(title: "Recommended for you", items: recommended)
                if !loading && error == nil && recent.isEmpty && resume.isEmpty && favorites.isEmpty {
                    ContentUnavailableView("Your library awaits", systemImage: "film",
                                           description: Text("Add media using Envision on your Mac, iPad, or iPhone."))
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let user = auth.user else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            resume = try await auth.api.resume(userId: user.Id, limit: 12).Items
            recent = try await auth.api.getItems(ItemQuery(Recursive: true, Limit: 20,
                IncludeItemTypes: "Movie,Series,Audio,Video", SortBy: "DateCreated")).Items
            favorites = try await auth.api.getItems(ItemQuery(Limit: 12, IsFavorite: true)).Items
            let groups = (try? await auth.api.recommendations(userId: user.Id, itemLimit: 12)) ?? []
            var seen = Set<String>()
            recommended = groups.flatMap(\.Items).filter { seen.insert($0.Id).inserted }
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }
}

struct TVLibrariesView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var libraries: [Library] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            if loading { ProgressView("Loading libraries…") }
            if let error { TVErrorView(message: error) { Task { await load() } } }
            ForEach(libraries) { library in
                NavigationLink {
                    TVCatalogView(title: library.Name, source: .library(library.ItemId))
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(library.Name, systemImage: "square.stack.fill").font(.title2)
                        Text(library.RemoteServerName ?? library.CollectionType).foregroundStyle(.secondary)
                    }.padding(12)
                }
            }
            if !loading && error == nil && libraries.isEmpty { Text("No libraries. Add one from another Envision app.") }
        }
        .navigationTitle("Libraries")
        .task { await load() }
    }

    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { libraries = try await auth.api.libraries() }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct TVPlaylistsView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var playlists: [Playlist] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            if loading { ProgressView("Loading playlists…") }
            if let error { TVErrorView(message: error) { Task { await load() } } }
            ForEach(playlists) { playlist in
                NavigationLink {
                    TVCatalogView(title: playlist.Name, source: .playlist(playlist.Id))
                } label: {
                    Label("\(playlist.Name) · \(playlist.ChildCount) items", systemImage: "list.bullet.rectangle")
                }
            }
            if !loading && error == nil && playlists.isEmpty { Text("No playlists yet.") }
        }
        .navigationTitle("Playlists")
        .task { await load() }
    }

    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { playlists = try await auth.api.playlists().Items }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct TVSearchView: View {
    @State private var text = ""
    @State private var query = ""

    var body: some View {
        VStack {
            HStack(spacing: 24) {
                TextField("Search movies, series, music…", text: $text)
                    .onSubmit { submit() }
                Button("Search", action: submit)
            }.padding(.horizontal, 64).padding(.top, 32)
            if query.isEmpty {
                ContentUnavailableView("Search your library", systemImage: "magnifyingglass")
            } else {
                TVMoviesSeriesView(title: "Results for \(query)", source: .search(query)).id(query)
            }
        }
    }

    private func submit() { query = text.trimmingCharacters(in: .whitespacesAndNewlines) }
}
