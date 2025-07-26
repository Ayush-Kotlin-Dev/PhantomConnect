//
//  Phantom.swift
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
public class Phantom: NSObject, @unchecked Sendable {

    @objc
    public static let shared: Phantom = Phantom()

    private var dappKeyPair: Curve25519.KeyAgreement.PrivateKey
    private let logger = Logger(subsystem: "com.phantomconnect.app", category: "Phantom")

    private override init() {
        self.dappKeyPair = Curve25519.KeyAgreement.PrivateKey()
        super.init()
        logger.debug("Phantom initialized")
    }

    // MARK: - Step 1: Connect to Phantom
    @objc
    public func connect(completion: @escaping @Sendable (Bool, String?) -> Void) {
        logger.debug("🚀 Starting connection to Phantom")

        guard let appURL = URL(string: "https://phantom.app/ul/v1/connect") else {
            let error = "Invalid Phantom URL"
            DispatchQueue.main.async {
                PhantomState.shared.setError(error)
                self.logger.error("Invalid Phantom URL")
                completion(false, error)
            }
            return
        }

        DispatchQueue.main.async {
            PhantomState.shared.setLoading(true)
            PhantomState.shared.clearError()
        }

        var components = URLComponents(url: appURL, resolvingAgainstBaseURL: false)!

        // Store dapp public key for later use
        PhantomState.shared.setDappPublicKey(dappKeyPair.publicKey.rawRepresentation.base58EncodedString)
        PhantomState.shared.setDappPrivateKey(dappKeyPair.rawRepresentation)

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
                PhantomState.shared.setError(error)
                self.logger.error("Failed to construct URL")
                PhantomState.shared.setLoading(false)
                completion(false, error)
            }
            return
        }

        logger.debug("📱 Opening Phantom app with URL: \(finalURL.absoluteString)")

        UIApplication.shared.open(finalURL) { [weak self] success in
            DispatchQueue.main.async {
                if !success {
                    let error = "Failed to open Phantom app"
                    PhantomState.shared.setError(error)
                    self?.logger.error("Failed to open Phantom app")
                    PhantomState.shared.setLoading(false)
                    completion(false, error)
                } else {
                    self?.logger.debug("✅ Successfully opened Phantom app")
                    completion(true, nil)
                }
            }
        }
    }

    // MARK: - Step 2: Sign Message
    @objc
    public func signMessage(_ message: String, completion: @escaping @Sendable (Bool, String?) -> Void) {
        guard PhantomState.shared.isConnected, !PhantomState.shared.session.isEmpty else {
            let error = "Not connected to Phantom"
            DispatchQueue.main.async {
                PhantomState.shared.setError(error)
                self.logger.error("Not connected to Phantom")
                completion(false, error)
            }
            return
        }

        guard let appURL = URL(string: "https://phantom.app/ul/v1/signMessage") else {
            let error = "Invalid Phantom URL"
            DispatchQueue.main.async {
                PhantomState.shared.setError(error)
                self.logger.error("Invalid Phantom URL")
                completion(false, error)
            }
            return
        }

        DispatchQueue.main.async {
            PhantomState.shared.setLoading(true)
            PhantomState.shared.clearError()
        }

        do {
            // Prepare the payload
            let messageData = message.data(using: .utf8)!
            let messageBase58 = messageData.base58EncodedString

            let payload = [
                "message": messageBase58,
                "session": PhantomState.shared.session,
                "display": "utf8"
            ]

            let payloadData = try JSONSerialization.data(withJSONObject: payload)
            let encryptedPayload = try encryptPayload(payloadData)

            var components = URLComponents(url: appURL, resolvingAgainstBaseURL: false)!

            let queryItems = [
                URLQueryItem(name: "dapp_encryption_public_key", value: PhantomState.shared.dappPublicKey),
                URLQueryItem(name: "nonce", value: encryptedPayload.nonce),
                URLQueryItem(name: "redirect_link", value: "phantomconnect://signed".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)),
                URLQueryItem(name: "payload", value: encryptedPayload.data)
            ]

            components.queryItems = queryItems

            guard let finalURL = components.url else {
                let error = "Failed to construct URL"
                DispatchQueue.main.async {
                    PhantomState.shared.setError(error)
                    self.logger.error("Failed to construct URL")
                    PhantomState.shared.setLoading(false)
                    completion(false, error)
                }
                return
            }

            UIApplication.shared.open(finalURL) { [weak self] success in
                DispatchQueue.main.async {
                    if !success {
                        let error = "Failed to open Phantom app"
                        PhantomState.shared.setError(error)
                        PhantomState.shared.setLoading(false)
                        completion(false, error)
                    } else {
                        completion(true, nil)
                    }
                }
            }
        } catch {
            let errorMsg = "Failed to prepare message: \(error.localizedDescription)"
            DispatchQueue.main.async {
                PhantomState.shared.setError(errorMsg)
                self.logger.error("Failed to prepare message: \(error.localizedDescription)")
                PhantomState.shared.setLoading(false)
                completion(false, errorMsg)
            }
        }
    }

    // MARK: - Encryption Helper
    private func encryptPayload(_ data: Data) throws -> (data: String, nonce: String) {
        guard let sharedSecret = PhantomState.shared.sharedSecret else {
            throw PhantomError.noSharedSecret
        }

        let sodium = Sodium()

        // Generate a random 24-byte nonce for NaCl SecretBox
        guard let nonce = sodium.randomBytes.buf(length: sodium.secretBox.NonceBytes) else {
            throw PhantomError.invalidResponse
        }

        logger.debug("🔐 Encrypting payload with SecretBox:")
        logger.debug("   Message length: \(data.count)")
        logger.debug("   Nonce length: \(nonce.count)")
        logger.debug("   Shared secret length: \(sharedSecret.count)")

        // Encrypt using NaCl SecretBox with shared secret as key
        guard let encrypted = sodium.secretBox.seal(
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

    // MARK: - Disconnect
    @objc
    public func disconnect() {
        PhantomState.shared.disconnect()
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
        guard let data = Base58.decode(string) else {
            return nil
        }
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