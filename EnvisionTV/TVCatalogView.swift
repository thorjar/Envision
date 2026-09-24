import SwiftUI

struct TVItemCard: View {
    let item: Item
    var layout: Layout = .poster

    enum Layout { case poster, landscape }

    /// Portrait posters for movies; wide 16:9 backdrops for series and episodes.
    private var size: (width: CGFloat, height: CGFloat) {
        layout == .poster ? (240, 340) : (440, 248)
    }

    private var caption: String {
        item.itemType == "Episode" ? item.episodeLabel : item.subtitleLine
    }

    var body: some View {
        // Explicit destination: value-based links are unreliable inside lazy
        // grids/shelves on tvOS when they depend on a distant registration.
        NavigationLink {
            TVDetailView(itemId: item.Id)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                TVItemArtwork(item: item, width: size.width, height: size.height,
                              style: layout == .landscape ? .backdrop : .poster)
                Text(item.Name).font(.headline).lineLimit(1)
                Text(caption)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: size.width)
            .padding(12)
        }
        .buttonStyle(.card)
        .accessibilityLabel(item.Name)
    }
}

/// Horizontal shelf. `layout` picks portrait posters or landscape backdrops —
/// the Continue Watching carousel and episode shelves use landscape.
struct TVMediaRow: View {
    let title: String
    let items: [Item]
    var layout: TVItemCard.Layout = .poster

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title2.bold()).padding(.horizontal, 64)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 32) {
                        ForEach(items) { TVItemCard(item: $0, layout: layout) }
                    }
                    .padding(.horizontal, 64).padding(.vertical, 28)
                }
            }
        }
    }
}

struct TVCatalogView: View {
    let title: String
    let source: TVCatalogSource
    @EnvironmentObject private var auth: AuthStore
    @State private var items: [Item] = []
    @State private var total = 0
    @State private var offset = 0
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                Text(title).font(.largeTitle.bold())
                if items.isEmpty && !loading && error == nil {
                    ContentUnavailableView("No items", systemImage: "film", description: Text("There is nothing here yet."))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 264), spacing: 40)], spacing: 44) {
                    ForEach(items) { TVItemCard(item: $0) }
                }
                if let error { TVErrorView(message: error) { Task { await load(reset: items.isEmpty) } } }
                if loading { ProgressView("Loading…") }
                if offset < total && !loading && error == nil {
                    Button("Load more") { Task { await load(reset: false) } }
                        .buttonStyle(TVButtonStyle())
                }
            }.padding(64)
        }
        .task(id: source) { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        guard !loading else { return }
        loading = true
        error = nil
        if reset { items = []; offset = 0; total = 0 }
        defer { loading = false }
        do {
            let result: ItemList
            switch source {
            case .playlist(let id):
                result = try await auth.api.playlistItems(id, startIndex: offset, limit: 60)
            case .resume:
                guard let user = auth.user else { return }
                result = try await auth.api.resume(userId: user.Id)
            default:
                var query = ItemQuery(StartIndex: offset, Limit: 60)
                switch source {
                case .library(let id): query.ParentId = id
                case .search(let text): query.SearchTerm = text; query.Recursive = true
                case .favorites: query.IsFavorite = true; query.Recursive = true
                default: break
                }
                result = try await auth.api.getItems(query)
            }
            try Task.checkCancellation()
            var seen = Set(items.map(\.Id))
            items += result.Items.filter { seen.insert($0.Id).inserted }
            offset += result.Items.count
            total = result.Items.isEmpty || source == .resume ? offset : result.TotalRecordCount
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }
}
