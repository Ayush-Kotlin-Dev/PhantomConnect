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
                    handleAppDeepLink(url)
                }
        }
    }
    
    private func handleAppDeepLink(_ url: URL) {
        // Try Phantom deep link first
        if PhantomDeepLinkHandler.shared.handleURL(url) {
            return
        }
        
        // Try Reown deep link if Phantom didn't handle it
        _ = ReownDeepLinkHandler.shared.handleURL(url)
    }
}
