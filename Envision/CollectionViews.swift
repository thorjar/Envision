import SwiftUI

/// Port of pages/SearchPage.tsx.
struct SearchView: View {
    let query: String

    @EnvironmentObject private var auth: AuthStore
    @State private var items: [Item] = []
    @State private var total = 0
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Search results for “\(query)”").font(.largeTitle).bold()
                if let error { Text(error).foregroundStyle(.red) }
                if loading {
                    ProgressView("Searching…").frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    if items.isEmpty {
                        ItemGrid(items: [], emptyMessage: "No matches for “\(query)”.")
                    } else {
                        let titles = items.filter { $0.itemType != "Episode" }
                        let episodes = items.filter { $0.itemType == "Episode" }
                        if !titles.isEmpty {
                            ItemGrid(items: titles)
                        }
                        if !episodes.isEmpty {
                            Text("Episodes").font(.title2.bold())
                            ItemGrid(items: episodes, layout: .episode)
                        }
                    }
                    if total > 0 {
                        Text("\(total) result\(total == 1 ? "" : "s")")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
        .task(id: query) { await load() }
    }

    private func load() async {
        guard !query.isEmpty else {
            items = []; total = 0; loading = false
            return
        }
        loading = true
        error = nil
        do {
            let data = try await auth.api.getItems(ItemQuery(SearchTerm: query, Limit: 200))
            items = data.Items
            total = data.TotalRecordCount
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

/// Port of pages/ResumePage.tsx.
struct ResumeView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var items: [Item] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Continue watching").font(.largeTitle).bold()
                if let error { Text(error).foregroundStyle(.red) }
                if loading {
                    ProgressView("Loading resume list…").frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ItemGrid(items: items, mixed: true,
                             emptyMessage: "Nothing to resume. Start playing something and it will appear here.",
                             onRemove: { id in items.removeAll { $0.Id == id } })
                }
            }
            .padding(24)
        }
        .task { await load() }
    }

    private func load() async {
        guard let user = auth.user else { return }
        loading = true
        do {
            items = try await auth.api.resume(userId: user.Id).Items
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

/// Port of pages/FavoritesPage.tsx.
struct FavoritesView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var items: [Item] = CatalogCache.shared.read([Item].self, forKey: "favorites") ?? []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Favorites").font(.largeTitle).bold()
                if let error {
                    Text("Could not load favorites: \(error)").foregroundStyle(.red)
                }
                if loading {
                    ProgressView("Loading favorites…").frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ItemGrid(items: items, mixed: true,
                             emptyMessage: "Titles you add to favorites will appear here.")
                }
            }
            .padding(24)
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .favoritesChanged)) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        do {
            let data = try await auth.api.getItems(ItemQuery(Limit: 200, IsFavorite: true))
            items = data.Items
            CatalogCache.shared.write("favorites", data.Items)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
