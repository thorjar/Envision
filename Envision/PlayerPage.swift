import SwiftUI

/// Port of pages/PlayerPage.tsx.
struct PlayerPage: View {
    let itemId: String

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.macPlaybackFullScreen) private var fullScreen
    @State private var item: Item?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error {
                Text(error).foregroundStyle(.red)
            }
            if let item {
                if item.itemType == "Episode", !fullScreen {
                    EpisodeNavigation(item: item, playback: true)
                }
                if item.IsFolder {
                    Text("Folders cannot be played directly.")
                        .foregroundStyle(.secondary)
                } else {
                    PlayerView(item: item)
                        .id(item.Id)
                }
            } else {
                ProgressView("Loading item…").frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .padding(fullScreen ? 0 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(fullScreen ? Color.black : Color.clear)
        .task(id: itemId) {
            error = nil
            item = try? await auth.api.getItem(itemId)
            if item == nil { error = "Could not load this item." }
        }
    }
}
