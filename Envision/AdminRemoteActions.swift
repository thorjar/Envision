import SwiftUI
import Foundation

// Async actions for the remote server / object store cards.
extension AdminView {
    func loadRemoteAndStores() async {
        if let servers = try? await auth.api.remoteServers() { remoteServers = servers }
        if let stores = try? await auth.api.objectStores() { objectStores = stores }
    }

    func connectRemoteServer() async {
        do {
            _ = try await auth.api.connectRemote(name: remoteName, url: remoteUrl,
                                                 username: remoteUsername, password: remotePassword)
            remoteName = ""
            remoteUrl = ""
            remoteUsername = ""
            remotePassword = ""
            await loadRemoteAndStores()
            // The server appears in the sidebar as soon as its libraries sync.
            NotificationCenter.announceLibrariesChanged()
            notice = "Remote server connected. Run a sync to import its libraries."
        } catch {
            self.error = error.localizedDescription
        }
    }

    func syncRemote(_ server: RemoteServer) async {
        do {
            let result = try await auth.api.syncRemote(server.Id)
            notice = "Synced \(result["Items"] ?? 0) items from \(server.Name)."
            await loadRemoteAndStores()
            NotificationCenter.announceLibrariesChanged()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func removeRemote(_ server: RemoteServer) async {
        do {
            try await auth.api.removeRemote(server.Id)
            await loadRemoteAndStores()
            NotificationCenter.announceLibrariesChanged()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func connectObjectStore() async {
        do {
            _ = try await auth.api.connectObjectStore(
                name: storeName, endpoint: storeEndpoint, region: storeRegion,
                bucket: storeBucket, prefix: storePrefix, accessKeyId: storeAccessKey,
                secretAccessKey: storeSecret, sessionToken: storeSessionToken,
                collectionType: storeCollectionType)
            storeName = ""
            storeEndpoint = ""
            storeBucket = ""
            storePrefix = ""
            storeAccessKey = ""
            storeSecret = ""
            storeSessionToken = ""
            await loadRemoteAndStores()
            NotificationCenter.announceLibrariesChanged()
            notice = "Object store connected."
        } catch {
            self.error = error.localizedDescription
        }
    }

    func syncObjectStore(_ store: ObjectStoreConnection) async {
        do {
            let result = try await auth.api.syncObjectStore(store.Id)
            notice = "Synced \(result["Items"] ?? 0) items from \(store.Name)."
            await loadRemoteAndStores()
            NotificationCenter.announceLibrariesChanged()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func removeObjectStore(_ store: ObjectStoreConnection) async {
        do {
            try await auth.api.removeObjectStore(store.Id)
            await loadRemoteAndStores()
            NotificationCenter.announceLibrariesChanged()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
