import SwiftUI

/// Port of components/StreamsTable.tsx.
struct StreamsTable: View {
    let title: String
    let streams: [MediaStream]
    let fallback: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption).bold()
                .foregroundStyle(.secondary)
            if streams.isEmpty {
                Text(fallback).font(.callout).foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                    GridRow {
                        Text("Index").font(.caption).bold().foregroundStyle(.secondary)
                        Text("Codec").font(.caption).bold().foregroundStyle(.secondary)
                        Text("Language").font(.caption).bold().foregroundStyle(.secondary)
                        Text("Details").font(.caption).bold().foregroundStyle(.secondary)
                    }
                    Divider()
                    ForEach(Array(streams.enumerated()), id: \.offset) { _, stream in
                        GridRow {
                            Text(stream.Index.map(String.init) ?? "—").foregroundStyle(.secondary)
                            Text(stream.Codec ?? "—")
                            Text(stream.Language ?? "—")
                            Text(details(stream))
                        }
                    }
                }
                .font(.callout)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func details(_ stream: MediaStream) -> String {
        var parts: [String] = []
        if stream.streamType == "Video", let width = stream.Width {
            parts.append("\(width)×\(stream.Height ?? 0)")
        }
        if stream.streamType == "Audio", let channels = stream.Channels {
            parts.append("\(channels) ch")
        }
        if stream.streamType == "Audio", let rate = stream.SampleRate {
            parts.append("\(rate) Hz")
        }
        if stream.IsExternal == true { parts.append("external") }
        return parts.joined(separator: " · ")
    }
}

/// Port of components/EpisodeNavigation.tsx.
struct EpisodeNavigation: View {
    let item: Item
    var playback = false

    @EnvironmentObject private var router: Router
    @EnvironmentObject private var auth: AuthStore
    @State private var adjacent: AdjacentEpisodes?

    var body: some View {
        HStack(spacing: 0) {
            if let previous = adjacent?.PreviousId {
                Button {
                    router.push(playback ? .play(previous) : .item(previous))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PREVIOUS").font(.caption2).foregroundStyle(.secondary)
                        Text("Episode").bold()
                    }
                }
                .buttonStyle(.borderless)
            }
            Spacer()
            if let parentId = item.ParentId {
                Button {
                    router.push(.item(parentId))
                } label: {
                    VStack(spacing: 2) {
                        Text("BROWSE SEASON").font(.caption2).foregroundStyle(.secondary)
                        Text(item.ParentIndexNumber == 0 ? "Specials" : "Season \(item.ParentIndexNumber ?? 0)")
                            .bold().foregroundStyle(.pink)
                    }
                }
                .buttonStyle(.borderless)
            }
            Spacer()
            if let next = adjacent?.NextId {
                Button {
                    router.push(playback ? .play(next) : .item(next))
                } label: {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("NEXT").font(.caption2).foregroundStyle(.secondary)
                        Text("Episode").bold()
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .task(id: item.Id) {
            adjacent = try? await auth.api.adjacentEpisodes(item.Id)
        }
    }
}
