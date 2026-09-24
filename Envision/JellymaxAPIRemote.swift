import Foundation

// Remote Jellyfin servers + S3 object stores (pages/admin/RemoteServersAdmin
// and ObjectStoresAdmin).
extension JellymaxAPI {
    // MARK: Remote servers

    func remoteServers() async throws -> [RemoteServer] {
        try await request("/RemoteServers")
    }

    func connectRemote(name: String, url: String, username: String, password: String) async throws -> [String: String] {
        try await request("/RemoteServers", method: "POST",
                          body: Self.json(["Name": name, "Url": url, "Username": username, "Password": password]))
    }

    func syncRemote(_ id: String) async throws -> [String: Int] {
        try await request("/RemoteServers/\(id)/Sync", method: "POST", body: Self.json([:]))
    }

    func removeRemote(_ id: String) async throws {
        try await requestEmpty("/RemoteServers/\(id)", method: "DELETE")
    }

    // MARK: Object stores

    func objectStores() async throws -> [ObjectStoreConnection] {
        try await request("/ObjectStores")
    }

    func connectObjectStore(
        name: String, endpoint: String?, region: String, bucket: String,
        prefix: String, accessKeyId: String, secretAccessKey: String,
        sessionToken: String?, collectionType: String
    ) async throws -> [String: String] {
        var payload: [String: Any] = [
            "Name": name, "Region": region, "Bucket": bucket,
            "AccessKeyId": accessKeyId, "SecretAccessKey": secretAccessKey,
            "CollectionType": collectionType,
        ]
        if let endpoint, !endpoint.isEmpty { payload["Endpoint"] = endpoint }
        if !prefix.isEmpty { payload["Prefix"] = prefix }
        if let sessionToken, !sessionToken.isEmpty { payload["SessionToken"] = sessionToken }
        return try await request("/ObjectStores", method: "POST", body: Self.json(payload))
    }

    func syncObjectStore(_ id: String) async throws -> [String: Int] {
        try await request("/ObjectStores/\(id)/Sync", method: "POST", body: Self.json([:]))
    }

    func removeObjectStore(_ id: String) async throws {
        try await requestEmpty("/ObjectStores/\(id)", method: "DELETE")
    }
}
