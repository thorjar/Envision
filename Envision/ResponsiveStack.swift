import SwiftUI

/// Chooses a stack using the actual container width, including iPad split view.
/// AnyLayout preserves child identity when the device rotates.
struct ResponsiveStack<Content: View>: View {
    var breakpoint: CGFloat = 600
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content
    @State private var width: CGFloat = 0

    var body: some View {
        let layout = width >= breakpoint
            ? AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
        layout { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
