import SwiftUI

/// Port of the ItemCard DetailModal ("Quick details").
struct QuickDetailsSheet: View {
    let item: Item
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ResponsiveStack(spacing: 20) {
            ItemImage(itemId: item.Id, name: item.Name)
                .frame(width: 180, height: 270)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(item.itemType)
                        .font(.caption).bold()
                        .foregroundStyle(.pink)
                        .textCase(.uppercase)
                    Spacer()
                    Button("Done") { dismiss() }
                }
                Text(item.Name).font(.title2).bold()
                Text(item.detailLine).font(.callout).foregroundStyle(.secondary)
                if let genres = item.Genres, !genres.isEmpty {
                    Text(genres.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                }
                ScrollView {
                    Text(item.Overview ?? "No description is available for this title.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button {
                    dismiss()
                    router.push(.item(item.Id))
                } label: {
                    Label("Full details", systemImage: "info.circle")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: 560, minHeight: 300, idealHeight: 340)
    }
}

/// Port of components/ItemGrid.tsx. When `mixed` is set, the grid hosts
/// movie/episode collections: movies (and other titles) use the landscape
/// backdrop layout while episodes keep their thumbnail look.
struct ItemGrid: View {
    let items: [Item]
    var layout: ItemCard.CardLayout = .poster
    var mixed = false
    var emptyMessage = "No items found."
    var onRemove: ((String) -> Void)?

    /// In mixed collections every title is landscape except episodes, whose
    /// episode-still image is preserved.
    private func layoutFor(_ item: Item) -> ItemCard.CardLayout {
        item.itemType == "Episode" ? .episode : .landscape
    }

    /// Episode tiles carry a title plus a two-line overview, so they get a
    /// wider gutter and row gap than plain poster tiles.
    private var isEpisodeLayout: Bool { mixed || layout == .episode }

    var body: some View {
        if items.isEmpty {
            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 140)
                .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        } else {
            LazyVGrid(columns: columns, spacing: isEpisodeLayout ? 34 : 28) {
                ForEach(items) { item in
                    ItemCard(item: item, layout: mixed ? layoutFor(item) : layout, onRemove: onRemove)
                }
            }
        }
    }

    private var columns: [GridItem] {
        if mixed {
            return [GridItem(.adaptive(minimum: 300), spacing: isEpisodeLayout ? 28 : 24)]
        }
        if layout == .episode {
            // Web parity: `grid gap-5 sm:grid-cols-2 xl:grid-cols-3` — episode
            // tiles are wide (2–3 across) instead of the 6-across poster wall,
            // so their title and overview never crowd the neighbouring tile.
            return [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 26, alignment: .top)]
        }
        return [GridItem(.adaptive(minimum: 180), spacing: 24)]
    }
}

/// Port of HomePage MediaRow: a horizontal scroll rail with a title and links.
/// Rails are poster-layout by default; `mixedLandscape` opts the rail into the
/// movie/episode treatment (landscape backdrops for movies, episode stills
/// unchanged) for collections that can contain both, such as Continue
/// Watching and Favorites.
struct MediaRow: View {
    let title: String
    let items: [Item]
    var viewAllRoute: Route?
    var mixedLandscape = false
    var onRemove: ((String) -> Void)?

    @EnvironmentObject private var router: Router

    private func cardLayout(for item: Item) -> ItemCard.CardLayout {
        guard mixedLandscape else { return .poster }
        if item.itemType == "Episode" { return .episode }
        return .landscape
    }

    private func cardWidth(for item: Item) -> CGFloat {
        switch cardLayout(for: item) {
        case .landscape: return 300
        case .episode: return 280
        case .poster: return 180
        }
    }

    /// Episode cards carry a two-line overview, so rails containing them use a
    /// wider gap than plain poster rails.
    private var railSpacing: CGFloat {
        items.contains { cardLayout(for: $0) == .episode } ? 28 : 24
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.title3).bold()
                    Spacer()
                    if let viewAllRoute {
                        Button("View all →") {
                            router.go(viewAllRoute)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: railSpacing) {
                        ForEach(items) { item in
                            ItemCard(item: item, layout: cardLayout(for: item), onRemove: onRemove)
                                .frame(width: cardWidth(for: item))
                        }
                        if let viewAllRoute {
                            Button {
                                router.go(viewAllRoute)
                            } label: {
                                VStack(spacing: 10) {
                                    Image(systemName: "chevron.right")
                                        .font(.title2)
                                    Text("See everything")
                                        .font(.callout).bold()
                                }
                                .frame(width: 180, height: 306)
                                .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
