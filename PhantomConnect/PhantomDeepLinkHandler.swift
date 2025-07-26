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
    private let userDefaults = UserDefaults.standard

    // Keys for UserDefaults
    private enum Keys {
        static let isConnected = "phantom_is_connected"
        static let publicKey = "phantom_public_key"
        static let session = "phantom_session"
        static let sharedSecret = "phantom_shared_secret"
        static let dappPublicKey = "phantom_dapp_public_key"
        static let dappPrivateKey = "phantom_dapp_private_key"
        static let isLoading = "phantom_is_loading"
        static let errorMessage = "phantom_error_message"
        static let signature = "phantom_signature"
    }

    private init() {
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

    private func setPublicKey(_ key: String) {
        userDefaults.set(key, forKey: Keys.publicKey)
    }

    private func setSession(_ sessionValue: String) {
        userDefaults.set(sessionValue, forKey: Keys.session)
    }

    private func setSharedSecret(_ secret: Data) {
        userDefaults.set(secret, forKey: Keys.sharedSecret)
    }

    private func setSignature(_ sig: String) {
        userDefaults.set(sig, forKey: Keys.signature)
    }

    private var dappPrivateKey: Data? {
        return userDefaults.data(forKey: Keys.dappPrivateKey)
    }

    private var sharedSecret: Data? {
        return userDefaults.data(forKey: Keys.sharedSecret)
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

        setLoading(false)

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems
        else {
            let error = "Invalid response URL"
            setError(error)
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
            setError(error)
            logger.error("Connection failed: \(errorMessage) (Code: \(errorCode))")
            return
        }

        // Parse successful response
        guard let phantomPublicKeyBase58 = queryDict["phantom_encryption_public_key"],
              let nonceBase58 = queryDict["nonce"],
              let encryptedDataBase58 = queryDict["data"]
        else {
            let error = "Missing required response parameters"
            setError(error)
            logger.error("Missing required response parameters")
            return
        }

        logger.debug("🔐 Starting decryption process...")

        do {
            // Get the required data for NaCl Box decryption
            guard let phantomPublicKeyData = Data(handlerBase58Encoded: phantomPublicKeyBase58),
                  let nonceData = Data(handlerBase58Encoded: nonceBase58),
                  let encryptedDataBytes = Data(handlerBase58Encoded: encryptedDataBase58),
                  let dappPrivateKeyData = self.dappPrivateKey
            else {
                throw HandlerPhantomError.invalidResponse
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

            setSharedSecret(naclSharedSecret)

            logger.debug("✅ NaCl Box decryption successful")

            // Parse the decrypted JSON
            if let json = try JSONSerialization.jsonObject(with: decryptedData) as? [String: Any],
               let publicKey = json["public_key"] as? String,
               let session = json["session"] as? String {

                logger.debug("✅ JSON parsing successful - PublicKey: \(publicKey)")

                setPublicKey(publicKey)
                setSession(session)
                setConnected(true)
                clearError()
                logger.debug("🎉 Connection completed successfully!")
            } else {
                let error = "Failed to parse connection response - Invalid JSON structure"
                setError(error)
                logger.error("Failed to parse connection response - Invalid JSON structure")
            }
        } catch {
            let errorMsg = "Failed to decrypt response: \(error.localizedDescription) (\(type(of: error)))"
            setError(errorMsg)
            logger.error("Failed to decrypt response: \(error.localizedDescription) (\(type(of: error)))")
        }
    }

    // MARK: - Handle Sign Response
    func handleSignResponse(url: URL) {
        logger.debug("📨 Handling sign response from URL: \(url.absoluteString)")

        setLoading(false)

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems
        else {
            let error = "Invalid response URL"
            setError(error)
            logger.error("Invalid response URL")
            return
        }

        let queryDict = Dictionary(uniqueKeysWithValues: queryItems.map {
            ($0.name, $0.value ?? "")
        })

        // Check for errors
        if let errorCode = queryDict["errorCode"], let errorMessage = queryDict["errorMessage"] {
            let error = "Signing failed: \(errorMessage) (Code: \(errorCode))"
            setError(error)
            logger.error("Signing failed: \(errorMessage) (Code: \(errorCode))")
            return
        }

        // Parse successful response
        guard let nonceBase58 = queryDict["nonce"],
              let encryptedDataBase58 = queryDict["data"]
        else {
            let error = "Missing required response parameters"
            setError(error)
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
                setSignature(signature)
                logger.debug("✅ Message signed successfully!")
            } else {
                let error = "Failed to parse signature response"
                setError(error)
                logger.error("Failed to parse signature response")
            }
        } catch {
            let errorMsg = "Failed to decrypt response: \(error.localizedDescription)"
            setError(errorMsg)
            logger.error("Failed to decrypt response: \(error.localizedDescription)")
        }
    }

    // MARK: - Decryption Helper
    private func decryptPayload(encryptedData: String, nonce: String) throws -> Data {
        guard let sharedSecret = self.sharedSecret else {
            throw HandlerPhantomError.noSharedSecret
        }

        guard let nonceData = Data(handlerBase58Encoded: nonce),
              let encryptedDataBytes = Data(handlerBase58Encoded: encryptedData)
        else {
            throw HandlerPhantomError.invalidResponse
        }

        logger.debug("🔍 NaCl SecretBox decryption details:")
        logger.debug("   Nonce length: \(nonceData.count)")
        logger.debug("   Encrypted data length: \(encryptedDataBytes.count)")
        logger.debug("   Shared secret length: \(sharedSecret.count)")
        logger.debug("   Expected nonce length: 24")

        // Validate lengths
        guard nonceData.count == 24 else {
            logger.error("Invalid nonce length: expected 24, got \(nonceData.count)")
            throw HandlerPhantomError.invalidResponse
        }

        // Use NaclSecretBox.open for decryption
        let decrypted = try NaclSecretBox.open(box: encryptedDataBytes,
                                               nonce: nonceData,
                                               key: sharedSecret)

        logger.debug("✅ NaCl SecretBox decryption successful")
        return decrypted
    }
}

