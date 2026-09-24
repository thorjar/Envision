import SwiftUI

// Header + data actions for ItemDetailView (kept in an extension so the main
// file stays small).
extension ItemDetailView {
    func header(_ item: Item) -> some View {
        ResponsiveStack(spacing: 24) {
            ItemImage(itemId: item.Id, name: item.Name)
                .frame(width: 220, height: 330)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 10) {
                Text(item.itemType).font(.caption).bold().foregroundStyle(.pink).textCase(.uppercase)
                Text(item.Name).font(.largeTitle).bold()
                Text(item.detailLine).font(.callout).foregroundStyle(.secondary)
                if let genres = item.Genres?.filter({ !$0.isEmpty }), !genres.isEmpty {
                    Text(genres.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                }
                ScrollView {
                    Text(item.Overview ?? "No description is available for this title.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: 140)
                if !item.IsFolder, let ticks = item.UserData?.PlaybackPositionTicks, ticks > 0,
                   item.UserData?.Played != true {
                    Text("Resume from \(formatTicks(ticks))")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    if !item.IsFolder {
                        Button {
                            router.push(.play(item.Id))
                        } label: {
                            Label((item.UserData?.PlaybackPositionTicks ?? 0) > 0 && item.UserData?.Played != true ? "Resume" : "Play",
                                  systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button(item.UserData?.IsFavorite == true ? "★ Favorited" : "☆ Favorite") {
                        Task { await toggleFavorite(item) }
                    }
                    if !item.IsFolder {
                        Button(item.UserData?.Played == true ? "Mark unplayed" : "Mark played") {
                            Task { await togglePlayed(item) }
                        }
                    }
                    if auth.isAdmin, ["Movie", "Series", "Season", "Episode"].contains(item.itemType) {
                        Button {
                            Task { await refreshMetadata(item) }
                        } label: {
                            if refreshing { ProgressView().controlSize(.small) } else { Text("↻ Refresh metadata") }
                        }
                        .disabled(refreshing)
                    }
                    if !item.IsFolder, !playlists.isEmpty {
                        Picker("Choose playlist", selection: $selectedPlaylist) {
                            ForEach(playlists) { playlist in
                                Text(playlist.Name).tag(playlist.Id)
                            }
                        }
                        .frame(maxWidth: 200)
                        Button("Add to playlist") { Task { await addToPlaylist(item) } }
                    }
                }
                if let notice {
                    Text(notice).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    func load() async {
        if let cached = CatalogCache.shared.read(Item.self, forKey: "item:\(itemId)") {
            item = cached
        }
        error = nil
        notice = nil
        children = []
        childPage = 0
        do {
            let data = try await auth.api.getItem(itemId)
            item = data
            CatalogCache.shared.write("item:\(itemId)", data)
        } catch {
            self.error = error.localizedDescription
            return
        }
        // Children are fetched here (after the item resolves) — a separate
        // .task(id: childPage) raced the item fetch and left folders showing
        // "No scanned items found".
        Task {
            if let data = try? await auth.api.playlists() {
                playlists = data.Items
                if let first = data.Items.first { selectedPlaylist = first.Id }
            }
        }
        if let item, item.IsFolder {
            await loadChildren(item)
        }
    }

    /// Page the folder's children by ±1 and refetch.
    func changePage(_ delta: Int) {
        let newPage = childPage + delta
        guard newPage >= 0, let item, item.IsFolder else { return }
        childPage = newPage
        Task { await loadChildren(item) }
    }

    func loadChildren(_ parent: Item) async {
        childrenLoading = true
        defer { childrenLoading = false }
        do {
            let data = try await auth.api.getItems(ItemQuery(
                ParentId: parent.Id,
                StartIndex: childPage * 100,
                Limit: 100))
            children = data.Items
            childTotal = data.TotalRecordCount
        } catch {
            children = []
            childTotal = 0
        }
    }

    func toggleFavorite(_ target: Item) async {
        guard let user = auth.user else { return }
        let next = !(target.UserData?.IsFavorite ?? false)
        if let data = try? await auth.api.setFavorite(userId: user.Id, itemId: target.Id, next) {
            item?.UserData = data
            NotificationCenter.announceFavoritesChanged()
        }
    }

    func togglePlayed(_ target: Item) async {
        guard let user = auth.user else { return }
        let next = !(target.UserData?.Played ?? false)
        if let data = try? await auth.api.setPlayed(userId: user.Id, itemId: target.Id, next) {
            item?.UserData = data
        }
    }

    func refreshMetadata(_ target: Item) async {
        refreshing = true
        defer { refreshing = false }
        if let result = try? await auth.api.refreshMetadata(target.Id, name: target.Name, year: target.Year),
           let matched = result["Matched"] {
            notice = matched ? "Metadata refreshed." : "No TMDb match found; existing metadata kept."
        } else {
            notice = "Could not refresh metadata."
        }
    }

    func addToPlaylist(_ target: Item) async {
        guard !selectedPlaylist.isEmpty else { return }
        do {
            try await auth.api.appendPlaylistItems(selectedPlaylist, ids: [target.Id])
            notice = "Added to playlist."
        } catch {
            notice = error.localizedDescription
        }
    }
}
