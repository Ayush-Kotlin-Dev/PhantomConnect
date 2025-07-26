//
//  PhantomDeepLinkHandler.swift
//  PhantomConnect
//
//  Created by Ayush Rai on 25/07/25.
//

import Foundation
import CryptoKit
import os
import TweetNacl

class PhantomDeepLinkHandler {
    static let shared = PhantomDeepLinkHandler()

    private let logger = Logger(subsystem: "com.phantomconnect.app", category: "PhantomDeepLinkHandler")

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

            logger.debug("🔍 NaCl Box decryption details:")
            logger.debug("   Dapp private key length: \(dappPrivateKeyData.count)")
            logger.debug("   Phantom public key length: \(phantomPublicKeyData.count)")
            logger.debug("   Nonce length: \(nonceData.count)")
            logger.debug("   Encrypted data length: \(encryptedDataBytes.count)")

            // Use NaCl Box.open for decryption
            let decryptedData = try NaclBox.open(message: encryptedDataBytes,
                                                 nonce: nonceData,
                                                 publicKey: phantomPublicKeyData,
                                                 secretKey: dappPrivateKeyData)

            // Now create shared secret for future operations
            let naclSharedSecret = try NaclBox.before(publicKey: phantomPublicKeyData,
                                                      secretKey: dappPrivateKeyData)

            PhantomState.shared.setSharedSecret(naclSharedSecret)

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
        logger.debug("   Expected nonce length: 24")

        // Validate lengths
        guard nonceData.count == 24 else {
            logger.error("Invalid nonce length: expected 24, got \(nonceData.count)")
            throw PhantomError.invalidResponse
        }

        // Use NaclSecretBox.open for decryption
        let decrypted = try NaclSecretBox.open(box: encryptedDataBytes,
                                               nonce: nonceData,
                                               key: sharedSecret)

        logger.debug("✅ NaCl SecretBox decryption successful")
        return decrypted
    }
}
