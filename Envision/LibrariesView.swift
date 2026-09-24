import SwiftUI

/// Port of pages/LibrariesPage.tsx: library cards grouped by server.
struct LibrariesView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var router: Router
    @State private var libraries: [Library]? = CatalogCache.shared.read([Library].self, forKey: "libraries")
    @State private var serverName = "This server"
    @State private var error: String?

    private let typeLabels = ["movies": "Movies", "tvshows": "TV Shows", "music": "Music", "homevideos": "Home Videos"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Libraries").font(.largeTitle).bold()
                if let error {
                    Text("Could not load libraries: \(error)").foregroundStyle(.red)
                }
                if let libraries {
                    if libraries.isEmpty {
                        Text("No libraries yet. Ask an administrator to add one in the Admin dashboard.")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 160)
                            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        ForEach(groups, id: \.key) { group in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(group.isLocal ? Color.pink : Color.green)
                                        .frame(width: 9, height: 9)
                                    VStack(alignment: .leading) {
                                        Text(group.name).font(.title3).bold()
                                        Text("\(group.isLocal ? "Local server" : "Connected Jellyfin server") · \(group.libraries.count) \(group.libraries.count == 1 ? "library" : "libraries")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                                    ForEach(group.libraries) { library in
                                        Button {
                                            router.push(.library(library.ItemId))
                                        } label: {
                                            VStack(spacing: 10) {
                                                Image(systemName: icon(library.CollectionType))
                                                    .font(.title2)
                                                    .foregroundStyle(.pink)
                                                Text(library.Name).bold()
                                                Text(typeLabels[library.CollectionType] ?? library.CollectionType)
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            .frame(maxWidth: .infinity, minHeight: 120)
                                            .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ProgressView("Loading libraries…")
                }
            }
            .padding(24)
        }
        .task { await load() }
    }

    private var groups: [(key: String, name: String, isLocal: Bool, libraries: [Library])] {
        guard let libraries else { return [] }
        var order: [String] = []
        var map: [String: (isLocal: Bool, libs: [Library])] = [:]
        for library in libraries {
            let name = (library.IsRemote ? library.RemoteServerName : nil) ?? serverName
            if map[name] == nil { map[name] = (library.IsRemote != true, []); order.append(name) }
            map[name]?.libs.append(library)
        }
        return order.map { (key: $0, name: $0, isLocal: map[$0]!.isLocal, libraries: map[$0]!.libs) }
    }

    private func load() async {
        do {
            let data = try await auth.api.libraries()
            libraries = data
            CatalogCache.shared.write("libraries", data)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        if let info = try? await auth.api.systemInfo() { serverName = info.ServerName }
    }

    private func icon(_ type: String) -> String {
        switch type {
        case "movies": return "film"
        case "tvshows": return "tv"
        case "music": return "music.note"
        default: return "folder"
        }
    }
}
