import Foundation

// MARK: - Ticks (Jellyfin convention: 1 tick = 100 ns)

public let TICKS_PER_SECOND: Int64 = 10_000_000

func ticksToSeconds(_ ticks: Int64?) -> Int {
    guard let ticks, ticks > 0 else { return 0 }
    return Int(ticks / TICKS_PER_SECOND)
}

// MARK: - Models (PascalCase mirrors of the backend JSON)

struct User: Codable, Hashable {
    struct Policy: Codable, Hashable { var IsAdministrator: Bool }
    var Id: String
    var Name: String
    var Policy: Policy?
}

struct LoginResponse: Codable {
    var User: User
    var AccessToken: String
    var ServerId: String?
}

/// A code the server generated for a device that cannot type credentials.
struct PairingInitiation: Codable {
    var Code: String
    var ExpiresIn: Int
}

/// Poll result for a pairing code. `AccessToken` is present exactly once, when
/// a signed-in user has approved the code and the device claims it.
struct PairingStatus: Codable {
    var Authenticated: Bool
    var User: User?
    var AccessToken: String?
    var ServerId: String?
}

struct SystemInfo: Codable {
    var ServerName: String
    var Id: String
    var Version: String?
    var ProductName: String?
    var StartupWizardCompleted: Bool?
}

struct Library: Codable, Hashable, Identifiable {
    var ItemId: String
    var Name: String
    var CollectionType: String
    var Locations: [String]?
    var IsRemote: Bool
    var RemoteServerName: String?
    var IsObjectStore: Bool?

    var id: String { ItemId }
}

struct MediaStream: Codable, Hashable {
    var Index: Int?
    var streamType: String?
    var Codec: String?
    var Width: Int?
    var Height: Int?
    var Channels: Int?
    var SampleRate: Int?
    var Language: String?
    var Title: String?
    var DisplayTitle: String?
    var IsDefault: Bool?
    var IsForced: Bool?
    var IsExternal: Bool?
    var DeliveryMethod: String?
    var DeliveryUrl: String?

    enum CodingKeys: String, CodingKey {
        case Index, streamType = "Type", Codec, Width, Height, Channels, SampleRate
        case Language, Title, DisplayTitle, IsDefault, IsForced, IsExternal
        case DeliveryMethod, DeliveryUrl
    }
}

struct UserData: Codable, Hashable {
    var PlaybackPositionTicks: Int64
    var Played: Bool
    var IsFavorite: Bool
}

struct Item: Codable, Hashable, Identifiable {
    var Id: String
    var IsRemote: Bool?
    var Name: String
    var itemType: String
    var MediaType: String?
    var IsFolder: Bool
    var ParentId: String?
    var LibraryId: String?
    var IndexNumber: Int?
    var ParentIndexNumber: Int?
    var ChildCount: Int?
    var SeriesId: String?
    var SeriesName: String?
    var SeriesTmdbId: String?
    var Container: String?
    var Size: Int64?
    var RunTimeTicks: Int64?
    var MediaStreams: [MediaStream]?
    var UserData: UserData?
    var TmdbId: String?
    var Year: Int?
    var Overview: String?
    var Genres: [String]?
    var CommunityRating: Double?

    enum CodingKeys: String, CodingKey {
        case Id, IsRemote, Name, itemType = "Type", MediaType, IsFolder, ParentId
        case LibraryId, IndexNumber, ParentIndexNumber, ChildCount, SeriesId
        case SeriesName, SeriesTmdbId, Container, Size, RunTimeTicks, MediaStreams
        case UserData, TmdbId, Year, Overview, Genres, CommunityRating
    }
}

struct ItemList: Codable {
    var Items: [Item]
    var TotalRecordCount: Int
    var StartIndex: Int
}

struct MediaSource: Codable {
    var Id: String
    var protocolName: String?
    var sourceType: String?
    var Container: String?
    var Size: Int64?
    var RunTimeTicks: Int64?
    var MediaStreams: [MediaStream]
    var SupportsDirectPlay: Bool
    var SupportsDirectStream: Bool
    var SupportsTranscoding: Bool
    var DirectStreamUrl: String
    var TranscodingUrl: String?
    var FallbackTranscodingUrl: String?
    var AudioTranscodingUrl: String?
    var AudioTrackUrls: [String: String]?
    var AudioTranscodingMode: String?
    var TranscodingMode: String?

