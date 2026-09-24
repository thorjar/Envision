#if canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#endif
import SwiftUI

/// Port of components/ItemImage.tsx: the artwork endpoint requires the
/// X-Emby-Token header, so fetch the image data with URLSession and render it.
struct ItemImage: View {
    enum ImageStyle {
        case poster
        /// Landscape TMDb backdrop; falls back to the poster when the server
        /// has no backdrop for the item.
        case backdrop
    }

    let itemId: String
    var name: String = ""
    var style: ImageStyle = .poster

    @EnvironmentObject private var auth: AuthStore
    @State private var image: PlatformImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.gray.opacity(0.35), Color.gray.opacity(0.15)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
#if canImport(AppKit)
            if let image = image {
                artwork(Image(nsImage: image))
            } else {
                placeholder
            }
#elseif canImport(UIKit)
            if let image = image {
                artwork(Image(uiImage: image))
            } else {
                placeholder
            }
#endif
        }
        .task(id: "\(itemId)-\(style == .backdrop ? "b" : "p")") { await load() }
    }

    private var placeholder: some View {
        Image(systemName: style == .backdrop ? "sparkles.rectangle.stack" : "film")
            .font(.title2)
            .foregroundStyle(.secondary)
    }

    /// Landscape art is letterboxed over a blurred copy of itself. A portrait
    /// poster served as the backdrop fallback then reads as a full image
    /// instead of a cropped center slice.
    @ViewBuilder
    private func artwork(_ image: Image) -> some View {
        if style == .backdrop {
            image.resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 24)
                .overlay(Color.black.opacity(0.35))
            image.resizable().aspectRatio(contentMode: .fit)
        } else {
            image.resizable().aspectRatio(contentMode: .fill)
        }
    }

    private func load() async {
        if style == .backdrop, let backdrop = await fetchImage(path: "/Items/\(itemId)/Images/Backdrop?v=b1-0") {
            image = backdrop
            return
        }
        image = await fetchImage(path: "/Items/\(itemId)/Images/Primary?v=hq2-0")
    }

    private func fetchImage(path: String) async -> PlatformImage? {
        guard let url = auth.api.resolveURL(path) else { return nil }
        var request = URLRequest(url: url)
        if let token = auth.api.tokenProvider() {
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        }
        guard let result = try? await URLSession.shared.data(for: request) else { return nil }
        let data = result.0
        let response = result.1
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        #if canImport(AppKit)
        guard let loaded = PlatformImage(data: data) else { return nil }
        #elseif canImport(UIKit)
        guard let loaded = PlatformImage(data: data) else { return nil }
        #endif
        return loaded
    }
}

