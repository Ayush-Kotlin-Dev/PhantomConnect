//
//  ReownWallet.swift
//  PhantomConnect
//
//  Created by Ayush Rai on 25/07/25.
//

import Foundation
import os
import UIKit

@objc
public class ReownWallet: NSObject, @unchecked Sendable {
    
    @objc
    public static let shared: ReownWallet = ReownWallet()
    
    private let logger = Logger(subsystem: "com.phantomconnect.app", category: "ReownWallet")
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
    
    private override init() {
        super.init()
        logger.debug("ReownWallet initialized")
        configureAppKit()
    }
    
    // MARK: - Configuration
    private func configureAppKit() {
        logger.debug("🔧 Configuring Reown AppKit")
        
        // Note: In a real implementation, you would need to:
        // 1. Add AppKit package dependency
        // 2. Import AppKit
        // 3. Configure with actual project ID from Reown Dashboard
        
        /*
        let metadata = AppMetadata(
            name: "PhantomConnect",
            description: "Multi-wallet connector with Phantom and WalletConnect support",
            url: "https://phantomconnect.app",
            icons: ["https://avatars.githubusercontent.com/u/179229932"],
            verifyUrl: "verify.walletconnect.com"
        )
        
        AppKit.configure(
            projectId: "YOUR_PROJECT_ID", // Get from https://cloud.reown.com
            metadata: metadata
        )
        */
    }
    
    // MARK: - Connection Management
    @objc
    public func presentWalletSelection(completion: @escaping @Sendable (Bool, String?) -> Void) {
        logger.debug("🚀 Presenting Reown wallet selection")
        
        DispatchQueue.main.async {
            self.setLoading(true)
            self.clearError()
        }
        
        // Note: In a real implementation, this would call:
        // AppKit.present()
        
        // For demonstration, we'll simulate the flow
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.logger.debug("📱 Reown wallet selection modal would be presented here")
            completion(true, nil)
        }
    }
    
    @objc
    public func connect(completion: @escaping @Sendable (Bool, String?) -> Void) {
        logger.debug("🔗 Initiating Reown wallet connection")
        
        DispatchQueue.main.async {
            self.setLoading(true)
            self.clearError()
        }
        
        // Note: In a real implementation, this would call:
        /*
        Task {
            do {
                try await AppKit.instance.connect(topic: nil)
                DispatchQueue.main.async {
                    self.setLoading(false)
                    completion(true, nil)
                }
            } catch {
                DispatchQueue.main.async {
                    let errorMessage = "Connection failed: \(error.localizedDescription)"
                    self.setError(errorMessage)
                    self.setLoading(false)
                    completion(false, errorMessage)
                }
            }
        }
        */
        
        // Simulate connection for demonstration
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Simulate successful connection
            self.setConnected(true)
            self.setWalletAddress("0x742d35Cc6abC9C4b7F3c4b8B4F8b4C4D4E4F4A4B")
            self.setConnectedWalletName("MetaMask")
            self.setLoading(false)
            self.logger.debug("✅ Simulated Reown wallet connection successful")
            completion(true, nil)
        }
    }
    
    @objc
    public func disconnect() {
        logger.debug("🔌 Disconnecting Reown wallet")
        
        // Note: In a real implementation, this would call:
        /*
        Task {
            do {
                let sessions = AppKit.instance.getSessions()
                for session in sessions {
                    try await AppKit.instance.disconnect(topic: session.topic)
                }
            } catch {
                logger.error("Disconnect error: \(error.localizedDescription)")
            }
        }
        */
        
        // Clear stored data
        setConnected(false)
        setWalletAddress("")
        setConnectedWalletName("")
        setSessionTopic("")
        clearError()
        
        logger.debug("✅ Reown wallet disconnected")
    }
    
    // MARK: - Message Signing
    @objc
    public func signMessage(_ message: String, completion: @escaping @Sendable (Bool, String?) -> Void) {
        logger.debug("📝 Signing message with Reown wallet")
        
        guard isConnected else {
            let error = "No wallet connected via Reown"
            DispatchQueue.main.async {
                self.setError(error)
                completion(false, error)
            }
            return
        }
        
        DispatchQueue.main.async {
            self.setLoading(true)
            self.clearError()
        }
        
        // Note: In a real implementation, this would call:
        /*
        Task {
            do {
                let messageData = message.data(using: .utf8)!
                let hexMessage = "0x" + messageData.map { String(format: "%02hhx", $0) }.joined()
                
                let result = try await AppKit.instance.request(
                    params: .init(
                        topic: sessionTopic,
                        method: "personal_sign",
                        params: AnyCodable([hexMessage, walletAddress]),
                        chainId: Blockchain("eip155:1")!
                    )
                )
                
                if let signature = result.result.value as? String {
                    DispatchQueue.main.async {
                        self.setSignature(signature)
                        self.setLoading(false)
                        completion(true, nil)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    let errorMessage = "Signing failed: \(error.localizedDescription)"
                    self.setError(errorMessage)
                    self.setLoading(false)
                    completion(false, errorMessage)
                }
            }
        }
        */
        
        // Simulate signing for demonstration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let mockSignature = "0x4f4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788"
            self.setSignature(mockSignature)
            self.setLoading(false)
            self.logger.debug("✅ Message signed successfully via Reown")
            completion(true, nil)
        }
    }
    
    // MARK: - State Properties
    public var isConnected: Bool {
        return userDefaults.bool(forKey: Keys.isConnected)
    }
    
    public var walletAddress: String {
        return userDefaults.string(forKey: Keys.walletAddress) ?? ""
    }
    
    public var connectedWalletName: String {
        return userDefaults.string(forKey: Keys.connectedWalletName) ?? ""
    }
    
    private var sessionTopic: String {
        return userDefaults.string(forKey: Keys.sessionTopic) ?? ""
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