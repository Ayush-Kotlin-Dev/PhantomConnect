//
//  PhantomConnectApp.swift
//  PhantomConnect
//
//  Created by Ayush Rai on 25/07/25.
//

import SwiftUI

@main
struct PhantomConnectApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // Handle deep links at the app level
                    handleAppDeepLink(url)
                }
        }
    }
    
    private func handleAppDeepLink(_ url: URL) {
        // This will be handled by ContentView's onOpenURL
        // but we can add app-level logging here if needed
        print("App received deep link: \(url)")
    }
}
