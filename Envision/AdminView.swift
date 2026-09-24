import SwiftUI

/// Port of pages/AdminPage.tsx + the admin sub-pages (LibraryAdmin,
/// ScanAdmin, UsersAdmin, RemoteServersAdmin, ObjectStoresAdmin): the
/// administration page hosts selectable sections.
struct AdminView: View {
    enum Section: String, CaseIterable, Identifiable {
        case libraries, scan, users, remoteServers, objectStores

        var id: Self { self }

        var title: String {
            switch self {
            case .libraries: return "Libraries"
            case .scan: return "Scan"
            case .users: return "Users"
            case .remoteServers: return "Remote Servers"
            case .objectStores: return "Object Stores"
            }
        }

        var icon: String {
            switch self {
            case .libraries: return "folder.badge.gearshape"
            case .scan: return "arrow.triangle.2.circlepath"
            case .users: return "person.2"
            case .remoteServers: return "server.rack"
            case .objectStores: return "externaldrive.connected.to.line.beneath"
            }
        }
    }

    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var router: Router
    @State var section: Section = .libraries
    @State var libraries: [Library] = []
    /// Name of this server, used for the local library group header.
    @State var serverName = "This server"
    @State var users: [User] = []
    @State var scans: [ScanStatus] = []
    @State var error: String?
    @State var notice: String?
    @State var newLibraryName = ""
    @State var newLibraryPath = ""
    @State var newLibraryType = "movies"
    /// Server-side folder browser (opened by the "Browse server folders…" button).
    @State var showDirectoryBrowser = false
    @State var newUser = ""
    @State var newPassword = ""
    @State var newIsAdmin = false
    // Remote Jellyfin servers (admin/RemoteServersAdmin).
    @State var remoteServers: [RemoteServer] = []
    @State var remoteName = ""
    @State var remoteUrl = ""
    @State var remoteUsername = ""
    @State var remotePassword = ""
    // S3 object stores (admin/ObjectStoresAdmin).
    @State var objectStores: [ObjectStoreConnection] = []
    @State var storeName = ""
    @State var storeEndpoint = ""
    @State var storeRegion = ""
    @State var storeBucket = ""
    @State var storePrefix = ""
    @State var storeAccessKey = ""
    @State var storeSecret = ""
    @State var storeSessionToken = ""
    @State var storeCollectionType = "movies"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Administration").font(.largeTitle).bold()
                    Text("Manage libraries, users, and connected sources.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let notice {
                    Label(notice, systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.pink.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                // Section navigation (the web admin's sub-page links).
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases) { section in
                        Label(section.title, systemImage: section.icon).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                selectedSection
            }
            .padding(24)
        }
        .task { await load() }
        .sheet(isPresented: $showDirectoryBrowser) {
            DirectoryBrowser(initialPath: libraryBrowserStartPath) { path in
                applyLibraryPath(path)
            }
        }
    }

    @ViewBuilder
    private var selectedSection: some View {
        switch section {
        case .libraries:
            AdminCard(icon: Section.libraries.icon, title: Section.libraries.title) {
                librariesContent
            }
        case .scan:
            AdminCard(icon: Section.scan.icon, title: Section.scan.title) {
                scanContent
            }
        case .users:
            AdminCard(icon: Section.users.icon, title: Section.users.title) {
                usersContent
            }
        case .remoteServers:
            AdminCard(icon: Section.remoteServers.icon, title: Section.remoteServers.title) {
                remoteServersContent
            }
        case .objectStores:
            AdminCard(icon: Section.objectStores.icon, title: Section.objectStores.title) {
                objectStoresContent
            }
        }
    }
}

/// Shared card container for the admin dashboard.
struct AdminCard<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.pink, in: RoundedRectangle(cornerRadius: 9))
                Text(title).font(.headline)
                Spacer()
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}

func adminLibraryIcon(_ type: String) -> String {
    switch type {
    case "movies": return "film"
    case "tvshows": return "tv"
    case "music": return "music.note"
    default: return "folder"
    }
}
