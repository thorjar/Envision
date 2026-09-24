import SwiftUI

// Dashboard card contents for remote Jellyfin servers and S3 object stores
// (ports of pages/admin/RemoteServersAdmin.tsx and ObjectStoresAdmin.tsx).
extension AdminView {
    var remoteServersContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Connect a server").font(.caption).bold().foregroundStyle(.secondary)
                HStack {
                    TextField("Name", text: $remoteName).textFieldStyle(.roundedBorder)
                    TextField("https://server.example.com", text: $remoteUrl).textFieldStyle(.roundedBorder)
                }
                HStack {
                    TextField("Username", text: $remoteUsername).textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $remotePassword).textFieldStyle(.roundedBorder)
                    Button("Connect server") { Task { await connectRemoteServer() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(remoteName.isEmpty || remoteUrl.isEmpty || remoteUsername.isEmpty || remotePassword.isEmpty)
                }
            }
            Divider()
            ForEach(remoteServers) { server in
                HStack(spacing: 10) {
                    Image(systemName: "server.rack")
                        .foregroundStyle(.pink)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(server.Name).font(.callout).bold()
                        Text(server.Url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if let lastError = server.LastError, !lastError.isEmpty {
                            Text(lastError).font(.caption).foregroundStyle(.red).lineLimit(1)
                        }
                    }
                    Spacer()
                    Button("Sync") { Task { await syncRemote(server) } }
                    Button {
                        Task { await removeRemote(server) }
                    } label: {
                        Image(systemName: "trash").foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove server")
                }
                .padding(.vertical, 4)
                Divider()
            }
            if remoteServers.isEmpty {
                Text("No remote servers connected.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    var objectStoresContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Connect an object store").font(.caption).bold().foregroundStyle(.secondary)
                HStack {
                    TextField("Name", text: $storeName).textFieldStyle(.roundedBorder)
                    TextField("Bucket", text: $storeBucket).textFieldStyle(.roundedBorder)
                    TextField("Region (e.g. us-east-1)", text: $storeRegion).textFieldStyle(.roundedBorder)
                    Picker("", selection: $storeCollectionType) {
                        Text("Movies").tag("movies")
                        Text("TV Shows").tag("tvshows")
                        Text("Music").tag("music")
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                HStack {
                    TextField("Endpoint (optional)", text: $storeEndpoint).textFieldStyle(.roundedBorder)
                    TextField("Prefix (optional)", text: $storePrefix).textFieldStyle(.roundedBorder)
                    SecureField("Access key ID", text: $storeAccessKey).textFieldStyle(.roundedBorder)
                    SecureField("Secret access key", text: $storeSecret).textFieldStyle(.roundedBorder)
                }
                HStack {
                    SecureField("Session token (optional)", text: $storeSessionToken)
                        .textFieldStyle(.roundedBorder)
                    Spacer()
                    Button("Connect object store") { Task { await connectObjectStore() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(storeName.isEmpty || storeBucket.isEmpty || storeRegion.isEmpty || storeAccessKey.isEmpty || storeSecret.isEmpty)
                }
            }
            Divider()
            ForEach(objectStores) { store in
                HStack(spacing: 10) {
                    Image(systemName: "externaldrive")
                        .foregroundStyle(.pink)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.Name).font(.callout).bold()
                        Text("\(store.Bucket)/\(store.Prefix) · \(store.Region)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("Sync") { Task { await syncObjectStore(store) } }
                    Button {
                        Task { await removeObjectStore(store) }
                    } label: {
                        Image(systemName: "trash").foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove object store")
                }
                .padding(.vertical, 4)
                Divider()
            }
            if objectStores.isEmpty {
                Text("No object stores connected.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

