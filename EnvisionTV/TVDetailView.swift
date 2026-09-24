import SwiftUI

struct TVDetailView: View {
    let itemId: String
    @EnvironmentObject private var auth: AuthStore
    @State private var item: Item?
    @State private var children: [Item] = []
    @State private var childrenFetched = false
    @State private var loading = true
    @State private var updating = false
    @State private var error: String?
    @State private var playbackItem: Item?
    @State private var adjacent: AdjacentEpisodes?

    private var seasons: [Item] { TVSeriesOrder.seasons(children) }
    private var episodes: [Item] { TVSeriesOrder.episodes(children) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                if loading { ProgressView("Loading details…").padding(64) }
                if let item {
                    VStack(alignment: .leading, spacing: 40) {
                        HStack(alignment: .top, spacing: 60) {
                            ItemImage(itemId: item.Id, name: item.Name)
                                .frame(width: 340, height: 480).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                            VStack(alignment: .leading, spacing: 24) {
                                Text(item.Name).font(.largeTitle.bold())
                                if let series = item.SeriesName { Text(series + " · " + item.episodeLabel).font(.title2) }
                                Text(item.detailLine).foregroundStyle(.secondary)
                                Text(item.Genres?.joined(separator: " · ") ?? "").foregroundStyle(.secondary)
                                if !item.IsFolder {
                                    HStack(spacing: 28) {
                                        Button(item.UserData?.Played != true && (item.UserData?.PlaybackPositionTicks ?? 0) > 0
                                               ? "Resume \(formatTicks(item.UserData?.PlaybackPositionTicks))" : "Play") {
                                            playbackItem = item
                                        }
                                        Button("From beginning") {
                                            var fresh = item
                                            fresh.UserData = UserData(PlaybackPositionTicks: 0, Played: false,
                                                                      IsFavorite: item.UserData?.IsFavorite ?? false)
                                            playbackItem = fresh
                                        }
                                    }
                                }
                                HStack(spacing: 28) {
                                    Button(item.UserData?.IsFavorite == true ? "Remove favorite" : "Add favorite") {
                                        Task { await update(favorite: true) }
                                    }.disabled(updating)
                                    if !item.IsFolder {
                                        Button(item.UserData?.Played == true ? "Mark unplayed" : "Mark played") {
                                            Task { await update(favorite: false) }
                                        }.disabled(updating)
                                    }
                                }
                            }
                        }
                        if let overview = item.Overview { Text(overview).font(.title3) }
                        HStack(spacing: 32) {
                            if let id = adjacent?.PreviousId {
                                NavigationLink("Previous episode") { TVDetailView(itemId: id) }
                            }
                            if let id = adjacent?.NextId {
                                NavigationLink("Next episode") { TVDetailView(itemId: id) }
                            }
                            if item.itemType == "Episode", let parentId = item.ParentId {
                                NavigationLink {
                                    TVDetailView(itemId: parentId)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("BROWSE SEASON").font(.caption).foregroundStyle(.white.opacity(0.85))
                                        Text(TVSeriesOrder.parentSeasonLabel(item)).bold()
                                    }
                                }
                            }
                        }
                    }
                    .padding(64)
                    // White labels on the pink accent fill for every action
                    // button and navigation link in the header.
                    .buttonStyle(TVButtonStyle())

                    if !seasons.isEmpty { TVMediaRow(title: "Seasons", items: seasons) }
                    if !episodes.isEmpty { TVMediaRow(title: "Episodes", items: episodes, layout: .landscape) }
                    if item.IsFolder, childrenFetched, seasons.isEmpty, episodes.isEmpty {
                        NavigationLink("Browse contents") {
                            TVCatalogView(title: item.Name, source: .library(item.Id))
                        }
                        .padding(.horizontal, 64)
                        .buttonStyle(TVButtonStyle())
                    }
                }
                if let error { TVErrorView(message: error) { Task { await load() } } }
            }
        }
        .task(id: itemId) { await load() }
        .fullScreenCover(item: $playbackItem, onDismiss: { Task { await load() } }) { item in
            TVPlayerView(api: auth.api, item: item)
        }
    }

    private func load() async {
        loading = item == nil
        error = nil
        defer { loading = false }
        do {
            let loaded = try await auth.api.getItem(itemId)
            item = loaded
            children = []
            childrenFetched = false
            if loaded.IsFolder {
                if let list = try? await auth.api.getItems(ItemQuery(ParentId: loaded.Id, Limit: 500, SortBy: "SortName")) {
                    children = list.Items
                }
                childrenFetched = true
            }
            if loaded.itemType == "Episode" { adjacent = try? await auth.api.adjacentEpisodes(loaded.Id) }
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }

    private func update(favorite: Bool) async {
        guard let user = auth.user, let current = item else { return }
        updating = true; error = nil
        defer { updating = false }
        do {
            let data: UserData
            if favorite {
                data = try await auth.api.setFavorite(userId: user.Id, itemId: itemId, !(current.UserData?.IsFavorite ?? false))
            } else {
                data = try await auth.api.setPlayed(userId: user.Id, itemId: itemId, !(current.UserData?.Played ?? false))
            }
            item?.UserData = data
            NotificationCenter.announceFavoritesChanged()
        } catch { self.error = error.localizedDescription }
    }
}
