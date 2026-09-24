import SwiftUI

/// Propagates the Mac player's presentation state without moving the player
/// out of its navigation hierarchy or restarting its playback session.
struct PlaybackFullScreenPreference: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct PlaybackFullScreenEnvironment: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var macPlaybackFullScreen: Bool {
        get { self[PlaybackFullScreenEnvironment.self] }
        set { self[PlaybackFullScreenEnvironment.self] = newValue }
    }
}
