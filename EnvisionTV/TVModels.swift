import Foundation

enum TVServerAddress {
    static func parse(_ text: String) -> URL? {
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        return parts.url
    }
}

enum TVCatalogSource: Hashable {
    case library(String), playlist(String), search(String), favorites, resume
}

/// Client-side ordering and labels for series → seasons → episodes navigation.
/// Pure Foundation so the harness in Tests/TVCore can exercise it headlessly.
enum TVSeriesOrder {
    /// Seasons sorted by index; specials (index 0) and unnumbered folders last.
    static func seasons(_ items: [Item]) -> [Item] {
        items.filter { $0.itemType == "Season" }.sorted { a, b in
            let (left, right) = (position(a.IndexNumber), position(b.IndexNumber))
            return left == right ? a.Name < b.Name : left < right
        }
    }

    /// Episodes sorted by season, then episode number; specials and episodes
    /// with unknown numbers sort last.
    static func episodes(_ items: [Item]) -> [Item] {
        items.filter { $0.itemType == "Episode" }.sorted { a, b in
            let left = (position(a.ParentIndexNumber), position(a.IndexNumber), a.Name)
            let right = (position(b.ParentIndexNumber), position(b.IndexNumber), b.Name)
            return left < right
        }
    }

    /// "Season 2" / "Specials" display title for a season item.
    static func seasonLabel(_ season: Item) -> String {
        guard let index = season.IndexNumber, index > 0 else { return "Specials" }
        return "Season \(index)"
    }

    /// Label for the season an episode belongs to.
    static func parentSeasonLabel(_ episode: Item) -> String {
        guard let index = episode.ParentIndexNumber, index > 0 else { return "Specials" }
        return "Season \(index)"
    }

    /// Specials (0) and missing numbers sort after every real number.
    private static func position(_ number: Int?) -> Int {
        guard let number, number > 0 else { return Int.max }
        return number
    }
}

/// Splits favorites/search results into the two display sections: Movies stay
/// portrait posters, while Series (with their seasons and episodes) become
/// landscape backdrops. Anything else (e.g. music) lands in neither section.
enum TVLibrarySections {
    static func movies(_ items: [Item]) -> [Item] {
        items.filter { $0.itemType == "Movie" }
    }

    static func series(_ items: [Item]) -> [Item] {
        items.filter { ["Series", "Season", "Episode"].contains($0.itemType) }
    }
}
