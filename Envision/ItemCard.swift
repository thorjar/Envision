import SwiftUI

/// Port of components/ItemCard.tsx (poster layout + context menu actions).
struct ItemCard: View {
    let item: Item
    var layout: CardLayout = .poster
    var onRemove: ((String) -> Void)?

    enum CardLayout { case poster, episode, landscape }

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var router: Router
    @State private var current: Item
    @State private var error: String?
    @State private var showDetails = false

    init(item: Item, layout: CardLayout = .poster, onRemove: ((String) -> Void)? = nil) {
        self.item = item
        self.layout = layout
        self.onRemove = onRemove
        _current = State(initialValue: item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                router.push(.item(current.Id))
            } label: {
                ZStack(alignment: .topTrailing) {
                    GeometryReader { geometry in
                        ItemImage(itemId: current.Id, name: current.Name,
                                  style: layout == .landscape ? .backdrop : .poster)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                    .frame(height: imageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .bottom) { progressBadge }
                    if current.UserData?.Played == true {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.pink)
                            .padding(6)
                    }
                }
            }
            .buttonStyle(.plain)
            .contextMenu { menuItems }

            VStack(alignment: .leading, spacing: 3) {
                Text(current.Name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .help(current.Name)
                Text(current.subtitleLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if layout == .episode {
                    // Web parity: `min-h-10` reserves two lines of overview so
                    // adjacent episode tiles stay visually separated.
                    Text(current.Overview ?? current.episodeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(minHeight: 34, alignment: .top)
                        .padding(.bottom, 6)
                }
            }
        }
        .sheet(isPresented: $showDetails) { QuickDetailsSheet(item: current) }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { _ in error = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private var imageHeight: CGFloat {
        switch layout {
        case .poster: return 270
        case .landscape: return 170
        case .episode: return 150
        }
    }

    @ViewBuilder
    private var progressBadge: some View {
        if let ticks = current.UserData?.PlaybackPositionTicks, ticks > 0,
           let runtime = current.RunTimeTicks, runtime > 0 {
            GeometryReader { proxy in
                VStack {
                    Spacer()
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.3)).frame(height: 4)
                        Capsule().fill(.pink)
                            .frame(width: proxy.size.width * CGFloat(ticks) / CGFloat(runtime), height: 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        if !current.IsFolder {
            Button(current.UserData?.Played == true ? "Mark as unplayed" : "Mark as played") {
                Task { await togglePlayed() }
            }
        }
        Button(current.UserData?.IsFavorite == true ? "Remove from favorites" : "Add to favorites") {
            Task { await toggleFavorite() }
        }
        if !current.IsFolder, let ticks = current.UserData?.PlaybackPositionTicks, ticks > 0,
           current.UserData?.Played != true {
            Button("Remove from Continue Watching") {
                Task { await removeResume() }
            }
        }
        Button("Quick details") { showDetails = true }
    }

    private func togglePlayed() async {
        guard let user = auth.user else { return }
        let target = !(current.UserData?.Played ?? false)
        if let data = try? await auth.api.setPlayed(userId: user.Id, itemId: current.Id, target) {
            current.UserData = data
            NotificationCenter.announceFavoritesChanged()
        }
    }

    private func toggleFavorite() async {
        guard let user = auth.user else { return }
        let target = !(current.UserData?.IsFavorite ?? false)
        if let data = try? await auth.api.setFavorite(userId: user.Id, itemId: current.Id, target) {
            current.UserData = data
            NotificationCenter.announceFavoritesChanged()
        }
    }

    private func removeResume() async {
        guard let user = auth.user else { return }
        var cleared = current.UserData ?? UserData(PlaybackPositionTicks: 0, Played: false, IsFavorite: false)
        cleared.PlaybackPositionTicks = 0
        _ = try? await auth.api.setPlayed(userId: user.Id, itemId: current.Id, false)
        current.UserData = cleared
        onRemove?(current.Id)
    }
}
