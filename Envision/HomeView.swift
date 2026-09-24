import SwiftUI

/// Port of pages/HomePage.tsx: resume/favorites/recommended/recent rows + per-library rows.
struct HomeView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var resume: [Item] = []
    @State private var favorites: [Item] = []
    @State private var recommended: [Item] = []
    @State private var recent: [Item] = []
    @State private var rows: [(library: Library, items: [Item])] = []
    @State private var loading = true
    @State private var error: String?

    struct HomeData: Codable {
        var resume: [Item]
        var favorites: [Item]
        var recommended: [Item]
        var recent: [Item]
        var rows: [RowData]
    }
    struct RowData: Codable {
        var library: Library
        var items: [Item]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("What will you watch?")
                    .font(.largeTitle).bold()
                if let error, rows.isEmpty {
                    Text("Could not load home: \(error)")
                        .foregroundStyle(.red)
                        .padding()
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
                if loading {
                    ProgressView("Building your home screen…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    MediaRow(title: "Continue watching", items: resume, viewAllRoute: .resume,
                             mixedLandscape: true) { id in
                        resume.removeAll { $0.Id == id }
                    }
                    MediaRow(title: "Favorites", items: favorites, viewAllRoute: .favorites,
                             mixedLandscape: true)
                    MediaRow(title: "Recommended for you", items: recommended)
                    MediaRow(title: "Recently added", items: recent)
                    ForEach(rows, id: \.library.ItemId) { row in
                        MediaRow(
                            title: row.library.Name,
                            items: row.items,
                            viewAllRoute: .library(row.library.ItemId)
                        )
                    }
                    if rows.isEmpty {
                        Text("No libraries yet. Add one from Administration.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 140)
                            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Home")
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .favoritesChanged)) { _ in
            Task { await refreshFavorites() }
        }
    }

    private func load() async {
        guard let user = auth.user else { return }
        if let cached = CatalogCache.shared.read(HomeData.self, forKey: "home") {
            apply(cached)
            loading = false
        }
        do {
            let libraries = try await auth.api.libraries()
            let resumeResult = try await auth.api.resume(userId: user.Id, limit: 10)
            let favoriteResult = try await auth.api.getItems(ItemQuery(Limit: 10, IsFavorite: true))
            let recommendationGroups = (try? await auth.api.recommendations(userId: user.Id, itemLimit: 10)) ?? []
            let latest = try await auth.api.getItems(ItemQuery(
                Recursive: true,
                Limit: 10,
                IncludeItemTypes: "Movie,Series,Audio,Video",
                SortBy: "DateCreated"))
            let libraryResults = try await withThrowingTaskGroup(of: (Int, ItemList).self) { group -> [ItemList] in
                for (index, library) in libraries.enumerated() {
                    group.addTask {
                        let list = try await auth.api.getItems(ItemQuery(ParentId: library.ItemId, Limit: 10))
                        return (index, list)
                    }
                }
                var indexed: [(Int, ItemList)] = []
                for try await result in group { indexed.append(result) }
                return indexed.sorted { $0.0 < $1.0 }.map(\.1)
            }
            let nextRows = zip(libraries, libraryResults).map { (library: $0.0, items: $0.1.Items) }
            let data = HomeData(
                resume: resumeResult.Items,
                favorites: favoriteResult.Items,
                recommended: recommendationGroups.flatMap(\.Items).prefix(10).map { $0 },
                recent: latest.Items,
                rows: nextRows.map { RowData(library: $0.0, items: $0.1) })
            apply(data)
            CatalogCache.shared.write("home", data)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func apply(_ data: HomeData) {
        resume = data.resume
        favorites = data.favorites
        recommended = data.recommended
        recent = data.recent
        rows = data.rows.map { ($0.library, $0.items) }
    }

    private func refreshFavorites() async {
        if let data = try? await auth.api.getItems(ItemQuery(Limit: 10, IsFavorite: true)) {
            favorites = data.Items
        }
    }
}
