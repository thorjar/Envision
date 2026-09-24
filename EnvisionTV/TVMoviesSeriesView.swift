import SwiftUI

/// Favorites and search results, split into two sections: Movies render as
/// portrait posters, and Series/Seasons/Episodes as landscape backdrops.
struct TVMoviesSeriesView: View {
    let title: String
    let source: TVCatalogSource
    @EnvironmentObject private var auth: AuthStore
    @State private var items: [Item] = []
    @State private var loading = true
    @State private var error: String?

    private var movies: [Item] { TVLibrarySections.movies(items) }
    private var series: [Item] { TVLibrarySections.series(items) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                Text(title).font(.largeTitle.bold())
                if loading { ProgressView("Loading…") }
                if let error { TVErrorView(message: error) { Task { await load() } } }
                if !movies.isEmpty {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Movies").font(.title2.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 264), spacing: 40)], spacing: 44) {
                            ForEach(movies) { TVItemCard(item: $0) }
                        }
                    }
                }
                if !series.isEmpty {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Series").font(.title2.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 464), spacing: 40)], spacing: 44) {
                            ForEach(series) { TVItemCard(item: $0, layout: .landscape) }
                        }
                    }
                }
                if !loading && error == nil && items.isEmpty {
                    ContentUnavailableView("No items", systemImage: "film",
                                           description: Text("There is nothing here yet."))
                }
            }
            .padding(64)
        }
        .task(id: source) { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            var query = ItemQuery(Recursive: true, Limit: 300)
            switch source {
            case .search(let text): query.SearchTerm = text
            case .favorites: query.IsFavorite = true
            default: break
            }
            // Restrict to the two sections' types so audio and folder results
            // do not silently vanish between the Movies and Series lists.
            query.IncludeItemTypes = "Movie,Series,Season,Episode"
            let result = try await auth.api.getItems(query)
            var seen = Set<String>()
            items = result.Items.filter { seen.insert($0.Id).inserted }
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}