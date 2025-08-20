//
//  ReownDeepLinkHandler.swift
//  PhantomConnect
//
//  Created by Ayush Rai on 25/07/25.
//

import Foundation
import os

class ReownDeepLinkHandler {
    static let shared = ReownDeepLinkHandler()
    
    private let logger = Logger(subsystem: "com.phantomconnect.app", category: "ReownDeepLinkHandler")
    private let userDefaults = UserDefaults.standard
    
    // Keys for UserDefaults
    private enum Keys {
        static let isConnected = "reown_is_connected"
        static let walletAddress = "reown_wallet_address"
        static let sessionTopic = "reown_session_topic"
        static let isLoading = "reown_is_loading"
        static let errorMessage = "reown_error_message"
        static let signature = "reown_signature"
        static let connectedWalletName = "reown_wallet_name"
    }
    
    private init() {
    }
    
    func handleURL(_ url: URL) -> Bool {
        logger.debug("🔗 Reown deep link received: \(url.absoluteString)")
        
        // Check if this is a WalletConnect deep link
        guard url.scheme?.hasPrefix("wc") == true || 
              url.absoluteString.contains("walletconnect") ||
              url.scheme == "phantomconnect" && url.host == "walletconnect" else {
            logger.debug("❌ Not a Reown/WalletConnect deep link")
            return false
        }
        
        // Note: In a real implementation, this would be handled by AppKit:
        // AppKit.instance.handleDeeplink(url)
        
        // For demonstration, we'll simulate handling different types of responses
        if url.absoluteString.contains("approve") || url.host == "walletconnect" {
            handleConnectionResponse(url: url)
            return true
        } else if url.absoluteString.contains("reject") {
            handleConnectionRejection(url: url)
            return true
        } else if url.absoluteString.contains("sign") {
            handleSignResponse(url: url)
            return true
        }
        
        logger.debug("🔄 Delegating to AppKit deep link handler")
        return true
    }
    
    // MARK: - Handle Connection Response
    private func handleConnectionResponse(url: URL) {
        logger.debug("📨 Handling Reown connection response from URL: \(url.absoluteString)")
        
        setLoading(false)
        
        // In a real implementation, AppKit would handle the session establishment
        // and provide session details through publishers
        
        // Simulate successful connection
        setConnected(true)
        setWalletAddress("0x742d35Cc6abC9C4b7F3c4b8B4F8b4C4D4E4F4A4B")
        setConnectedWalletName("Connected Wallet")
        setSessionTopic("mock_session_topic_12345")
        clearError()
        
        logger.debug("✅ Reown wallet connection successful")
    }
    
    // MARK: - Handle Connection Rejection
    private func handleConnectionRejection(url: URL) {
        logger.debug("❌ Handling Reown connection rejection from URL: \(url.absoluteString)")
        
        setLoading(false)
        setError("User rejected the connection request")
        
        logger.debug("❌ Reown wallet connection rejected by user")
    }
    
    // MARK: - Handle Sign Response
    private func handleSignResponse(url: URL) {
        logger.debug("📨 Handling Reown sign response from URL: \(url.absoluteString)")
        
        setLoading(false)
        
        // Parse URL for signature or error
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            let error = "Invalid Reown response URL"
            setError(error)
            logger.error("Invalid Reown response URL")
            return
        }
        
        let queryDict = Dictionary(uniqueKeysWithValues: queryItems.map {
            ($0.name, $0.value ?? "")
        })
        
        // Check for errors
        if let error = queryDict["error"] {
            setError("Signing failed: \(error)")
            logger.error("Reown signing failed: \(error)")
            return
        }
        
        // In a real implementation, this would come from the AppKit response
        // For simulation, we'll generate a mock signature
        let mockSignature = "0x4f4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788"
        setSignature(mockSignature)
        
        logger.debug("✅ Message signed successfully via Reown")
    }
    
    // MARK: - UserDefaults Helpers
    private func setLoading(_ loading: Bool) {
        userDefaults.set(loading, forKey: Keys.isLoading)
    }
    
    private func setError(_ error: String) {
        userDefaults.set(error, forKey: Keys.errorMessage)
    }
    
    private func clearError() {
        userDefaults.set("", forKey: Keys.errorMessage)
    }
    
    private func setConnected(_ connected: Bool) {
        userDefaults.set(connected, forKey: Keys.isConnected)
    }
    
    private func setWalletAddress(_ address: String) {
        userDefaults.set(address, forKey: Keys.walletAddress)
    }
    
    private func setConnectedWalletName(_ name: String) {
        userDefaults.set(name, forKey: Keys.connectedWalletName)
    }
    
    private func setSessionTopic(_ topic: String) {
        userDefaults.set(topic, forKey: Keys.sessionTopic)
    }
    
    private func setSignature(_ signature: String) {
        userDefaults.set(signature, forKey: Keys.signature)
    }
}