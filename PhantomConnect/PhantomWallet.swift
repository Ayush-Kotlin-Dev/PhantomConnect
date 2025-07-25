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

class PhantomWallet: ObservableObject {
    @Published var isConnected = false
    @Published var publicKey: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String = ""
    
    private var session: String = ""
    private var dappKeyPair: Curve25519.KeyAgreement.PrivateKey
    private var sharedSecret: Data?
    private let logger = Logger(subsystem: "com.phantomconnect.app", category: "PhantomWallet")
    private let sodium = Sodium()
    
    init() {
        self.dappKeyPair = Curve25519.KeyAgreement.PrivateKey()
        logger.debug("PhantomWallet initialized")
        print("DEBUG: PhantomWallet initialized")
    }
    
    // MARK: - Step 1: Connect to Phantom
    func connect() {
        logger.debug("🚀 Starting connection to Phantom")
        print("DEBUG: 🚀 Starting connection to Phantom")

        guard let appURL = URL(string: "https://phantom.app/ul/v1/connect") else {
            errorMessage = "Invalid Phantom URL"
            logger.error("Invalid Phantom URL")
            print("ERROR: Invalid Phantom URL")
            return
        }
        
        isLoading = true
        errorMessage = ""
        
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
            errorMessage = "Failed to construct URL"
            logger.error("Failed to construct URL")
            print("ERROR: Failed to construct URL")
            isLoading = false
            return
        }

        logger.debug("📱 Opening Phantom app with URL: \(finalURL.absoluteString)")
        print("DEBUG: 📱 Opening Phantom app with URL: \(finalURL.absoluteString)")

