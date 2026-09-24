import SwiftUI
import Foundation

// MARK: - Formatting (port of lib/format.ts)

func formatTicks(_ ticks: Int64?) -> String {
    formatSeconds(Double(ticksToSeconds(ticks)))
}

func formatSeconds(_ totalSeconds: Double) -> String {
    guard totalSeconds.isFinite, totalSeconds >= 0 else { return "0:00" }
    let total = Int(totalSeconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
        : String(format: "%d:%02d", minutes, seconds)
}

func formatBytes(_ bytes: Int64?) -> String {
    guard let bytes, bytes > 0 else { return "" }
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

func formatMediaType(_ type: String?) -> String {
    switch type {
    case "Movie": return "Movie"
    case "Episode": return "Episode"
    case "Audio": return "Music"
    case "Video": return "Home Video"
    default: return type ?? "Unknown"
    }
}

// MARK: - Stale-while-refresh catalog cache (port of lib/catalogCache.ts)

/// Session-scoped cache that mirrors the browser's sessionStorage catalog cache.
final class CatalogCache {
    static let shared = CatalogCache()
    private var storage: [String: Data] = [:]

    func read<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = storage[key] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func write<T: Encodable>(_ key: String, _ value: T) {
        storage[key] = try? JSONEncoder().encode(value)
    }

    func clear() { storage.removeAll() }
}

// MARK: - Route model (React Router equivalent)

enum Route: Hashable {
    case home
    case libraries
    case resume
    case favorites
    case playlists
    case admin
    case library(String)
    case item(String)
    case play(String)
    case playlist(String)
    case search(String)
}

// MARK: - Cross-view change notifications (lib/favoriteEvents.ts / libraryEvents.ts)

extension Notification.Name {
    static let favoritesChanged = Notification.Name("favoritesChanged")
    static let librariesChanged = Notification.Name("librariesChanged")
}

extension NotificationCenter {
    static func announceFavoritesChanged() {
        NotificationCenter.default.post(name: .favoritesChanged, object: nil)
    }

    static func announceLibrariesChanged() {
        NotificationCenter.default.post(name: .librariesChanged, object: nil)
    }
}

extension Item {
    /// Poster/backdrop-free summary line used by cards and grids.
    var subtitleLine: String {
        if IsFolder {
            let count = ChildCount ?? 0
            return "\(count) \(itemType == "Series" ? "seasons" : "episodes")"
        }
        var parts = [itemType]
        if let Year { parts.append(String(Year)) }
        return parts.joined(separator: " · ")
    }

    var detailLine: String {
        var parts: [String] = []
        if let Year { parts.append(String(Year)) }
        if let rating = CommunityRating { parts.append(String(format: "★ %.1f", rating)) }
        let runtime = formatTicks(RunTimeTicks)
        if !runtime.isEmpty { parts.append(runtime) }
        return parts.joined(separator: " · ")
    }

    var episodeLabel: String {
        var parts: [String] = []
        if let ParentIndexNumber { parts.append(String(format: "S%02d", ParentIndexNumber)) }
        if let IndexNumber { parts.append(String(format: "E%02d", IndexNumber)) }
        return parts.joined(separator: " · ")
    }
}
