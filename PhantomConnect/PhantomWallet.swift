//
//  PhantomWallet.swift
//  PhantomConnect
//
//  Created by Ayush Rai on 25/07/25.
//

import Foundation
import CryptoKit
import UIKit

class PhantomWallet: ObservableObject {
    @Published var isConnected = false
    @Published var publicKey: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String = ""
    
    private var session: String = ""
    private var dappKeyPair: Curve25519.KeyAgreement.PrivateKey
    private var sharedSecret: SymmetricKey?
    
    init() {
        self.dappKeyPair = Curve25519.KeyAgreement.PrivateKey()
    }
    
    // MARK: - Step 1: Connect to Phantom
    func connect() {
        guard let appURL = URL(string: "https://phantom.app/ul/v1/connect") else {
            errorMessage = "Invalid Phantom URL"
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
    }
    
    // MARK: - Handle Connect Response
    func handleConnectResponse(url: URL) {
        isLoading = false
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            errorMessage = "Invalid response URL"
            return
        }
        
        let queryDict = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
        
        // Check for errors
        if let errorCode = queryDict["errorCode"], let errorMessage = queryDict["errorMessage"] {
            self.errorMessage = "Connection failed: \(errorMessage) (Code: \(errorCode))"
            return
        }
        
        // Parse successful response
        guard let phantomPublicKeyBase58 = queryDict["phantom_encryption_public_key"],
              let nonceBase58 = queryDict["nonce"],
              let encryptedDataBase58 = queryDict["data"] else {
            errorMessage = "Missing required response parameters"
            return
        }
        
        do {
            // Decrypt the response
            let decryptedData = try decryptPayload(
                encryptedData: encryptedDataBase58,
                nonce: nonceBase58,
                phantomPublicKey: phantomPublicKeyBase58
            )
            
            // Parse the decrypted JSON
            if let json = try JSONSerialization.jsonObject(with: decryptedData) as? [String: Any],
               let publicKey = json["public_key"] as? String,
               let session = json["session"] as? String {
                
                DispatchQueue.main.async {
                    self.publicKey = publicKey
                    self.session = session
                    self.isConnected = true
                    self.errorMessage = ""
                }
            } else {
                errorMessage = "Failed to parse connection response"
            }
        } catch {
            errorMessage = "Failed to decrypt response: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Step 2: Sign Message
    func signMessage(_ message: String) {
        guard isConnected, !session.isEmpty else {
            errorMessage = "Not connected to Phantom"
            return
        }
        
        guard let appURL = URL(string: "https://phantom.app/ul/v1/signMessage") else {
            errorMessage = "Invalid Phantom URL"
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
            isLoading = false
        }
    }
    
    // MARK: - Handle Sign Response
    func handleSignResponse(url: URL) -> String? {
        isLoading = false
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            errorMessage = "Invalid response URL"
            return nil
        }
        
        let queryDict = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
        
        // Check for errors
        if let errorCode = queryDict["errorCode"], let errorMessage = queryDict["errorMessage"] {
            self.errorMessage = "Signing failed: \(errorMessage) (Code: \(errorCode))"
            return nil
        }
        
        // Parse successful response
        guard let nonceBase58 = queryDict["nonce"],
              let encryptedDataBase58 = queryDict["data"] else {
            errorMessage = "Missing required response parameters"
            return nil
        }
        
        do {
            let decryptedData = try decryptPayload(
                encryptedData: encryptedDataBase58,
                nonce: nonceBase58,
                phantomPublicKey: nil // Use existing shared secret
            )
            
            if let json = try JSONSerialization.jsonObject(with: decryptedData) as? [String: Any],
               let signature = json["signature"] as? String {
                return signature
            } else {
                errorMessage = "Failed to parse signature response"
                return nil
            }
        } catch {
            errorMessage = "Failed to decrypt response: \(error.localizedDescription)"
            return nil
        }
    }
    
    // MARK: - Encryption/Decryption Helpers
    private func encryptPayload(_ data: Data) throws -> (data: String, nonce: String) {
        guard let sharedSecret = sharedSecret else {
            throw PhantomError.noSharedSecret
        }
        
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: sharedSecret, nonce: nonce)
        
        return (
            data: sealedBox.ciphertext.base58EncodedString,
            nonce: Data(nonce).base58EncodedString
        )
    }
    
    private func decryptPayload(encryptedData: String, nonce: String, phantomPublicKey: String?) throws -> Data {
        // If phantom public key is provided, create shared secret
        if let phantomPublicKeyBase58 = phantomPublicKey {
            let phantomPublicKeyData = Data(base58Encoded: phantomPublicKeyBase58)!
            let phantomPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: phantomPublicKeyData)
            let sharedSecretData = try dappKeyPair.sharedSecretFromKeyAgreement(with: phantomPublicKey)
            self.sharedSecret = SymmetricKey(data: sharedSecretData)
        }
        
        guard let sharedSecret = sharedSecret else {
            throw PhantomError.noSharedSecret
        }
        
        let nonceData = Data(base58Encoded: nonce)!
        let encryptedDataBytes = Data(base58Encoded: encryptedData)!
        
        let sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonceData), ciphertext: encryptedDataBytes, tag: Data())
        return try AES.GCM.open(sealedBox, using: sharedSecret)
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
