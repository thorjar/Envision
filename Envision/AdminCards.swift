#if canImport(AppKit)
import AppKit
#endif
import SwiftUI

// Dashboard card contents for libraries, scans, and users.
extension AdminView {
    var librariesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Add a library").font(.caption).bold().foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name").font(.caption2).foregroundStyle(.secondary)
                        TextField("Movies", text: $newLibraryName)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Collection type").font(.caption2).foregroundStyle(.secondary)
                        Picker("", selection: $newLibraryType) {
                            Text("movies").tag("movies")
                            Text("tvshows").tag("tvshows")
                            Text("music").tag("music")
                            Text("homevideos").tag("homevideos")
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Media directory (on the server)").font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("Choose a folder on the server or type a path",
                                  text: $newLibraryPath)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            chooseLibraryPath()
                        } label: {
                            Label("Browse server folders…", systemImage: "folder")
                        }
                        .help("Walk the server's folders — that is where your mounted media lives")
                    }
                }
                Button("Create library") { Task { await addLibrary() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(newLibraryName.trimmingCharacters(in: .whitespaces).isEmpty
                              || newLibraryPath.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Divider()
            if libraries.isEmpty {
                Text("No libraries yet.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                // Grouped by owning server, exactly like the sidebar, so the
                // local server and each connected remote are labelled.
                ForEach(Array(libraryGroups.enumerated()), id: \.element.id) { index, group in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(group.isLocal ? Color.pink : Color.green)
                                .frame(width: 6, height: 6)
                            Text(group.name).font(.caption).bold()
                            Text("· \(group.libraries.count) \(group.libraries.count == 1 ? "library" : "libraries")")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                        Text(group.isLocal
                             ? "Local server"
                             : (group.libraries.first?.IsObjectStore == true ? "Object storage" : "Connected Jellyfin server"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 12)
                        ForEach(group.libraries) { library in
                            AdminLibraryRow(
                                library: library,
                                onOpen: { router.go(.library(library.ItemId)) },
                                onDelete: { Task { await deleteLibrary(library) } }
                            )
                        }
                    }
                    if index < libraryGroups.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    var scanContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Library scans and their progress.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            ForEach(scans) { scan in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(scan.Id).font(.callout).lineLimit(1)
                        Spacer()
                        Text(scan.State)
                            .font(.caption).bold()
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Color.pink.opacity(0.12), in: Capsule())
                            .foregroundStyle(.pink)
                    }
                    HStack(spacing: 12) {
                        Text("scanned \(scan.Scanned ?? 0)")
                        if let removed = scan.Removed { Text("removed \(removed)") }
                        if let failures = scan.ProbeFailures, failures > 0 {
                            Text("\(failures) probe failures").foregroundStyle(.orange)
                        }
                        if let failures = scan.MetadataFailures, failures > 0 {
                            Text("\(failures) metadata failures").foregroundStyle(.orange)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                Divider()
            }
            if scans.isEmpty {
                Text("No scan tasks reported.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    var usersContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Create a user").font(.caption).bold().foregroundStyle(.secondary)
                ResponsiveStack(spacing: 8) {
                    TextField("Username", text: $newUser)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password (12+ characters)", text: $newPassword)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Administrator", isOn: $newIsAdmin)
                    Button("Create user") { Task { await addUser() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(newUser.isEmpty || newPassword.count < 12)
                }
            }
            Divider()
            ForEach(users, id: \.Id) { user in
                HStack(spacing: 10) {
                    Image(systemName: user.Policy?.IsAdministrator == true ? "person.badge.shield.checkmark" : "person")
                        .foregroundStyle(.pink)
                        .frame(width: 20)
                    Text(user.Name).font(.callout).bold()
                    Spacer()
                    Text(user.Policy?.IsAdministrator == true ? "Administrator" : "User")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }
}

/// Libraries grouped by owning server (same grouping as the sidebar).
extension AdminView {
    var libraryGroups: [LibraryGroup] {
        LibraryGrouping.groups(libraries, localServerName: serverName)
    }

    /// Where the server folder browser should open: the path already typed, else
    /// a known local library location (normally `/media/...`, the mounted media
    /// root), else the server's own default (its working directory).
    var libraryBrowserStartPath: String? {
        let typed = newLibraryPath.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty { return typed }
        return libraries.first { $0.IsRemote != true }?.Locations?.first
    }
}

/// A clickable admin library row: opens the library, with a separate delete
/// action on the trailing trash button.
private struct AdminLibraryRow: View {
    let library: Library
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(systemName: adminLibraryIcon(library.CollectionType))
                        .foregroundStyle(.pink)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(library.Name).font(.callout).bold()
                        Text((library.Locations?.joined(separator: ", ")) ?? "")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(library.Name)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Delete library")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            hovering ? Color.pink.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .onHover { hovering = $0 }
    }
}

