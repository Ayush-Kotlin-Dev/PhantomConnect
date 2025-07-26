//
//  PhantomState.swift
//  PhantomConnect
//
//  Created by Ayush Rai on 25/07/25.
//

import Foundation
import Combine

class PhantomState: ObservableObject {
    static let shared = PhantomState()

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

    @Published var isConnected: Bool {
        didSet {
            userDefaults.set(isConnected, forKey: Keys.isConnected)
        }
    }

    @Published var publicKey: String {
        didSet {
            userDefaults.set(publicKey, forKey: Keys.publicKey)
        }
    }

    @Published var isLoading: Bool {
        didSet {
            userDefaults.set(isLoading, forKey: Keys.isLoading)
        }
    }

    @Published var errorMessage: String {
        didSet {
            userDefaults.set(errorMessage, forKey: Keys.errorMessage)
        }
    }

    @Published var signature: String {
        didSet {
            userDefaults.set(signature, forKey: Keys.signature)
        }
    }

    var session: String {
        get {
            return userDefaults.string(forKey: Keys.session) ?? ""
        }
        set {
            userDefaults.set(newValue, forKey: Keys.session)
        }
    }

    var sharedSecret: Data? {
        get {
            return userDefaults.data(forKey: Keys.sharedSecret)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.sharedSecret)
        }
    }

    var dappPublicKey: String {
        get {
            return userDefaults.string(forKey: Keys.dappPublicKey) ?? ""
        }
        set {
            userDefaults.set(newValue, forKey: Keys.dappPublicKey)
        }
    }

    var dappPrivateKey: Data? {
        get {
            return userDefaults.data(forKey: Keys.dappPrivateKey)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.dappPrivateKey)
        }
    }

    private init() {
        // Load existing values from UserDefaults
        self.isConnected = userDefaults.bool(forKey: Keys.isConnected)
        self.publicKey = userDefaults.string(forKey: Keys.publicKey) ?? ""
        self.isLoading = userDefaults.bool(forKey: Keys.isLoading)
        self.errorMessage = userDefaults.string(forKey: Keys.errorMessage) ?? ""
        self.signature = userDefaults.string(forKey: Keys.signature) ?? ""
    }

    // MARK: - Helper Methods
    func setLoading(_ loading: Bool) {
        DispatchQueue.main.async {
            self.isLoading = loading
        }
    }

    func setError(_ error: String) {
        DispatchQueue.main.async {
            self.errorMessage = error
        }
    }

    func clearError() {
        DispatchQueue.main.async {
            self.errorMessage = ""
        }
    }

    func setConnected(_ connected: Bool) {
        DispatchQueue.main.async {
            self.isConnected = connected
        }
    }

    func setPublicKey(_ key: String) {
        DispatchQueue.main.async {
            self.publicKey = key
        }
    }

    func setSignature(_ sig: String) {
        DispatchQueue.main.async {
            self.signature = sig
        }
    }

    func setSession(_ sessionValue: String) {
        session = sessionValue
    }

    func setSharedSecret(_ secret: Data) {
        sharedSecret = secret
    }

    func setDappPublicKey(_ key: String) {
        dappPublicKey = key
    }

    func setDappPrivateKey(_ key: Data) {
        dappPrivateKey = key
    }

    func disconnect() {
        DispatchQueue.main.async {
            self.isConnected = false
            self.publicKey = ""
            self.signature = ""
            self.errorMessage = ""
        }
        session = ""
        sharedSecret = nil
    }
}