    enum CodingKeys: String, CodingKey {
        case Id, protocolName = "Protocol", sourceType = "Type", Container, Size
        case RunTimeTicks, MediaStreams, SupportsDirectPlay, SupportsDirectStream
        case SupportsTranscoding, DirectStreamUrl, TranscodingUrl, FallbackTranscodingUrl
        case AudioTranscodingUrl, AudioTrackUrls, AudioTranscodingMode, TranscodingMode
    }
}

struct PlaybackInfo: Codable {
    var PlaySessionId: String?
    var MediaSources: [MediaSource]
}

struct Recommendation: Codable {
    var BaselineItemName: String?
    var CategoryId: String?
    var RecommendationType: String?
    var Items: [Item]
}

struct Playlist: Codable, Hashable, Identifiable {
    var Id: String
    var Name: String
    var playlistType: String?
    var ChildCount: Int

    var id: String { Id }

    enum CodingKeys: String, CodingKey {
        case Id, Name, playlistType = "Type", ChildCount
    }
}

struct PlaylistList: Codable {
    var Items: [Playlist]
    var TotalRecordCount: Int
}

struct AdjacentEpisodes: Codable {
    var PreviousId: String?
    var NextId: String?
}

struct ScanStatus: Codable, Identifiable {
    var Id: String
    var State: String
    var Scanned: Int?
    var Removed: Int?
    var ProbeFailures: Int?
    var MetadataFailures: Int?
    var MetadataProvider: String?
    var Errors: [String]?

    var id: String { Id }
}

extension Item {
    var id: String { Id }
}

struct SubtitleSearchResult: Codable, Hashable, Identifiable {
    var FileId: Int
    var FileName: String
    var Language: String
    var DownloadCount: Int
    var HearingImpaired: Bool

    var id: Int { FileId }
}

struct RemoteServer: Codable, Identifiable {
    var Id: String
    var Name: String
    var Url: String
    var ServerId: String
    var LastSync: Int?
    var LastError: String?

    var id: String { Id }
}

struct ObjectStoreConnection: Codable, Identifiable {
    var Id: String
    var Name: String
    var Endpoint: String?
    var Region: String
    var Bucket: String
    var Prefix: String
    var LibraryId: String

    var id: String { Id }
}

struct DirectoryChild: Codable, Hashable {
    var Name: String
    var Path: String
}

struct DirectoryListing: Codable {
    var Path: String?
    var Parent: String?
    var Directories: [DirectoryChild]
}

// MARK: - Item query

struct ItemQuery {
    var ParentId: String?
    var Recursive: Bool?
    var SearchTerm: String?
    var StartIndex: Int?
    var Limit: Int?
    var IncludeItemTypes: String?
    var IsFavorite: Bool?
    var IsPlayed: Bool?
    var SortBy: String?

    /// The module defaults to `MainActor` isolation, which makes the implicit
    /// memberwise init actor-isolated — and default arguments are evaluated in a
    /// nonisolated context, so give the query an explicitly nonisolated init.
    nonisolated init() {}

    nonisolated init(
        ParentId: String? = nil,
        Recursive: Bool? = nil,
        SearchTerm: String? = nil,
        StartIndex: Int? = nil,
        Limit: Int? = nil,
        IncludeItemTypes: String? = nil,
        IsFavorite: Bool? = nil,
        IsPlayed: Bool? = nil,
        SortBy: String? = nil
    ) {
        self.ParentId = ParentId
        self.Recursive = Recursive
        self.SearchTerm = SearchTerm
        self.StartIndex = StartIndex
        self.Limit = Limit
        self.IncludeItemTypes = IncludeItemTypes
        self.IsFavorite = IsFavorite
        self.IsPlayed = IsPlayed
        self.SortBy = SortBy
    }
}

// MARK: - API errors

enum APIError: LocalizedError {
    case failed(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .failed(_, let message): return message
        case .invalidResponse: return "Invalid server response."
        }
    }
}
