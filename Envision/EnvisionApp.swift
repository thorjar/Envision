//
//  EnvisionApp.swift
//  Envision
//
//  Created by Jaret Thompson on 2026/06/29.
//

import SwiftUI

@main
struct EnvisionApp: App {
    @StateObject private var auth: AuthStore

    init() {
        let store = AuthStore()
        AuthStoreLocator.shared = store
        _auth = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
            #if os(macOS)
                .frame(minWidth: 700, minHeight: 480)
            #endif
        }
    }
}

