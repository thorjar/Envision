import Foundation

/// A set of libraries that live on the same server — either this server or a
/// connected remote Jellyfin server. Port of the frontend's
/// `lib/libraryGroups.ts` grouping, shared by the sidebar and the admin panel.
struct LibraryGroup: Identifiable {
    let key: String
    let name: String
    let isLocal: Bool
    let libraries: [Library]

    var id: String { key }
}

enum LibraryGrouping {
    /// Group libraries by their owning server, preserving first-seen order (the
    /// local server first, then connected remotes in backend order).
    static func groups(_ libraries: [Library], localServerName: String) -> [LibraryGroup] {
        var order: [String] = []
        var map: [String: (isLocal: Bool, libs: [Library])] = [:]
        for library in libraries {
            let name = (library.IsRemote ? library.RemoteServerName : nil) ?? localServerName
            if map[name] == nil {
                map[name] = (library.IsRemote != true, [])
                order.append(name)
            }
            map[name]?.libs.append(library)
        }
        return order.map { key in
            let entry = map[key]!
            return LibraryGroup(key: key, name: key, isLocal: entry.isLocal, libraries: entry.libs)
        }
    }
}
