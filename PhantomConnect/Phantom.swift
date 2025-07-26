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
import TweetNacl

@objc
public class Phantom: NSObject, @unchecked Sendable {

    @objc
    public static let shared: Phantom = Phantom()

    private var dappKeyPair: Curve25519.KeyAgreement.PrivateKey
    private let logger = Logger(subsystem: "com.phantomconnect.app", category: "Phantom")
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

    private override init() {
        self.dappKeyPair = Curve25519.KeyAgreement.PrivateKey()
        super.init()
        logger.debug("Phantom initialized")
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

    private func setDappPublicKey(_ key: String) {
        userDefaults.set(key, forKey: Keys.dappPublicKey)
    }

    private func setDappPrivateKey(_ key: Data) {
        userDefaults.set(key, forKey: Keys.dappPrivateKey)
    }

    private var isConnected: Bool {
        return userDefaults.bool(forKey: Keys.isConnected)
    }

    private var session: String {
        return userDefaults.string(forKey: Keys.session) ?? ""
    }

    private var sharedSecret: Data? {
        return userDefaults.data(forKey: Keys.sharedSecret)
    }

    // MARK: - Step 1: Connect to Phantom
    @objc
    public func connect(completion: @escaping @Sendable (Bool, String?) -> Void) {
        logger.debug("🚀 Starting connection to Phantom")

        guard let appURL = URL(string: "https://phantom.app/ul/v1/connect") else {
            let error = "Invalid Phantom URL"
            DispatchQueue.main.async {
                self.setError(error)
                self.logger.error("Invalid Phantom URL")
                completion(false, error)
            }
            return
        }

        DispatchQueue.main.async {
            self.setLoading(true)
            self.clearError()
        }

        var components = URLComponents(url: appURL, resolvingAgainstBaseURL: false)!

        // Store dapp public key for later use
        setDappPublicKey(dappKeyPair.publicKey.rawRepresentation.phantomBase58EncodedString)
        setDappPrivateKey(dappKeyPair.rawRepresentation)

        // Required parameters for Phantom connect
        let queryItems = [
            URLQueryItem(name: "app_url", value: "https://myapp.com".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)),
            URLQueryItem(name: "dapp_encryption_public_key", value: dappKeyPair.publicKey.rawRepresentation.phantomBase58EncodedString),
            URLQueryItem(name: "redirect_link", value: "phantomconnect://connected".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)),
            URLQueryItem(name: "cluster", value: "mainnet-beta")
        ]

        components.queryItems = queryItems

        guard let finalURL = components.url else {
            let error = "Failed to construct URL"
            DispatchQueue.main.async {
                self.setError(error)
                self.logger.error("Failed to construct URL")
                self.setLoading(false)
                completion(false, error)
            }
            return
        }

        logger.debug("📱 Opening Phantom app with URL: \(finalURL.absoluteString)")

        UIApplication.shared.open(finalURL) { [weak self] success in
            DispatchQueue.main.async {
                if !success {
                    let error = "Failed to open Phantom app"
                    self?.setError(error)
                    self?.logger.error("Failed to open Phantom app")
                    self?.setLoading(false)
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
        guard isConnected, !session.isEmpty else {
            let error = "Not connected to Phantom"
            DispatchQueue.main.async {
                self.setError(error)
                self.logger.error("Not connected to Phantom")
                completion(false, error)
            }
            return
        }

        guard let appURL = URL(string: "https://phantom.app/ul/v1/signMessage") else {
            let error = "Invalid Phantom URL"
            DispatchQueue.main.async {
                self.setError(error)
                self.logger.error("Invalid Phantom URL")
                completion(false, error)
            }
            return
        }

        DispatchQueue.main.async {
            self.setLoading(true)
            self.clearError()
        }

        do {
            // Prepare the payload
            let messageData = message.data(using: .utf8)!
            let messageBase58 = messageData.phantomBase58EncodedString

            let payload = [
                "message": messageBase58,
                "session": session,
                "display": "utf8"
            ]

            let payloadData = try JSONSerialization.data(withJSONObject: payload)
            let encryptedPayload = try encryptPayload(payloadData)

            var components = URLComponents(url: appURL, resolvingAgainstBaseURL: false)!

            let dappPublicKey = userDefaults.string(forKey: Keys.dappPublicKey) ?? ""
            let queryItems = [
                URLQueryItem(name: "dapp_encryption_public_key", value: dappPublicKey),
                URLQueryItem(name: "nonce", value: encryptedPayload.nonce),
                URLQueryItem(name: "redirect_link", value: "phantomconnect://signed".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)),
                URLQueryItem(name: "payload", value: encryptedPayload.data)
            ]

            components.queryItems = queryItems

            guard let finalURL = components.url else {
                let error = "Failed to construct URL"
                DispatchQueue.main.async {
                    self.setError(error)
                    self.logger.error("Failed to construct URL")
                    self.setLoading(false)
                    completion(false, error)
                }
                return
            }

            UIApplication.shared.open(finalURL) { [weak self] success in
                DispatchQueue.main.async {
                    if !success {
                        let error = "Failed to open Phantom app"
                        self?.setError(error)
                        self?.setLoading(false)
                        completion(false, error)
                    } else {
                        completion(true, nil)
                    }
                }
            }
        } catch {
            let errorMsg = "Failed to prepare message: \(error.localizedDescription)"
            DispatchQueue.main.async {
                self.setError(errorMsg)
                self.logger.error("Failed to prepare message: \(error.localizedDescription)")
                self.setLoading(false)
                completion(false, errorMsg)
            }
        }
    }

    // MARK: - Encryption Helper
    private func encryptPayload(_ data: Data) throws -> (data: String, nonce: String) {
        guard let sharedSecret = self.sharedSecret else {
            throw PhantomError.noSharedSecret
        }

        // Generate a random 24-byte nonce for NaCl SecretBox
        let nonce = Data((0..<24).map { _ in
            UInt8.random(in: 0...255)
        })

        logger.debug("🔐 Encrypting payload with SecretBox:")
        logger.debug("   Message length: \(data.count)")
        logger.debug("   Nonce length: \(nonce.count)")
        logger.debug("   Shared secret length: \(sharedSecret.count)")

        // Encrypt using NaCl SecretBox with shared secret as key
        let encrypted = try NaclSecretBox.secretBox(message: data, nonce: nonce, key: sharedSecret)

        logger.debug("✅ SecretBox encryption successful, encrypted length: \(encrypted.count)")

        return (
            data: encrypted.phantomBase58EncodedString,
            nonce: nonce.phantomBase58EncodedString
        )
    }

    // MARK: - Disconnect
    @objc
    public func disconnect() {
        setConnected(false)
        setPublicKey("")
        userDefaults.set("", forKey: Keys.signature)
        userDefaults.set("", forKey: Keys.errorMessage)
        userDefaults.set("", forKey: Keys.session)
        userDefaults.removeObject(forKey: Keys.sharedSecret)
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
    var phantomBase58EncodedString: String {
        return PhantomBase58.encode(self)
    }

    init?(phantomBase58Encoded string: String) {
        guard let data = PhantomBase58.decode(string) else {
            return nil
        }
        self = data
    }
}

// MARK: - Base58 Implementation
struct PhantomBase58 {
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