// MARK: - Custom Errors
enum HandlerPhantomError: Error {
    case noSharedSecret
    case invalidResponse
}

// MARK: - Base58 Encoding Extension
extension Data {
    var handlerBase58EncodedString: String {
        return HandlerBase58.encode(self)
    }

    init?(handlerBase58Encoded string: String) {
        guard let data = HandlerBase58.decode(string) else {
            return nil
        }
        self = data
    }
}

// MARK: - Base58 Implementation
struct HandlerBase58 {
    private static let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    private static let base = alphabet.count

    static func encode(_ data: Data) -> String {
        var bytes = Array(data)
        var zerosCount = 0

        for byte in bytes {
            if byte == 0 {
                zerosCount += 1
            } else {
                break
            }
        }

        bytes = Array(bytes.dropFirst(zerosCount))

        var result = ""

        while !bytes.isEmpty {
            var remainder = 0
            var newBytes: [UInt8] = []

            for byte in bytes {
                let temp = remainder * 256 + Int(byte)
                newBytes.append(UInt8(temp / base))
                remainder = temp % base
            }

            result = String(alphabet[alphabet.index(alphabet.startIndex, offsetBy: remainder)]) + result
            bytes = Array(newBytes.drop(while: { $0 == 0 }))
        }

        let prefix = String(repeating: alphabet.first!, count: zerosCount)
        return prefix + result
    }

    static func decode(_ string: String) -> Data? {
        var result = [UInt8]()
        var zerosCount = 0

        for char in string {
            if char == alphabet.first! {
                zerosCount += 1
            } else {
                break
            }
        }

        let chars = Array(string.dropFirst(zerosCount))

        for char in chars {
            guard let index = alphabet.firstIndex(of: char) else {
                return nil
            }
            let digit = alphabet.distance(from: alphabet.startIndex, to: index)

            var carry = digit
            for i in 0..<result.count {
                carry += Int(result[i]) * base
                result[i] = UInt8(carry % 256)
                carry /= 256
            }

            while carry > 0 {
                result.append(UInt8(carry % 256))
                carry /= 256
            }
        }

        let prefix = Array(repeating: UInt8(0), count: zerosCount)
        return Data(prefix + result.reversed())
    }
}