        UIApplication.shared.open(finalURL) { [weak self] success in
            DispatchQueue.main.async {
                if !success {
                    self?.errorMessage = "Failed to open Phantom app"
                    self?.logger.error("Failed to open Phantom app")
                    print("ERROR: Failed to open Phantom app")
                    self?.isLoading = false
                } else {
                    self?.logger.debug("✅ Successfully opened Phantom app")
                    print("DEBUG: ✅ Successfully opened Phantom app")
                }
            }
        }
    }
    
    // MARK: - Handle Connect Response
    func handleConnectResponse(url: URL) {
        logger.debug("📨 Handling connect response from URL: \(url.absoluteString)")
        print("DEBUG: 📨 Handling connect response from URL: \(url.absoluteString)")

        isLoading = false
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            errorMessage = "Invalid response URL"
            logger.error("Invalid response URL")
            print("ERROR: Invalid response URL")
            return
        }
        
        let queryDict = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })

        logger.debug("📋 Query parameters: \(queryDict.keys.joined(separator: ", "))")
        print("DEBUG: 📋 Query parameters: \(queryDict.keys.joined(separator: ", "))")

        // Check for errors
        if let errorCode = queryDict["errorCode"], let errorMessage = queryDict["errorMessage"] {
            self.errorMessage = "Connection failed: \(errorMessage) (Code: \(errorCode))"
            logger.error("Connection failed: \(errorMessage) (Code: \(errorCode))")
            print("ERROR: Connection failed: \(errorMessage) (Code: \(errorCode))")
            return
        }
        
        // Parse successful response
        guard let phantomPublicKeyBase58 = queryDict["phantom_encryption_public_key"],
              let nonceBase58 = queryDict["nonce"],
              let encryptedDataBase58 = queryDict["data"] else {
            errorMessage = "Missing required response parameters"
            logger.error("Missing required response parameters")
            print("ERROR: Missing required response parameters")
            return
        }

        logger.debug("🔐 Starting decryption process...")
        print("DEBUG: 🔐 Starting decryption process...")

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

            print("DEBUG: 🔍 NaCl Box decryption details:")
            print("DEBUG:    Dapp private key length: \(dappPrivateKeyBytes.count)")
            print("DEBUG:    Phantom public key length: \(phantomPublicKeyBytes.count)")
            print("DEBUG:    Nonce length: \(nonceBytes.count)")
            print("DEBUG:    Encrypted data length: \(encryptedBytes.count)")

            // Use NaCl Box.open for decryption (matching Android implementation)
            guard let decryptedBytes = sodium.box.open(authenticatedCipherText: encryptedBytes,
                                                       senderPublicKey: phantomPublicKeyBytes,
                                                       recipientSecretKey: dappPrivateKeyBytes,
                                                       nonce: nonceBytes)
            else {
                throw PhantomError.invalidResponse
            }

            let decryptedData = Data(decryptedBytes)

            // Now create shared secret for future operations (like Android does)
            guard let naclSharedSecret = sodium.box.beforenm(recipientPublicKey: phantomPublicKeyBytes,
                                                             senderSecretKey: dappPrivateKeyBytes)
            else {
                throw PhantomError.invalidResponse
            }
            self.sharedSecret = Data(naclSharedSecret)

            logger.debug("✅ NaCl Box decryption successful")
            print("DEBUG: ✅ NaCl Box decryption successful")

            // Parse the decrypted JSON
            if let json = try JSONSerialization.jsonObject(with: decryptedData) as? [String: Any],
               let publicKey = json["public_key"] as? String,
               let session = json["session"] as? String {

                logger.debug("✅ JSON parsing successful - PublicKey: \(publicKey)")
                print("DEBUG: ✅ JSON parsing successful - PublicKey: \(publicKey)")

                DispatchQueue.main.async {
                    self.publicKey = publicKey
                    self.session = session
                    self.isConnected = true
                    self.errorMessage = ""
                    self.logger.debug("🎉 Connection completed successfully!")
                    print("DEBUG: 🎉 Connection completed successfully!")
                }
            } else {
                errorMessage = "Failed to parse connection response - Invalid JSON structure"
                logger.error("Failed to parse connection response - Invalid JSON structure")
                print("ERROR: Failed to parse connection response - Invalid JSON structure")
            }
        } catch {
            errorMessage = "Failed to decrypt response: \(error.localizedDescription) (\(type(of: error)))"
            logger.error("Failed to decrypt response: \(error.localizedDescription) (\(type(of: error)))")
            print("ERROR: Failed to decrypt response: \(error.localizedDescription) (\(type(of: error)))")
        }
    }
    
    // MARK: - Step 2: Sign Message
    func signMessage(_ message: String) {
        guard isConnected, !session.isEmpty else {
            errorMessage = "Not connected to Phantom"
            logger.error("Not connected to Phantom")
            print("ERROR: Not connected to Phantom")
            return
        }
        
        guard let appURL = URL(string: "https://phantom.app/ul/v1/signMessage") else {
            errorMessage = "Invalid Phantom URL"
            logger.error("Invalid Phantom URL")
            print("ERROR: Invalid Phantom URL")
            return
        }
        
        isLoading = true
        errorMessage = ""
        
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
                errorMessage = "Failed to construct URL"
                logger.error("Failed to construct URL")
                print("ERROR: Failed to construct URL")
                isLoading = false
                return
            }
            
            UIApplication.shared.open(finalURL) { [weak self] success in
                DispatchQueue.main.async {
                    if !success {
                        self?.errorMessage = "Failed to open Phantom app"
                        self?.isLoading = false
                    }
                }
            }
        } catch {
            errorMessage = "Failed to prepare message: \(error.localizedDescription)"
            logger.error("Failed to prepare message: \(error.localizedDescription)")
            print("ERROR: Failed to prepare message: \(error.localizedDescription)")
            isLoading = false
        }
    }
    
    // MARK: - Handle Sign Response
    func handleSignResponse(url: URL) -> String? {
        isLoading = false
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            errorMessage = "Invalid response URL"
            logger.error("Invalid response URL")
            print("ERROR: Invalid response URL")
            return nil
        }
        
        let queryDict = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
        
        // Check for errors
        if let errorCode = queryDict["errorCode"], let errorMessage = queryDict["errorMessage"] {
            self.errorMessage = "Signing failed: \(errorMessage) (Code: \(errorCode))"
            logger.error("Signing failed: \(errorMessage) (Code: \(errorCode))")
            print("ERROR: Signing failed: \(errorMessage) (Code: \(errorCode))")
            return nil
        }
        
        // Parse successful response
        guard let nonceBase58 = queryDict["nonce"],
              let encryptedDataBase58 = queryDict["data"] else {
            errorMessage = "Missing required response parameters"
            logger.error("Missing required response parameters")
            print("ERROR: Missing required response parameters")
            return nil
        }
        
        do {
            let decryptedData = try decryptPayload(
                encryptedData: encryptedDataBase58,
                nonce: nonceBase58
            )
            
            if let json = try JSONSerialization.jsonObject(with: decryptedData) as? [String: Any],
               let signature = json["signature"] as? String {
                return signature
            } else {
                errorMessage = "Failed to parse signature response"
                logger.error("Failed to parse signature response")
                print("ERROR: Failed to parse signature response")
                return nil
            }
        } catch {
            errorMessage = "Failed to decrypt response: \(error.localizedDescription)"
            logger.error("Failed to decrypt response: \(error.localizedDescription)")
            print("ERROR: Failed to decrypt response: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Encryption/Decryption Helpers
    private func encryptPayload(_ data: Data) throws -> (data: String, nonce: String) {
        guard let sharedSecret = sharedSecret else {
            throw PhantomError.noSharedSecret
        }

        // Generate a random 24-byte nonce for NaCl SecretBox
        guard let nonce = sodium.randomBytes.buf(length: 24) else {
            throw PhantomError.invalidResponse
        }

        // Encrypt using NaCl SecretBox with shared secret as key (matching Android)
        guard let encrypted = sodium.secretBox.seal(
            message: Array(data),
            secretKey: Array(sharedSecret),
            nonce: nonce
        )
        else {
            throw PhantomError.invalidResponse
        }

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

        print("DEBUG: 🔍 NaCl SecretBox decryption details:")
        print("DEBUG:    Nonce length: \(nonceData.count)")
        print("DEBUG:    Encrypted data length: \(encryptedDataBytes.count)")
        print("DEBUG:    Shared secret length: \(sharedSecret.count)")

        // Use NaCl SecretBox to decrypt with shared secret as key (matching Android)
        guard let decrypted = sodium.secretBox.open(
            nonceAndAuthenticatedCipherText: Array(encryptedDataBytes),
            secretKey: Array(sharedSecret)
        )
        else {
            throw PhantomError.invalidResponse
        }

        logger.debug("✅ NaCl SecretBox decryption successful")
        print("DEBUG: ✅ NaCl SecretBox decryption successful")

        return Data(decrypted)
    }
    
    // MARK: - Disconnect
    func disconnect() {
        isConnected = false
        publicKey = ""
        session = ""
        sharedSecret = nil
        errorMessage = ""
    }
}

// MARK: - Custom Errors
enum PhantomError: Error {
    case noSharedSecret
    case invalidResponse
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
