import SwiftUI

@main
struct EnvisionTVApp: App {
    @StateObject private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            TVRootView()
                .environmentObject(auth)
                .preferredColorScheme(.dark)
        }
    }
}
