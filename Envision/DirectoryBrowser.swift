import SwiftUI

/// Port of components/DirectoryPicker.tsx.
///
/// The media folders live on the machine running the jellymax server — for this
/// deployment that is a container with host folders mounted (e.g.
/// `./media:/media:ro`) — so a native folder dialog on this Mac would hand the
/// server paths it cannot read. This sheet walks the server's filesystem through
/// the admin-only `/Library/Paths` endpoint instead, exactly like the web UI.
struct DirectoryBrowser: View {
    /// Directory to open first; nil starts at the server's default location.
    var initialPath: String?
    let onSelect: (String) -> Void

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var current: String?
    @State private var parent: String?
    @State private var directories: [DirectoryChild] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            listing
            Divider()
            footer
        }
        .frame(maxWidth: 560, minHeight: 380, idealHeight: 540, maxHeight: 640)
        .task { await load(initialPath) }
    }

    private var header: some View {
        HStack {
            Text("Choose a folder on the server").font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Use this folder") {
                if let current { onSelect(current) }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(current == nil || loading || error != nil)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func load(_ path: String?) async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let result = try await auth.api.listDirectories(path: path)
            current = result.Path
            parent = result.Parent
            directories = result.Directories
        } catch {
            current = nil
            directories = []
            parent = nil
            self.error = error.localizedDescription
        }
    }

    private var listing: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Folders are read on the machine running the jellymax server.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(current ?? (loading ? "Loading…" : "Folder unavailable"))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(current ?? "")
                .textSelection(.enabled)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            } else if loading {
                ProgressView("Loading folders…")
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        if let parent {
                            DirectoryRow(icon: "arrow.turn.up.left", name: ".. (parent)", isParent: true) {
                                Task { await load(parent) }
                            }
                            Divider()
                        }
                        if directories.isEmpty {
                            Text(parent == nil ? "No directories found." : "No subdirectories here.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                        } else {
                            ForEach(Array(directories.enumerated()), id: \.element.Path) { index, directory in
                                DirectoryRow(icon: "folder", name: directory.Name, isParent: false) {
                                    Task { await load(directory.Path) }
                                }
                                if index < directories.count - 1 { Divider() }
                            }
                        }
                    }
                    .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// One browsable row: a folder to descend into, or the parent entry.
private struct DirectoryRow: View {
    let icon: String
    let name: String
    let isParent: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(isParent ? Color.secondary : Color.pink)
                    .frame(width: 20)
                Text(name)
                    .font(.callout)
                    .foregroundStyle(isParent ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(hovering ? Color.pink.opacity(0.10) : Color.clear)
        .onHover { hovering = $0 }
    }
}