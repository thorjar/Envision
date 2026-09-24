import SwiftUI

/// A click/touch-and-drag timeline. Playback ticks never overwrite the preview.
struct PlaybackTimeline: View {
    let position: Double
    let duration: Double
    var onEditingChanged: (Bool) -> Void = { _ in }
    let onSeek: (Double) -> Void
    @State private var preview: Double?

    private var limit: Double { duration.isFinite ? max(0, duration) : 0 }
    private var displayed: Double {
        Self.displayed(position: position, preview: preview, duration: limit)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width - 16, 1)
            let fraction = limit > 0 ? displayed / limit : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.3)).frame(height: 4)
                Capsule().fill(.tint).frame(width: width * fraction, height: 4)
                Circle().fill(.tint).frame(width: 16, height: 16)
                    .offset(x: width * fraction - 8)
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard limit > 0 else { return }
                    if preview == nil { onEditingChanged(true) }
                    preview = Self.target(x: value.location.x, width: geometry.size.width, duration: limit)
                }
                .onEnded { value in
                    guard limit > 0 else { return }
                    onSeek(Self.target(x: value.location.x, width: geometry.size.width, duration: limit))
                    preview = nil
                    onEditingChanged(false)
                })
        }
        .frame(height: 44)
        .opacity(limit > 0 ? 1 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(formatSeconds(displayed)) of \(formatSeconds(limit))")
        .accessibilityAdjustableAction { direction in
            guard limit > 0 else { return }
            switch direction {
            case .increment: onSeek(min(limit, displayed + 10))
            case .decrement: onSeek(max(0, displayed - 10))
            @unknown default: break
            }
        }
    }

    nonisolated static func target(x: CGFloat, width: CGFloat, duration: Double) -> Double {
        guard duration.isFinite, duration > 0, width > 16 else { return 0 }
        let fraction = min(max((x - 8) / (width - 16), 0), 1)
        return Double(fraction) * duration
    }

    /// The knob's shown time: a live drag preview when present, else playback.
    nonisolated static func displayed(
        position: Double,
        preview: Double?,
        duration: Double
    ) -> Double {
        let limit = duration.isFinite ? max(0, duration) : 0
        return min(max(preview ?? position, 0), limit)
    }
}
