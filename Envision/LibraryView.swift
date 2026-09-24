import SwiftUI

/// Port of pages/LibraryPage.tsx: paged item grid with a library filter.
struct LibraryView: View {
    let libraryId: String

    @EnvironmentObject private var auth: AuthStore
    @State private var items: [Item] = []
    @State private var total = 0
    @State private var startIndex = 0
    @State private var searchTerm = ""
    @State private var appliedSearch = ""
    @State private var loading = true
    @State private var error: String?
    @State private var library: Library?

    private let pageSize = 100

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(library?.Name ?? "Library").font(.largeTitle).bold()
                    Text("\(total) items").font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    TextField("Filter this library…", text: $searchTerm)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                        .onSubmit(applyFilter)
                    Button("Apply", action: applyFilter)
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
                if loading {
                    ProgressView("Loading items…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ItemGrid(items: items, emptyMessage: "No items in this library.")
                    if total > pageSize {
                        HStack {
                            Button("← Previous") { startIndex = max(0, startIndex - pageSize) }
                                .disabled(startIndex == 0)
                            Spacer()
                            Text("Page \(startIndex / pageSize + 1) of \(max(1, (total + pageSize - 1) / pageSize)) (\(total) items)")
                                .font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button("Next →") { startIndex += pageSize }
                                .disabled(startIndex + pageSize >= total)
                        }
                    }
                }
            }
            .padding(24)
        }
        .task(id: "\(libraryId)|\(startIndex)|\(appliedSearch)") { await load() }
        .task { await loadLibraryMeta() }
    }

    private func applyFilter() {
        startIndex = 0
        appliedSearch = searchTerm.trimmingCharacters(in: .whitespaces)
    }

    private func loadLibraryMeta() async {
        if let cached = CatalogCache.shared.read([Library].self, forKey: "libraries") {
            library = cached.first { $0.ItemId == libraryId }
        }
        if let libs = try? await auth.api.libraries() {
            CatalogCache.shared.write("libraries", libs)
            library = libs.first { $0.ItemId == libraryId }
        }
    }

    private func load() async {
        let cacheKey = "library:\(libraryId):\(startIndex):\(appliedSearch)"
        if let cached = CatalogCache.shared.read(ItemList.self, forKey: cacheKey) {
            items = cached.Items
            total = cached.TotalRecordCount
            loading = false
        }
        error = nil
        do {
            let data = try await auth.api.getItems(ItemQuery(
                ParentId: libraryId,
                SearchTerm: appliedSearch.isEmpty ? nil : appliedSearch,
                StartIndex: startIndex,
                Limit: pageSize))
            items = data.Items
            total = data.TotalRecordCount
            CatalogCache.shared.write(cacheKey, data)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
