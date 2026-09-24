import SwiftUI

/// Port of pages/ItemDetailPage.tsx.
struct ItemDetailView: View {
    let itemId: String

    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var router: Router
    @State var item: Item?
    @State var playlists: [Playlist] = []
    @State var selectedPlaylist = ""
    @State var notice: String?
    @State var error: String?
    @State var refreshing = false
    @State var children: [Item] = []
    @State var childTotal = 0
    @State var childPage = 0
    @State var childrenLoading = false

    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else if let item {
                        header(item)
                        if item.IsFolder {
                            childrenSection(item)
                        } else {
                            streamsSection(item)
                        }
                    } else {
                        ProgressView("Loading item…").frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .padding(24)
            }
            .task(id: itemId) { await load() }
        }

    private func childrenSection(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(item.itemType == "Series" ? "Seasons" : "Episodes").font(.title3).bold()
            if childrenLoading {
                ProgressView("Loading…").frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ItemGrid(items: children, layout: item.itemType == "Season" ? .episode : .poster,
                         emptyMessage: "No scanned items found.")
            }
            if childTotal > 100 {
                HStack {
                    Button("Previous") { changePage(-1) }.disabled(childPage == 0)
                    Text("Page \(childPage + 1) of \((childTotal + 99) / 100)")
                    Button("Next") { changePage(1) }.disabled((childPage + 1) * 100 >= childTotal)
                }
            }
        }
    }

    private func streamsSection(_ item: Item) -> some View {
        let streams = item.MediaStreams ?? []
        return VStack(alignment: .leading, spacing: 16) {
            StreamsTable(title: "Video streams", streams: streams.filter { $0.streamType == "Video" },
                         fallback: "No video stream metadata.")
            StreamsTable(title: "Audio streams", streams: streams.filter { $0.streamType == "Audio" },
                         fallback: "No audio stream metadata.")
            StreamsTable(title: "Subtitles", streams: streams.filter { $0.streamType == "Subtitle" },
                         fallback: "No subtitle streams.")
        }
    }
}
