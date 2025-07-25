//
//  PhantomWallet.swift
//  PhantomConnect
//
//  Created by Ayush Rai on 25/07/25.
//

import Foundation
import CryptoKit
import UIKit
import os
import Sodium

@objc
public class PhantomWallet: NSObject, @unchecked Sendable {

    @objc
    public static let shared: PhantomWallet = PhantomWallet()

    @objc public var isConnected: Bool = false
    @objc public var publicKey: String = ""
    @objc public var isLoading: Bool = false
    @objc public var errorMessage: String = ""

    private var session: String = ""
    private var dappKeyPair: Curve25519.KeyAgreement.PrivateKey
    private var sharedSecret: Data?
    private let logger = Logger(subsystem: "com.phantomconnect.app", category: "PhantomWallet")
    private let sodium = Sodium()

    private override init() {
        self.dappKeyPair = Curve25519.KeyAgreement.PrivateKey()
        super.init()
        logger.debug("PhantomWallet initialized")
    }
    
    // MARK: - Step 1: Connect to Phantom
    @objc
    public func connect(completion: @escaping @Sendable (Bool, String?) -> Void) {
        logger.debug("🚀 Starting connection to Phantom")

        guard let appURL = URL(string: "https://phantom.app/ul/v1/connect") else {
            let error = "Invalid Phantom URL"
            DispatchQueue.main.async {
                self.errorMessage = error
                self.logger.error("Invalid Phantom URL")
                completion(false, error)
            }
            return
        }

        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = ""
        }
        
        var components = URLComponents(url: appURL, resolvingAgainstBaseURL: false)!
        
