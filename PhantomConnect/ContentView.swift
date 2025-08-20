//
//  ContentView.swift
//  PhantomConnect
//
//  Created by Ayush Rai on 25/07/25.
//

import SwiftUI
import os

struct ContentView: View {
    @State private var messageToSign = "Hello from PhantomConnect! Test message for signing."
    @State private var showingSignatureAlert = false
    @State private var debugLogs: [String] = []

    // Phantom UserDefaults-backed state
    @State private var isConnected = false
    @State private var publicKey = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var signature = ""
    
    // Reown UserDefaults-backed state
    @State private var reownIsConnected = false
    @State private var reownWalletAddress = ""
    @State private var reownIsLoading = false
    @State private var reownErrorMessage = ""
    @State private var reownSignature = ""
    @State private var reownWalletName = ""

    private let logger = Logger(subsystem: "com.phantomconnect.app", category: "ContentView")
    private let userDefaults = UserDefaults.standard

    // Keys for UserDefaults - Phantom
    private enum Keys {
        static let isConnected = "phantom_is_connected"
        static let publicKey = "phantom_public_key"
        static let isLoading = "phantom_is_loading"
        static let errorMessage = "phantom_error_message"
        static let signature = "phantom_signature"
    }
    
    // Keys for UserDefaults - Reown
    private enum ReownKeys {
        static let isConnected = "reown_is_connected"
        static let walletAddress = "reown_wallet_address"
        static let isLoading = "reown_is_loading"
        static let errorMessage = "reown_error_message"
        static let signature = "reown_signature"
        static let walletName = "reown_wallet_name"
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                headerView
                walletConnectionSection
                signStepView
                errorView
                debugLogView
                disconnectButtons
            }
            .padding()
            .navigationBarHidden(true)
        }
        .onAppear {
            loadUserDefaults()
            startPollingUserDefaults()
        }
        .onChange(of: signature) { newSignature in
            if !newSignature.isEmpty && !showingSignatureAlert {
                showingSignatureAlert = true
                addDebugLog("✅ Phantom message signed successfully!")
            }
        }
        .onChange(of: reownSignature) { newSignature in
            if !newSignature.isEmpty && !showingSignatureAlert {
                showingSignatureAlert = true
                addDebugLog("✅ Reown message signed successfully!")
            }
        }
        .alert("Message Signed", isPresented: $showingSignatureAlert) {
            Button("OK") {
            }
        } message: {
            Text("Your message has been successfully signed!")
        }
    }

    private func loadUserDefaults() {
        // Phantom
        isConnected = userDefaults.bool(forKey: Keys.isConnected)
        publicKey = userDefaults.string(forKey: Keys.publicKey) ?? ""
        isLoading = userDefaults.bool(forKey: Keys.isLoading)
        errorMessage = userDefaults.string(forKey: Keys.errorMessage) ?? ""
        signature = userDefaults.string(forKey: Keys.signature) ?? ""
        
        // Reown
        reownIsConnected = userDefaults.bool(forKey: ReownKeys.isConnected)
        reownWalletAddress = userDefaults.string(forKey: ReownKeys.walletAddress) ?? ""
        reownIsLoading = userDefaults.bool(forKey: ReownKeys.isLoading)
        reownErrorMessage = userDefaults.string(forKey: ReownKeys.errorMessage) ?? ""
        reownSignature = userDefaults.string(forKey: ReownKeys.signature) ?? ""
        reownWalletName = userDefaults.string(forKey: ReownKeys.walletName) ?? ""
    }

    private func startPollingUserDefaults() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            // Phantom state
            let newIsConnected = userDefaults.bool(forKey: Keys.isConnected)
            let newPublicKey = userDefaults.string(forKey: Keys.publicKey) ?? ""
            let newIsLoading = userDefaults.bool(forKey: Keys.isLoading)
            let newErrorMessage = userDefaults.string(forKey: Keys.errorMessage) ?? ""
            let newSignature = userDefaults.string(forKey: Keys.signature) ?? ""

            if newIsConnected != isConnected {
                isConnected = newIsConnected
            }
            if newPublicKey != publicKey {
                publicKey = newPublicKey
            }
            if newIsLoading != isLoading {
                isLoading = newIsLoading
            }
            if newErrorMessage != errorMessage {
                errorMessage = newErrorMessage
            }
            if newSignature != signature {
                signature = newSignature
            }
            
            // Reown state
            let newReownIsConnected = userDefaults.bool(forKey: ReownKeys.isConnected)
            let newReownWalletAddress = userDefaults.string(forKey: ReownKeys.walletAddress) ?? ""
            let newReownIsLoading = userDefaults.bool(forKey: ReownKeys.isLoading)
            let newReownErrorMessage = userDefaults.string(forKey: ReownKeys.errorMessage) ?? ""
            let newReownSignature = userDefaults.string(forKey: ReownKeys.signature) ?? ""
            let newReownWalletName = userDefaults.string(forKey: ReownKeys.walletName) ?? ""

            if newReownIsConnected != reownIsConnected {
                reownIsConnected = newReownIsConnected
            }
            if newReownWalletAddress != reownWalletAddress {
                reownWalletAddress = newReownWalletAddress
            }
            if newReownIsLoading != reownIsLoading {
                reownIsLoading = newReownIsLoading
            }
            if newReownErrorMessage != reownErrorMessage {
                reownErrorMessage = newReownErrorMessage
            }
            if newReownSignature != reownSignature {
                reownSignature = newReownSignature
            }
            if newReownWalletName != reownWalletName {
                reownWalletName = newReownWalletName
            }
        }
    }

    private var headerView: some View {
        VStack(spacing: 10) {
            Image(systemName: "wallet.pass")
                .font(.system(size: 60))
                .foregroundColor(.purple)

            Text("Multi-Wallet Connect")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Connect via Phantom or WalletConnect")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 20)
    }

    private var walletConnectionSection: some View {
        VStack(spacing: 15) {
            HStack {
                Circle()
                    .fill((isConnected || reownIsConnected) ? Color.green : Color.gray)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Text("1")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text("Connect Wallet")
                        .font(.headline)
                    Text("Choose your preferred wallet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isConnected || reownIsConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                }
            }

            if isConnected {
                connectedPhantomWalletInfo
            } else if reownIsConnected {
                connectedReownWalletInfo
            } else {
                walletConnectionButtons
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(15)
    }
    
    private var walletConnectionButtons: some View {
        VStack(spacing: 12) {
            // Phantom Connect Button
            Button(action: {
                Phantom.shared.connect { success, error in
                    if success {
                        addDebugLog("✅ Phantom connection request sent!")
                    } else if let error = error {
                        addDebugLog("❌ Phantom connection failed: \(error)")
                    }
                }
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "link")
                    }
                    Text("Connect to Phantom")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(isLoading || reownIsLoading)
            
            // WalletConnect Button
            Button(action: {
                ReownWallet.shared.presentWalletSelection { success, error in
                    if success {
                        addDebugLog("✅ WalletConnect selection presented!")
                        // After presenting, attempt connection
                        ReownWallet.shared.connect { connectSuccess, connectError in
                            if connectSuccess {
                                addDebugLog("✅ WalletConnect connection successful!")
                            } else if let error = connectError {
                                addDebugLog("❌ WalletConnect connection failed: \(error)")
                            }
                        }
                    } else if let error = error {
                        addDebugLog("❌ WalletConnect presentation failed: \(error)")
                    }
                }
            }) {
                HStack {
                    if reownIsLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "wallet.pass")
                    }
                    Text("WalletConnect")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(isLoading || reownIsLoading)
        }
    }

    private var connectedPhantomWalletInfo: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Connected via Phantom:")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(publicKey)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(8)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
    
    private var connectedReownWalletInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connected via WalletConnect:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wallet: \(reownWalletName)")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(reownWalletAddress)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
    }

    private var signStepView: some View {
        VStack(spacing: 15) {
            HStack {
                Circle()
                    .fill((isConnected || reownIsConnected) ? 
                          ((!signature.isEmpty || !reownSignature.isEmpty) ? Color.green : Color.orange) : Color.gray)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Text("2")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text("Sign Message")
                        .font(.headline)
                    Text("Verify wallet ownership")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !signature.isEmpty || !reownSignature.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                }
            }

            if isConnected || reownIsConnected {
                signMessageContent
            } else {
                Text("Complete step 1 first")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(15)
        .opacity((isConnected || reownIsConnected) ? 1.0 : 0.6)
    }

    private var signMessageContent: some View {
        VStack(spacing: 10) {
            TextField("Message to sign", text: $messageToSign)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            if isConnected {
                Button(action: {
                    Phantom.shared.signMessage(messageToSign) { success, error in
                        if success {
                            addDebugLog("✅ Phantom sign request sent!")
                        } else if let error = error {
                            addDebugLog("❌ Phantom sign request failed: \(error)")
                        }
                    }
                }) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "signature")
                        }
                        Text("Sign with Phantom")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isLoading || reownIsLoading || messageToSign.isEmpty)
            }
            
            if reownIsConnected {
                Button(action: {
                    ReownWallet.shared.signMessage(messageToSign) { success, error in
                        if success {
                            addDebugLog("✅ WalletConnect sign request sent!")
                        } else if let error = error {
                            addDebugLog("❌ WalletConnect sign request failed: \(error)")
                        }
                    }
                }) {
                    HStack {
                        if reownIsLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "signature")
                        }
                        Text("Sign with WalletConnect")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isLoading || reownIsLoading || messageToSign.isEmpty)
            }

            if !signature.isEmpty {
                phantomSignatureDisplay
            }
            
            if !reownSignature.isEmpty {
                reownSignatureDisplay
            }
        }
    }

    private var phantomSignatureDisplay: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Phantom Signature:")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(signature)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(8)
                .lineLimit(3)
        }
    }
    
    private var reownSignatureDisplay: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("WalletConnect Signature:")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(reownSignature)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                .lineLimit(3)
        }
    }

    @ViewBuilder
    private var errorView: some View {
        if !errorMessage.isEmpty {
            Text("Phantom: \(errorMessage)")
                .foregroundColor(.red)
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(10)
        }
        
        if !reownErrorMessage.isEmpty {
            Text("WalletConnect: \(reownErrorMessage)")
                .foregroundColor(.red)
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(10)
        }
    }

    private var debugLogView: some View {
        VStack(alignment: .leading, spacing: 10) {
            debugLogHeader
            debugLogScrollView
        }
        .padding()
        .background(Color.blue.opacity(0.02))
        .cornerRadius(15)
    }

    private var debugLogHeader: some View {
        HStack {
            Text("Debug Logs")
                .font(.headline)
            Spacer()

            Button("Save Logs") {
                saveLogsToFile()
            }
            .font(.caption)
            .foregroundColor(.green)
            .padding(.trailing, 8)

            Button("Clear") {
                debugLogs.removeAll()
            }
            .font(.caption)
            .foregroundColor(.blue)
        }
    }

    private var debugLogScrollView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 5) {
                ForEach(debugLogs.indices, id: \.self) { index in
                    DebugLogItemView(
                        index: index + 1,
                        message: debugLogs[index]
                    )
                }
            }
            .padding(.horizontal, 5)
        }
        .frame(height: 120)
        .background(Color.gray.opacity(0.02))
        .cornerRadius(8)
        .border(Color.gray.opacity(0.3), width: 1)
    }

    @ViewBuilder
    private var disconnectButtons: some View {
        HStack(spacing: 12) {
            if isConnected {
                Button("Disconnect Phantom") {
                    Phantom.shared.disconnect()
                    addDebugLog("Phantom wallet disconnected")
                }
                .foregroundColor(.red)
            }
            
            if reownIsConnected {
                Button("Disconnect WalletConnect") {
                    ReownWallet.shared.disconnect()
                    addDebugLog("WalletConnect wallet disconnected")
                }
                .foregroundColor(.red)
            }
        }
    }

    private func addDebugLog(_ message: String) {
        logger.debug("\(message)")
        let timestamp = DateFormatter.debugTimeFormatter.string(from: Date())
        debugLogs.append("[\(timestamp)] \(message)")
    }

    private func saveLogsToFile() {
        let timestamp = DateFormatter.fileNameFormatter.string(from: Date())
        let fileName = "PhantomConnect_Logs_\(timestamp).txt"

        let logsContent = debugLogs.joined(separator: "\n")
        let fullContent = """
                          Phantom Connect Debug Logs
                          Generated: \(DateFormatter.fullDateFormatter.string(from: Date()))

                          ===========================================

                          \(logsContent)

                          ===========================================
                          End of logs
                          """

        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            logger.error("Could not access documents directory")
            return
        }

        let fileURL = documentsDirectory.appendingPathComponent(fileName)

        do {
            try fullContent.write(to: fileURL, atomically: true, encoding: .utf8)
            logger.debug("✅ Logs saved to: \(fileURL.path)")
            addDebugLog("💾 Logs saved to file: \(fileName)")

            // Show share sheet to export the file
            DispatchQueue.main.async {
                let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let rootVC = window.rootViewController {

                    // For iPad compatibility
                    if let popover = activityVC.popoverPresentationController {
                        popover.sourceView = window
                        popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                        popover.permittedArrowDirections = []
                    }

                    rootVC.present(activityVC, animated: true)
                }
            }
        } catch {
            logger.error("Failed to save logs: \(error.localizedDescription)")
            addDebugLog("❌ Failed to save logs: \(error.localizedDescription)")
        }
    }
}

struct DebugLogItemView: View {
    let index: Int
    let message: String

    var body: some View {
        HStack(alignment: .top) {
            Text("\(index).")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .leading)

            Text(message)
                .font(.system(.caption, design: .monospaced))
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(5)
    }
}

extension DateFormatter {
    static let debugTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
    static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

#Preview {
    ContentView()
}
