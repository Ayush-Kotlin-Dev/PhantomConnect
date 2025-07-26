//
//  PhantomDeepLinkHandler.swift
//  PhantomConnect
//
//  Created by Ayush Rai on 25/07/25.
//

import Foundation
import CryptoKit
import os
import Sodium

class PhantomDeepLinkHandler {
    static let shared = PhantomDeepLinkHandler()

    private let logger = Logger(subsystem: "com.phantomconnect.app", category: "PhantomDeepLinkHandler")
    private let sodium = Sodium()

    private init() {
    }

    func handleURL(_ url: URL) -> Bool {
        logger.debug("🔗 Deep link received: \(url.absoluteString)")

        guard url.scheme == "phantomconnect" else {
            logger.error("❌ Invalid scheme: \(url.scheme ?? "nil")")
            return false
        }

        switch url.host {
        case "connected":
            handleConnectResponse(url: url)
            return true
        case "signed":
            handleSignResponse(url: url)
            return true
        default:
            logger.error("❌ Unknown host: \(url.host ?? "nil")")
            return false
        }
    }

    // MARK: - Handle Connect Response
    func handleConnectResponse(url: URL) {
        logger.debug("📨 Handling connect response from URL: \(url.absoluteString)")

        PhantomState.shared.setLoading(false)

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems
        else {
            let error = "Invalid response URL"
            PhantomState.shared.setError(error)
            logger.error("Invalid response URL")
            return
        }

        let queryDict = Dictionary(uniqueKeysWithValues: queryItems.map {
            ($0.name, $0.value ?? "")
        })

        logger.debug("📋 Query parameters: \(queryDict.keys.joined(separator: ", "))")

        // Check for errors
        if let errorCode = queryDict["errorCode"], let errorMessage = queryDict["errorMessage"] {
            let error = "Connection failed: \(errorMessage) (Code: \(errorCode))"
            PhantomState.shared.setError(error)
            logger.error("Connection failed: \(errorMessage) (Code: \(errorCode))")
            return
        }

        // Parse successful response
        guard let phantomPublicKeyBase58 = queryDict["phantom_encryption_public_key"],
              let nonceBase58 = queryDict["nonce"],
              let encryptedDataBase58 = queryDict["data"]
        else {
            let error = "Missing required response parameters"
            PhantomState.shared.setError(error)
            logger.error("Missing required response parameters")
            return
        }

        logger.debug("🔐 Starting decryption process...")

        do {
            // Get the required data for NaCl Box decryption
            guard let phantomPublicKeyData = Data(base58Encoded: phantomPublicKeyBase58),
                  let nonceData = Data(base58Encoded: nonceBase58),
                  let encryptedDataBytes = Data(base58Encoded: encryptedDataBase58),
                  let dappPrivateKeyData = PhantomState.shared.dappPrivateKey
            else {
                throw PhantomError.invalidResponse
            }

            // Convert keys to format compatible with Sodium
            let dappPrivateKeyBytes = Array(dappPrivateKeyData)
            let phantomPublicKeyBytes = Array(phantomPublicKeyData)
            let nonceBytes = Array(nonceData)
            let encryptedBytes = Array(encryptedDataBytes)

            logger.debug("🔍 NaCl Box decryption details:")
            logger.debug("   Dapp private key length: \(dappPrivateKeyBytes.count)")
            logger.debug("   Phantom public key length: \(phantomPublicKeyBytes.count)")
            logger.debug("   Nonce length: \(nonceBytes.count)")
            logger.debug("   Encrypted data length: \(encryptedBytes.count)")

            // Use NaCl Box.open for decryption
            guard let decryptedBytes = self.sodium.box.open(authenticatedCipherText: encryptedBytes,
                                                            senderPublicKey: phantomPublicKeyBytes,
                                                            recipientSecretKey: dappPrivateKeyBytes,
                                                            nonce: nonceBytes)
            else {
                throw PhantomError.invalidResponse
            }

            let decryptedData = Data(decryptedBytes)

            // Now create shared secret for future operations
            guard let naclSharedSecret = self.sodium.box.beforenm(recipientPublicKey: phantomPublicKeyBytes,
                                                                  senderSecretKey: dappPrivateKeyBytes)
            else {
                throw PhantomError.invalidResponse
            }

            PhantomState.shared.setSharedSecret(Data(naclSharedSecret))

            logger.debug("✅ NaCl Box decryption successful")

            // Parse the decrypted JSON
            if let json = try JSONSerialization.jsonObject(with: decryptedData) as? [String: Any],
               let publicKey = json["public_key"] as? String,
               let session = json["session"] as? String {

                logger.debug("✅ JSON parsing successful - PublicKey: \(publicKey)")

                PhantomState.shared.setPublicKey(publicKey)
                PhantomState.shared.setSession(session)
                PhantomState.shared.setConnected(true)
                PhantomState.shared.clearError()
                logger.debug("🎉 Connection completed successfully!")
            } else {
                let error = "Failed to parse connection response - Invalid JSON structure"
                PhantomState.shared.setError(error)
                logger.error("Failed to parse connection response - Invalid JSON structure")
            }
        } catch {
            let errorMsg = "Failed to decrypt response: \(error.localizedDescription) (\(type(of: error)))"
            PhantomState.shared.setError(errorMsg)
            logger.error("Failed to decrypt response: \(error.localizedDescription) (\(type(of: error)))")
        }
    }

