import Foundation

/// Swift port of the jellymax frontend's `api/client.ts`.
final class JellymaxAPI {
    /// Base URL of the jellymax backend, e.g. "http://127.0.0.1:8097".
    let baseURL: URL
    /// Token storage shared with the auth store.
    let tokenProvider: () -> String?
    private let session: URLSession

    init(baseURL: URL, tokenProvider: @escaping () -> String?, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    /// Encode a JSON body from a heterogeneous dictionary.
    static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }

    /// Resolve a relative backend URL (e.g. a DirectStreamUrl) against the base.
    func resolveURL(_ path: String) -> URL? {
        if let url = URL(string: path), url.scheme == "http" || url.scheme == "https" {
            return url
        }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    @discardableResult
    func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        let data = try await rawRequest(path, method: method, body: body)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func requestEmpty(_ path: String, method: String = "GET", body: Data? = nil) async throws {
        _ = try await rawRequest(path, method: method, body: body)
    }

    /// Fetch a text resource (subtitle VTT/SRT content) with authentication.
    func fetchText(_ path: String) async throws -> String {
        let data = try await rawRequest(path, method: "GET", body: nil)
        return String(decoding: data, as: UTF8.self)
    }

    private func rawRequest(_ path: String, method: String, body: Data?) async throws -> Data {
        guard let url = resolveURL(path) else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token = tokenProvider() {
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            var message = "Request failed (\(http.statusCode))"
            if let decoded = try? JSONDecoder().decode([String: String].self, from: data),
               let errorText = decoded["Error"] {
                message = errorText
            }
            throw APIError.failed(http.statusCode, message)
        }
        return data
    }

    // MARK: Public

    func systemInfo() async throws -> SystemInfo {
        try await request("/System/Info/Public")
    }

    func setupAdmin(name: String, password: String) async throws -> User {
        try await request("/System/Setup", method: "POST", body: Self.json(["Name": name, "Password": password]))
    }

    // MARK: Authentication

    func login(username: String, password: String) async throws -> LoginResponse {
        try await request("/Users/AuthenticateByName", method: "POST", body: Self.json(["Username": username, "Pw": password]))
    }

    func logout() async throws {
        try await requestEmpty("/Sessions/Logout", method: "POST")
    }

    func me() async throws -> User {
        try await request("/Users/Me")
    }

    // MARK: Device pairing

    /// Ask the server for a short code a signed-in client can approve. Used by
    /// devices where typing a password is painful (Apple TV).
    func initiatePairing(deviceName: String) async throws -> PairingInitiation {
        try await request("/QuickConnect/Initiate", method: "POST",
                          body: Self.json(["DeviceName": deviceName]))
    }

    /// Poll a pair code. `Authenticated` stays false until a user approves it;
    /// the first poll after approval returns the session and consumes the code.
    func pairingStatus(code: String) async throws -> PairingStatus {
        var components = URLComponents(string: "/QuickConnect/Connect")!
        components.queryItems = [URLQueryItem(name: "Code", value: code)]
        return try await request(components.string!)
    }

    /// Approve a code shown by another device, which then signs in as this user.
    func approvePairing(code: String) async throws {
        try await requestEmpty("/QuickConnect/Approve", method: "POST",
                               body: Self.json(["Code": code]))
    }

    // MARK: Admin users

    func users() async throws -> [User] {
        try await request("/Users/")
    }

    func createUser(name: String, password: String, isAdministrator: Bool) async throws -> User {
        try await request("/Users/New", method: "POST",
                          body: Self.json(["Name": name, "Password": password, "IsAdministrator": isAdministrator]))
    }

    // MARK: Libraries

    func libraries() async throws -> [Library] {
        try await request("/Library/VirtualFolders")
    }

    func createLibrary(name: String, collectionType: String, location: String) async throws -> [String: String] {
        try await request("/Library/VirtualFolders", method: "POST",
                          body: Self.json(["Name": name, "CollectionType": collectionType, "Locations": [location]]))
    }

    func deleteLibrary(_ id: String) async throws {
        try await requestEmpty("/Library/VirtualFolders/\(id)", method: "DELETE")
    }

    func listDirectories(path: String? = nil) async throws -> DirectoryListing {
        var components = URLComponents(string: "/Library/Paths")!
        if let path { components.queryItems = [URLQueryItem(name: "Path", value: path)] }
        return try await request(components.string!)
    }

    func refreshLibrary() async throws -> [String: String] {
        try await request("/Library/Refresh", method: "POST", body: Self.json([:]))
    }

    func scanStatus() async throws -> [ScanStatus] {
        try await request("/ScheduledTasks")
    }

    // MARK: Metadata

    func refreshMetadata(_ id: String, name: String? = nil, year: Int? = nil) async throws -> [String: Bool] {
        var payload: [String: Any] = [:]
        if let name { payload["Name"] = name }
        if let year { payload["Year"] = year }
        return try await request("/Items/\(id)/Metadata/Refresh", method: "POST", body: Self.json(payload))
    }

    // MARK: Items

    func getItems(_ query: ItemQuery = ItemQuery()) async throws -> ItemList {
        var components = URLComponents(string: "/Items")!
        var params: [URLQueryItem] = []
        if let v = query.ParentId { params.append(.init(name: "ParentId", value: v)) }
        if let v = query.Recursive { params.append(.init(name: "Recursive", value: String(v))) }
        if let v = query.SearchTerm, !v.isEmpty { params.append(.init(name: "SearchTerm", value: v)) }
        if let v = query.StartIndex { params.append(.init(name: "StartIndex", value: String(v))) }
        if let v = query.Limit { params.append(.init(name: "Limit", value: String(v))) }
        if let v = query.IncludeItemTypes { params.append(.init(name: "IncludeItemTypes", value: v)) }
        if let v = query.IsFavorite { params.append(.init(name: "IsFavorite", value: String(v))) }
        if let v = query.IsPlayed { params.append(.init(name: "IsPlayed", value: String(v))) }
        if let v = query.SortBy { params.append(.init(name: "SortBy", value: v)) }
        if !params.isEmpty { components.queryItems = params }
        return try await request(components.string!)
    }

    func getItem(_ id: String) async throws -> Item {
        try await request("/Items/\(id)")
    }

    func adjacentEpisodes(_ id: String) async throws -> AdjacentEpisodes {
        try await request("/Items/\(id)/AdjacentEpisodes")
    }

    func resume(userId: String, limit: Int? = nil) async throws -> ItemList {
        let suffix = limit.map { "?Limit=\($0)" } ?? ""
        return try await request("/Users/\(userId)/Items/Resume\(suffix)")
    }

    func recommendations(userId: String, itemLimit: Int = 10) async throws -> [Recommendation] {
        try await request("/Recommendations?UserId=\(userId)&ItemLimit=\(itemLimit)")
    }


    // MARK: Playback

    /// Explicit platform input lets regression tests verify TV capabilities on macOS.
    static func playbackDeviceProfile(isAppleTV: Bool) -> [String: Any] {
        // The native app plays anything AVFoundation supports (H.264/HEVC, MKV,
        // AC3/EAC3, MP4, HLS), so the device profile advertises wide support and
        // the backend prefers direct play.
        var profile: [String: Any] = [
            "Name": "Envision",
            "MaxStreamingBitrate": 100_000_000,
            "MaxStaticBitrate": 120_000_000,
            "MusicStreamingTranscodingBitrate": 384_000,
            "DirectPlayProfiles": [
                ["Container": "mp4,m4v,mov,mkv,webm", "Type": "Video", "VideoCodec": "h264,hevc,vp9,av1", "AudioCodec": "aac,ac3,eac3,mp3,flac,opus,alac"],
                ["Container": "hls", "Type": "Video", "VideoCodec": "h264,hevc", "AudioCodec": "aac,ac3,eac3,mp3"],
            ],
            "TranscodingProfiles": [
                ["Container": "mp4", "Type": "Video", "VideoCodec": "h264,hevc", "AudioCodec": "aac", "Context": "Streaming", "Protocol": "hls", "BreakOnNonKeyFrames": true],
            ],
            "SubtitleProfiles": ["vtt", "srt", "sub", "ass", "ssa"].map { ["Format": $0, "Method": "External"] },
        ]
        if isAppleTV {
            // AVKit needs compatible containers and stream-provided subtitles.
            profile["Name"] = "Envision Apple TV"
            profile["DirectPlayProfiles"] = [
                ["Container": "mp4,m4v,mov", "Type": "Video", "VideoCodec": "h264,hevc", "AudioCodec": "aac,ac3,eac3,mp3,alac"],
                ["Container": "hls", "Type": "Video", "VideoCodec": "h264,hevc", "AudioCodec": "aac,ac3,eac3"],
                ["Container": "mp3,m4a,aac,flac,wav", "Type": "Audio"],
            ]
            profile["SubtitleProfiles"] = [["Format": "vtt", "Method": "Hls"]]
        }
        return profile
    }

    func playbackInfo(_ id: String, startTimeTicks: Int64 = 0) async throws -> PlaybackInfo {
        #if os(tvOS)
        let profile = Self.playbackDeviceProfile(isAppleTV: true)
        #else
        let profile = Self.playbackDeviceProfile(isAppleTV: false)
        #endif
        return try await request(
            "/Items/\(id)/PlaybackInfo?StartTimeTicks=\(max(0, startTimeTicks))",
            method: "POST", body: Self.json(["DeviceProfile": profile]))
    }

    func subtitleSearch(_ id: String, language: String) async throws -> [SubtitleSearchResult] {
        struct Wrapper: Codable { var Results: [SubtitleSearchResult] }
        let wrapper: Wrapper = try await request("/Items/\(id)/SubtitleSearch?Language=\(language)")
        return wrapper.Results
    }

    func downloadSubtitle(_ id: String, fileId: Int) async throws -> [String: String] {
        try await request("/Items/\(id)/SubtitleDownload", method: "POST", body: Self.json(["FileId": fileId]))
    }

    func reportProgress(itemId: String, positionTicks: Int64, playSessionId: String?) async throws {
        try await requestEmpty("/Sessions/Playing/Progress", method: "POST",
                               body: Self.json(["ItemId": itemId, "PositionTicks": positionTicks, "PlaySessionId": playSessionId ?? ""]))
    }

    func reportStopped(itemId: String, positionTicks: Int64, playSessionId: String?) async throws {
        try await requestEmpty("/Sessions/Playing/Stopped", method: "POST",
                               body: Self.json(["ItemId": itemId, "PositionTicks": positionTicks, "PlaySessionId": playSessionId ?? ""]))
    }

    func setFavorite(userId: String, itemId: String, _ favorite: Bool) async throws -> UserData {
        try await request("/Users/\(userId)/FavoriteItems/\(itemId)", method: favorite ? "POST" : "DELETE")
    }

    func setPlayed(userId: String, itemId: String, _ played: Bool) async throws -> UserData {
        try await request("/Users/\(userId)/PlayedItems/\(itemId)", method: played ? "POST" : "DELETE")
    }

    // MARK: Playlists

    func playlists() async throws -> PlaylistList {
        try await request("/Playlists")
    }

    func createPlaylist(name: String, ids: [String]) async throws -> [String: String] {
        try await request("/Playlists", method: "POST", body: Self.json(["Name": name, "Ids": ids]))
    }

    func playlistItems(_ id: String, startIndex: Int = 0, limit: Int = 200) async throws -> ItemList {
        try await request("/Playlists/\(id)/Items?StartIndex=\(startIndex)&Limit=\(limit)")
    }

    func appendPlaylistItems(_ id: String, ids: [String]) async throws {
        try await requestEmpty("/Playlists/\(id)/Items", method: "POST", body: Self.json(["Ids": ids]))
    }

    func deletePlaylist(_ id: String) async throws {
        try await requestEmpty("/Playlists/\(id)", method: "DELETE")
    }
}

