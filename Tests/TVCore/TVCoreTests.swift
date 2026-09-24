import Foundation

final class StubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        precondition(request.value(forHTTPHeaderField: "X-Emby-Token") == "test-token")
        let failing = request.url!.path.contains("failure")
        let body: String
        if request.url!.path.contains("PlaybackInfo") {
            precondition(request.httpMethod == "POST")
            precondition(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                .contains(URLQueryItem(name: "StartTimeTicks", value: "0")))
            body = failing ? "{\"Error\":\"Transcoding unavailable\"}" : "{\"MediaSources\":[],\"PlaySessionId\":\"test-session\"}"
        } else if request.url!.path.contains("QuickConnect/Initiate") {
            precondition(request.httpMethod == "POST")
            body = "{\"Code\":\"ABCD2345\",\"ExpiresIn\":300}"
        } else if request.url!.path.contains("QuickConnect/Connect") {
            precondition(request.httpMethod == "GET")
            precondition(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                .contains(URLQueryItem(name: "Code", value: "ABCD2345")))
            body = "{\"Authenticated\":true,\"User\":{\"Id\":\"u1\",\"Name\":\"viewer\",\"Policy\":{\"IsAdministrator\":false}},\"AccessToken\":\"paired-token\",\"ServerId\":\"s1\"}"
        } else if request.url!.path.contains("SubtitleSearch") {
            precondition(request.httpMethod == "GET")
            precondition(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                .contains(URLQueryItem(name: "Language", value: "en")))
            body = "{\"Results\":[{\"FileId\":42,\"FileName\":\"Movie.en.srt\",\"Language\":\"en\",\"DownloadCount\":1234,\"HearingImpaired\":false}]}"
        } else if request.url!.path.contains("SubtitleDownload") {
            precondition(request.httpMethod == "POST")
            body = "{\"Content\":\"1\\n00:00:01,000 --> 00:00:02,000\\nHello\",\"Format\":\"srt\"}"
        } else {
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            precondition(query.contains(URLQueryItem(name: "SearchTerm", value: "A & B / 日本語")))
            precondition(query.contains(URLQueryItem(name: "StartIndex", value: "60")))
            body = "{\"Items\":[],\"TotalRecordCount\":0,\"StartIndex\":60}"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: failing ? 503 : 200,
                                       httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct TVCoreTests {
    static func main() async throws {
        for value in ["https://media.example.com", " http://192.168.1.20:8097 \n", "http://[::1]:8097"] {
            precondition(TVServerAddress.parse(value) != nil, value)
        }
        for value in ["", "media.example.com", "ftp://media.example.com", "https://u:p@host", "https://host?token=x", "https://host#fragment", "http://host:0"] {
            precondition(TVServerAddress.parse(value) == nil, value)
        }
        let tvProfile = JellymaxAPI.playbackDeviceProfile(isAppleTV: true)
        precondition(tvProfile["Name"] as? String == "Envision Apple TV")
        let direct = tvProfile["DirectPlayProfiles"] as! [[String: String]]
        precondition(direct.filter { $0["Type"] == "Video" }.allSatisfy {
            $0["VideoCodec"] == "h264,hevc" && !$0["Container"]!.contains("mkv") && !$0["Container"]!.contains("webm")
        })
        precondition(tvProfile["SubtitleProfiles"] as? [[String: String]] == [["Format": "vtt", "Method": "Hls"]])
        let transcode = tvProfile["TranscodingProfiles"] as! [[String: Any]]
        precondition(transcode.first?["Protocol"] as? String == "hls")
        let original = JellymaxAPI.playbackDeviceProfile(isAppleTV: false)
        precondition(original["Name"] as? String == "Envision")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let api = JellymaxAPI(baseURL: URL(string: "https://test.invalid")!, tokenProvider: { "test-token" },
                             session: URLSession(configuration: config))
        let info = try await api.playbackInfo("success", startTimeTicks: -1)
        precondition(info.PlaySessionId == "test-session")
        // Pairing: the code, its poll status, and the claimed session all have
        // to survive the PascalCase JSON contract shared by the TV and phone.
        let initiation = try await api.initiatePairing(deviceName: "Apple TV")
        precondition(initiation.Code == "ABCD2345" && initiation.ExpiresIn == 300)
        let claimed = try await api.pairingStatus(code: initiation.Code)
        precondition(claimed.Authenticated)
        precondition(claimed.AccessToken == "paired-token")
        precondition(claimed.User?.Name == "viewer")
        precondition(claimed.User?.Policy?.IsAdministrator == false)
        // OpenSubtitles: the search result fields and the download payload are
        // the contract between the TV/phone panels and jellymax's provider.
        let subtitles = try await api.subtitleSearch("success", language: "en")
        precondition(subtitles.count == 1 && subtitles[0].FileId == 42)
        precondition(subtitles[0].FileName == "Movie.en.srt" && subtitles[0].Language == "en")
        precondition(subtitles[0].DownloadCount == 1234 && !subtitles[0].HearingImpaired)
        let downloaded = try await api.downloadSubtitle("success", fileId: subtitles[0].FileId)
        precondition(downloaded["Format"] == "srt")
        precondition(downloaded["Content"]?.contains("-->") == true)
        do {
            _ = try await api.playbackInfo("failure")
            preconditionFailure("HTTP failure must throw")
        } catch APIError.failed(let code, let message) {
            precondition(code == 503 && message == "Transcoding unavailable")
        }
        let results = try await api.getItems(ItemQuery(SearchTerm: "A & B / 日本語", StartIndex: 60, Limit: 60))
        precondition(results.StartIndex == 60)
        let vtt = try toWebVtt("1\n00:00:01,000 --> 00:00:03,000\nHello\n", fileName: "test.srt")
        let cues = parseWebVtt(vtt)
        precondition(visibleSubtitle(cues, at: 2) == "Hello")
        precondition(visibleSubtitle(cues, at: 3).isEmpty)
        func makeItem(id: String, type: String, name: String = "",
                      index: Int? = nil, parentIndex: Int? = nil) -> Item {
            Item(Id: id, IsRemote: nil, Name: name, itemType: type, MediaType: nil, IsFolder: false,
                 ParentId: nil, LibraryId: nil, IndexNumber: index, ParentIndexNumber: parentIndex,
                 ChildCount: nil, SeriesId: nil, SeriesName: nil, SeriesTmdbId: nil, Container: nil,
                 Size: nil, RunTimeTicks: nil, MediaStreams: nil, UserData: nil, TmdbId: nil,
                 Year: nil, Overview: nil, Genres: nil, CommunityRating: nil)
        }
        let orderedSeasons = TVSeriesOrder.seasons([
            makeItem(id: "s2", type: "Season", name: "Two", index: 2),
            makeItem(id: "sp", type: "Season", name: "Specials", index: 0),
            makeItem(id: "s1", type: "Season", name: "One", index: 1),
            makeItem(id: "sn", type: "Season", name: "Unnumbered"),
            makeItem(id: "not", type: "Series", name: "Not a season"),
        ])
        precondition(orderedSeasons.map(\.Id) == ["s1", "s2", "sp", "sn"])
        precondition(TVSeriesOrder.seasonLabel(orderedSeasons[0]) == "Season 1")
        precondition(TVSeriesOrder.seasonLabel(orderedSeasons[2]) == "Specials")
        precondition(TVSeriesOrder.seasonLabel(orderedSeasons[3]) == "Specials")
        let orderedEpisodes = TVSeriesOrder.episodes([
            makeItem(id: "e9", type: "Episode", name: "Nine", index: 9, parentIndex: 2),
            makeItem(id: "eSP", type: "Episode", name: "Special", index: 1, parentIndex: 0),
            makeItem(id: "e3", type: "Episode", name: "Three", index: 3, parentIndex: 1),
            makeItem(id: "eUn", type: "Episode", name: "Unknown"),
            makeItem(id: "mv", type: "Movie", name: "Not an episode"),
        ])
        precondition(orderedEpisodes.map(\.Id) == ["e3", "e9", "eSP", "eUn"])
        precondition(TVSeriesOrder.parentSeasonLabel(makeItem(id: "e", type: "Episode", parentIndex: 3)) == "Season 3")
        precondition(TVSeriesOrder.parentSeasonLabel(makeItem(id: "e", type: "Episode", parentIndex: 0)) == "Specials")
        let catalogue = [
            makeItem(id: "m1", type: "Movie", name: "Movie"),
            makeItem(id: "s1", type: "Series", name: "Series"),
            makeItem(id: "e1", type: "Episode", name: "Episode"),
            makeItem(id: "a1", type: "Audio", name: "Song"),
        ]
        precondition(TVLibrarySections.movies(catalogue).map(\.Id) == ["m1"])
        precondition(TVLibrarySections.series(catalogue).map(\.Id) == ["s1", "e1"])
        print("PASS: server validation, authenticated API requests, playback HTTP errors, resume clamping, search encoding/pagination, subtitle timing, OpenSubtitles search/download, series/season/episode ordering, favorites/search section splitting")
    }
}