    // MARK: - Handle Sign Response
    func handleSignResponse(url: URL) {
        logger.debug("📨 Handling sign response from URL: \(url.absoluteString)")

        PhantomState.shared.setLoading(false)

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems
        else {
            let error = "Invalid response URL"
            PhantomState.shared.setError(error)
            logger.error("Invalid response URL")
            return
        }

        let queryDict = Dictionary(uniqueKeysWithValues: queryItems.map {
            ($0.name, $0.value ?? "")
        })

        // Check for errors
        if let errorCode = queryDict["errorCode"], let errorMessage = queryDict["errorMessage"] {
            let error = "Signing failed: \(errorMessage) (Code: \(errorCode))"
            PhantomState.shared.setError(error)
            logger.error("Signing failed: \(errorMessage) (Code: \(errorCode))")
            return
        }

        // Parse successful response
        guard let nonceBase58 = queryDict["nonce"],
              let encryptedDataBase58 = queryDict["data"]
        else {
            let error = "Missing required response parameters"
            PhantomState.shared.setError(error)
            logger.error("Missing required response parameters")
            return
        }

        do {
            let decryptedData = try decryptPayload(
                encryptedData: encryptedDataBase58,
                nonce: nonceBase58
            )

            if let json = try JSONSerialization.jsonObject(with: decryptedData) as? [String: Any],
               let signature = json["signature"] as? String {
                PhantomState.shared.setSignature(signature)
                logger.debug("✅ Message signed successfully!")
            } else {
                let error = "Failed to parse signature response"
                PhantomState.shared.setError(error)
                logger.error("Failed to parse signature response")
            }
        } catch {
            let errorMsg = "Failed to decrypt response: \(error.localizedDescription)"
            PhantomState.shared.setError(errorMsg)
            logger.error("Failed to decrypt response: \(error.localizedDescription)")
        }
    }

    // MARK: - Decryption Helper
    private func decryptPayload(encryptedData: String, nonce: String) throws -> Data {
        guard let sharedSecret = PhantomState.shared.sharedSecret else {
            throw PhantomError.noSharedSecret
        }

        guard let nonceData = Data(base58Encoded: nonce),
              let encryptedDataBytes = Data(base58Encoded: encryptedData)
        else {
            throw PhantomError.invalidResponse
        }

        logger.debug("🔍 NaCl SecretBox decryption details:")
        logger.debug("   Nonce length: \(nonceData.count)")
        logger.debug("   Encrypted data length: \(encryptedDataBytes.count)")
        logger.debug("   Shared secret length: \(sharedSecret.count)")
        logger.debug("   Expected nonce length: \(self.sodium.secretBox.NonceBytes)")

        // Validate lengths
        guard nonceData.count == self.sodium.secretBox.NonceBytes else {
            logger.error("Invalid nonce length: expected \(self.sodium.secretBox.NonceBytes), got \(nonceData.count)")
            throw PhantomError.invalidResponse
        }

        // Try method 1: Use separate nonce and ciphertext
        guard let decrypted = self.sodium.secretBox.open(
            authenticatedCipherText: Array(encryptedDataBytes),
            secretKey: Array(sharedSecret),
            nonce: Array(nonceData)
        )
        else {
            logger.error("SecretBox decryption failed with separate nonce/ciphertext")

            // Try method 2: Combined nonce and ciphertext (fallback)
            logger.debug("Trying fallback method with combined nonce+ciphertext")
            guard let fallbackDecrypted = self.sodium.secretBox.open(
                nonceAndAuthenticatedCipherText: Array(encryptedDataBytes),
                secretKey: Array(sharedSecret)
            )
            else {
                logger.error("Both SecretBox decryption methods failed")
                throw PhantomError.invalidResponse
            }

            logger.debug("✅ NaCl SecretBox decryption successful with fallback method")
            return Data(fallbackDecrypted)
        }

        logger.debug("✅ NaCl SecretBox decryption successful")
        return Data(decrypted)
    }
}