        // Required parameters for Phantom connect
        let queryItems = [
            URLQueryItem(name: "app_url", value: "https://myapp.com".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)),
            URLQueryItem(name: "dapp_encryption_public_key", value: dappKeyPair.publicKey.rawRepresentation.base58EncodedString),
            URLQueryItem(name: "redirect_link", value: "phantomconnect://connected".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)),
            URLQueryItem(name: "cluster", value: "mainnet-beta")
        ]
        
        components.queryItems = queryItems
        
        guard let finalURL = components.url else {
            let error = "Failed to construct URL"
            DispatchQueue.main.async {
                self.errorMessage = error
                self.logger.error("Failed to construct URL")
                self.isLoading = false
                completion(false, error)
            }
            return
        }

        logger.debug("📱 Opening Phantom app with URL: \(finalURL.absoluteString)")

        UIApplication.shared.open(finalURL) { [weak self] success in
            DispatchQueue.main.async {
                if !success {
                    let error = "Failed to open Phantom app"
                    self?.errorMessage = error
                    self?.logger.error("Failed to open Phantom app")
                    self?.isLoading = false
                    completion(false, error)
                } else {
                    self?.logger.debug("✅ Successfully opened Phantom app")
                    completion(true, nil)
                }
            }
        }
    }
    
    // MARK: - Handle Connect Response
    @objc
    public func handleConnectResponse(url: URL, completion: @escaping @Sendable (Bool, String?, String?) -> Void) {
        logger.debug("📨 Handling connect response from URL: \(url.absoluteString)")

        DispatchQueue.main.async {
            self.isLoading = false
        }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            let error = "Invalid response URL"
            DispatchQueue.main.async {
                self.errorMessage = error
                self.logger.error("Invalid response URL")
                completion(false, nil, error)
            }
            return
        }
        
        let queryDict = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })

        logger.debug("📋 Query parameters: \(queryDict.keys.joined(separator: ", "))")

        // Check for errors
        if let errorCode = queryDict["errorCode"], let errorMessage = queryDict["errorMessage"] {
            let error = "Connection failed: \(errorMessage) (Code: \(errorCode))"
            DispatchQueue.main.async {
                self.errorMessage = error
                self.logger.error("Connection failed: \(errorMessage) (Code: \(errorCode))")
                completion(false, nil, error)
            }
            return
        }
        
        // Parse successful response
        guard let phantomPublicKeyBase58 = queryDict["phantom_encryption_public_key"],
              let nonceBase58 = queryDict["nonce"],
              let encryptedDataBase58 = queryDict["data"] else {
            let error = "Missing required response parameters"
            DispatchQueue.main.async {
                self.errorMessage = error
                self.logger.error("Missing required response parameters")
                completion(false, nil, error)
            }
            return
        }

        logger.debug("🔐 Starting decryption process...")

        do {
            // Get the required data for NaCl Box decryption
            guard let phantomPublicKeyData = Data(base58Encoded: phantomPublicKeyBase58),
                  let nonceData = Data(base58Encoded: nonceBase58),
                  let encryptedDataBytes = Data(base58Encoded: encryptedDataBase58)
            else {
                throw PhantomError.invalidResponse
            }

            // Convert keys to format compatible with Sodium
            let dappPrivateKeyBytes = Array(dappKeyPair.rawRepresentation)
            let phantomPublicKeyBytes = Array(phantomPublicKeyData)
            let nonceBytes = Array(nonceData)
            let encryptedBytes = Array(encryptedDataBytes)

            logger.debug("🔍 NaCl Box decryption details:")
            logger.debug("   Dapp private key length: \(dappPrivateKeyBytes.count)")
            logger.debug("   Phantom public key length: \(phantomPublicKeyBytes.count)")
            logger.debug("   Nonce length: \(nonceBytes.count)")
            logger.debug("   Encrypted data length: \(encryptedBytes.count)")


            // Use NaCl Box.open for decryption (matching Android implementation)
            guard let decryptedBytes = self.sodium.box.open(authenticatedCipherText: encryptedBytes,
                                                       senderPublicKey: phantomPublicKeyBytes,
                                                       recipientSecretKey: dappPrivateKeyBytes,
                                                       nonce: nonceBytes)
            else {
                throw PhantomError.invalidResponse
            }

            let decryptedData = Data(decryptedBytes)

            // Now create shared secret for future operations (like Android does)
            guard let naclSharedSecret = self.sodium.box.beforenm(recipientPublicKey: phantomPublicKeyBytes,
                                                             senderSecretKey: dappPrivateKeyBytes)
            else {
                throw PhantomError.invalidResponse
            }
            self.sharedSecret = Data(naclSharedSecret)

            logger.debug("✅ NaCl Box decryption successful")

            // Parse the decrypted JSON
            if let json = try JSONSerialization.jsonObject(with: decryptedData) as? [String: Any],
               let publicKey = json["public_key"] as? String,
               let session = json["session"] as? String {

                logger.debug("✅ JSON parsing successful - PublicKey: \(publicKey)")

                DispatchQueue.main.async {
                    self.publicKey = publicKey
                    self.session = session
                    self.isConnected = true
                    self.errorMessage = ""
                    self.logger.debug("🎉 Connection completed successfully!")
                    completion(true, publicKey, nil)
                }
            } else {
                let error = "Failed to parse connection response - Invalid JSON structure"
                DispatchQueue.main.async {
                    self.errorMessage = error
                    self.logger.error("Failed to parse connection response - Invalid JSON structure")
                    completion(false, nil, error)
                }
            }
        } catch {
            let errorMsg = "Failed to decrypt response: \(error.localizedDescription) (\(type(of: error)))"
            DispatchQueue.main.async {
                self.errorMessage = errorMsg
                self.logger.error("Failed to decrypt response: \(error.localizedDescription) (\(type(of: error)))")
                completion(false, nil, errorMsg)
            }
        }
    }
    
    // MARK: - Step 2: Sign Message
    @objc
    public func signMessage(_ message: String, completion: @escaping @Sendable (Bool, String?) -> Void) {
        guard isConnected, !session.isEmpty else {
            let error = "Not connected to Phantom"
            DispatchQueue.main.async {
                self.errorMessage = error
                self.logger.error("Not connected to Phantom")
                completion(false, error)
            }
            return
        }
        
        guard let appURL = URL(string: "https://phantom.app/ul/v1/signMessage") else {
            let error = "Invalid Phantom URL"
            DispatchQueue.main.async {
                self.errorMessage = error
                self.logger.error("Invalid Phantom URL")
                completion(false, error)
            }
            return
        }

        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = ""
        }
        
        do {
            // Prepare the payload
            let messageData = message.data(using: .utf8)!
            let messageBase58 = messageData.base58EncodedString
            
            let payload = [
                "message": messageBase58,
                "session": session,
                "display": "utf8"
            ]
            
            let payloadData = try JSONSerialization.data(withJSONObject: payload)
            let encryptedPayload = try encryptPayload(payloadData)
            
            var components = URLComponents(url: appURL, resolvingAgainstBaseURL: false)!
            
            let queryItems = [
                URLQueryItem(name: "dapp_encryption_public_key", value: dappKeyPair.publicKey.rawRepresentation.base58EncodedString),
                URLQueryItem(name: "nonce", value: encryptedPayload.nonce),
                URLQueryItem(name: "redirect_link", value: "phantomconnect://signed".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)),
                URLQueryItem(name: "payload", value: encryptedPayload.data)
            ]
            
            components.queryItems = queryItems
            
            guard let finalURL = components.url else {
                let error = "Failed to construct URL"
                DispatchQueue.main.async {
                    self.errorMessage = error
                    self.logger.error("Failed to construct URL")
                    self.isLoading = false
                    completion(false, error)
                }
                return
            }
            
            UIApplication.shared.open(finalURL) { [weak self] success in
                DispatchQueue.main.async {
                    if !success {
                        let error = "Failed to open Phantom app"
                        self?.errorMessage = error
                        self?.isLoading = false
                        completion(false, error)
                    } else {
                        completion(true, nil)
                    }
                }
            }
        } catch {
            let errorMsg = "Failed to prepare message: \(error.localizedDescription)"
            DispatchQueue.main.async {
                self.errorMessage = errorMsg
                self.logger.error("Failed to prepare message: \(error.localizedDescription)")
                self.isLoading = false
                completion(false, errorMsg)
            }
        }
    }
    
    // MARK: - Handle Sign Response
    @objc
    public func handleSignResponse(url: URL, completion: @escaping @Sendable (String?, String?) -> Void) {
        DispatchQueue.main.async {
            self.isLoading = false
        }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            let error = "Invalid response URL"
            DispatchQueue.main.async {
                self.errorMessage = error
                self.logger.error("Invalid response URL")
                completion(nil, error)
            }
            return
        }
        
        let queryDict = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
        
        // Check for errors
        if let errorCode = queryDict["errorCode"], let errorMessage = queryDict["errorMessage"] {
            let error = "Signing failed: \(errorMessage) (Code: \(errorCode))"
            DispatchQueue.main.async {
                self.errorMessage = error
                self.logger.error("Signing failed: \(errorMessage) (Code: \(errorCode))")
                completion(nil, error)
            }
            return
        }
        
        // Parse successful response
        guard let nonceBase58 = queryDict["nonce"],
              let encryptedDataBase58 = queryDict["data"] else {
            let error = "Missing required response parameters"
            DispatchQueue.main.async {
                self.errorMessage = error
                self.logger.error("Missing required response parameters")
                completion(nil, error)
            }
            return
        }
        
        do {
            let decryptedData = try decryptPayload(
                encryptedData: encryptedDataBase58,
                nonce: nonceBase58
            )
            
            if let json = try JSONSerialization.jsonObject(with: decryptedData) as? [String: Any],
               let signature = json["signature"] as? String {
                DispatchQueue.main.async {
                    completion(signature, nil)
                }
            } else {
                let error = "Failed to parse signature response"
                DispatchQueue.main.async {
                    self.errorMessage = error
                    self.logger.error("Failed to parse signature response")
                    completion(nil, error)
                }
            }
        } catch {
            let errorMsg = "Failed to decrypt response: \(error.localizedDescription)"
            DispatchQueue.main.async {
                self.errorMessage = errorMsg
                self.logger.error("Failed to decrypt response: \(error.localizedDescription)")
                completion(nil, errorMsg)
            }
        }
    }
    
    // MARK: - Encryption/Decryption Helpers
    private func encryptPayload(_ data: Data) throws -> (data: String, nonce: String) {
        guard let sharedSecret = sharedSecret else {
            throw PhantomError.noSharedSecret
        }

        // Generate a random 24-byte nonce for NaCl SecretBox (matching Android)
        guard let nonce = self.sodium.randomBytes.buf(length: self.sodium.secretBox.NonceBytes) else {
            throw PhantomError.invalidResponse
        }

        logger.debug("🔐 Encrypting payload with SecretBox:")
        logger.debug("   Message length: \(data.count)")
        logger.debug("   Nonce length: \(nonce.count)")
        logger.debug("   Shared secret length: \(sharedSecret.count)")


        // Encrypt using NaCl SecretBox with shared secret as key (matching Android)
        guard let encrypted = self.sodium.secretBox.seal(
            message: Array(data),
            secretKey: Array(sharedSecret),
            nonce: nonce
        )
        else {
            throw PhantomError.invalidResponse
        }

        logger.debug("✅ SecretBox encryption successful, encrypted length: \(encrypted.count)")

        return (
            data: Data(encrypted).base58EncodedString,
            nonce: Data(nonce).base58EncodedString
        )
    }

    private func decryptPayload(encryptedData: String, nonce: String) throws -> Data {
        guard let sharedSecret = sharedSecret else {
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

        // Try method 1: Use separate nonce and ciphertext (matching Android EncryptionUtils)
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
    
    // MARK: - Disconnect
    @objc
    public func disconnect() {
        DispatchQueue.main.async {
            self.isConnected = false
            self.publicKey = ""
            self.session = ""
            self.sharedSecret = nil
            self.errorMessage = ""
        }
    }

    // MARK: - Utility Methods
    @objc
    public func handleDeeplink(_ url: URL) -> Bool {
        let urlString = url.absoluteString
        if urlString.contains("phantomconnect://connected") {
            handleConnectResponse(url: url) { success, publicKey, error in
                // Handle response in completion block
            }
            return true
        } else if urlString.contains("phantomconnect://signed") {
            handleSignResponse(url: url) { signature, error in
                // Handle response in completion block
            }
            return true
        }
        return false
    }
}

// MARK: - Custom Errors
@objc
public enum PhantomError: Int, Error {
    case noSharedSecret = 1
    case invalidResponse = 2
}

// MARK: - Base58 Encoding Extension
extension Data {
    var base58EncodedString: String {
        return Base58.encode(self)
    }
    
    init?(base58Encoded string: String) {
        guard let data = Base58.decode(string) else { return nil }
        self = data
    }
}

// MARK: - Base58 Implementation
struct Base58 {
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
            guard let index = alphabet.firstIndex(of: char) else { return nil }
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
