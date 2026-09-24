import SwiftUI

/// Default style for TV action buttons: the pink accent fills the button when
/// focused, and the label is always white so it stays legible on the fill
/// (tvOS otherwise leaves the focused label color up to the style).
struct TVButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVButtonBody(content: configuration.label)
    }
}

/// Focus and enabled state come from the environment because this SDK's
/// ButtonStyleConfiguration does not expose isFocused/isEnabled.
private struct TVButtonBody<Content: View>: View {
    let content: Content
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        content
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 30)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isFocused ? Color.accentColor : Color.white.opacity(0.14))
            )
            .scaleEffect(isFocused ? 1.06 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}

/// Artwork with the resume-progress and watched overlays shared by the TV item
/// cards, so posters and episode stills get identical watch-state treatment.
struct TVItemArtwork: View {
    let item: Item
    var width: CGFloat
    var height: CGFloat
    /// Poster (portrait) or backdrop (landscape) artwork endpoint; the image
    /// loader falls back to the poster when no backdrop exists.
    var style: ItemImage.ImageStyle = .poster

    var body: some View {
        ItemImage(itemId: item.Id, name: item.Name, style: style)
            .frame(width: width, height: height).clipped()
            .overlay(alignment: .bottom) {
                if let data = item.UserData, let runtime = item.RunTimeTicks, runtime > 0,
                   data.PlaybackPositionTicks > 0, !data.Played {
                    ProgressView(value: min(1, Double(data.PlaybackPositionTicks) / Double(runtime)))
                        .tint(.pink).padding(12).background(.black.opacity(0.5))
                }
            }
            .overlay(alignment: .topTrailing) {
                if item.UserData?.Played == true {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.pink).padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}