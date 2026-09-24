import Foundation

// Data actions for AdminView.
extension AdminView {
    /// Open the server-side folder browser (port of the web frontend's
    /// DirectoryPicker button). The server is the only side that can see these
    /// paths — it usually runs in a container with host folders mounted.
    func chooseLibraryPath() {
        showDirectoryBrowser = true
    }

    /// Apply a folder chosen in the browser, prefilling the name from the folder
    /// when the field is still empty.
    func applyLibraryPath(_ path: String) {
        newLibraryPath = path
        if newLibraryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let folder = (path as NSString).lastPathComponent
            if !folder.isEmpty { newLibraryName = folder }
        }
    }

    func load() async {
        if let info = try? await auth.api.systemInfo() { serverName = info.ServerName }
        if let libs = try? await auth.api.libraries() { libraries = libs }
        if let found = try? await auth.api.users() { users = found }
        if let tasks = try? await auth.api.scanStatus() { scans = tasks }
        await loadRemoteAndStores()
    }

    func addLibrary() async {
        do {
            _ = try await auth.api.createLibrary(name: newLibraryName, collectionType: newLibraryType, location: newLibraryPath)
            newLibraryName = ""
            newLibraryPath = ""
            await load()
            NotificationCenter.announceLibrariesChanged()
            // Match the web admin: kick off a scan so the library fills up
            // immediately, and report if the scan could not start.
            do {
                _ = try await auth.api.refreshLibrary()
                notice = "Library created. Scanning for media now…"
            } catch {
                notice = "Library created, but its scan could not start: \(error.localizedDescription)"
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteLibrary(_ library: Library) async {
        do {
            try await auth.api.deleteLibrary(library.ItemId)
            await load()
            NotificationCenter.announceLibrariesChanged()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refresh() async {
        do {
            _ = try await auth.api.refreshLibrary()
            notice = "Scan requested."
            try await Task.sleep(nanoseconds: 1_000_000_000)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addUser() async {
        do {
            _ = try await auth.api.createUser(name: newUser, password: newPassword, isAdministrator: newIsAdmin)
            newUser = ""
            newPassword = ""
            newIsAdmin = false
            await load()
            notice = "User created."
        } catch {
            self.error = error.localizedDescription
        }
    }
}
