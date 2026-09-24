import SwiftUI

/// Port of pages/PlaylistsPage.tsx.
struct PlaylistsView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var router: Router
    @State private var playlists: [Playlist] = []
    @State private var name = ""
    @State private var loading = true
    @State private var error: String?
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Playlists").font(.largeTitle).bold()
                HStack {
                    TextField("New playlist name…", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                    Button("Create") { Task { await create() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let notice {
                    Text(notice).font(.callout).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
                if loading {
                    ProgressView("Loading playlists…").frame(maxWidth: .infinity, minHeight: 200)
                } else if playlists.isEmpty {
                    Text("No playlists yet. Create one above.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 140)
                        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(spacing: 0) {
                        ForEach(playlists) { playlist in
                            HStack {
                                Button {
                                    router.push(.playlist(playlist.Id))
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.Name).bold()
                                        Text("\(playlist.ChildCount) item\(playlist.ChildCount == 1 ? "" : "s")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Button("Delete", role: .destructive) {
                                    Task { await remove(playlist) }
                                }
                            }
                            .padding(.vertical, 10)
                            Divider()
                        }
                    }
                }
            }
            .padding(24)
        }
        .task { await load() }
    }

    private func load() async {
        do {
            playlists = try await auth.api.playlists().Items
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func create() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        notice = nil
        do {
            _ = try await auth.api.createPlaylist(name: trimmed, ids: [])
            name = ""
            await load()
            notice = "Playlist created."
        } catch {
            notice = error.localizedDescription
        }
    }

    private func remove(_ playlist: Playlist) async {
        do {
            try await auth.api.deletePlaylist(playlist.Id)
            await load()
        } catch {
            notice = error.localizedDescription
        }
    }
}

/// Port of pages/PlaylistDetailPage.tsx.
struct PlaylistDetailView: View {
    let playlistId: String

    @EnvironmentObject private var auth: AuthStore
    @State private var items: [Item] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Playlist").font(.largeTitle).bold()
                if let error { Text(error).foregroundStyle(.red) }
                if loading {
                    ProgressView("Loading playlist…").frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ItemGrid(items: items, emptyMessage: "This playlist is empty.")
                }
            }
            .padding(24)
        }
        .task(id: playlistId) { await load() }
    }

    private func load() async {
        loading = true
        do {
            items = try await auth.api.playlistItems(playlistId).Items
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
