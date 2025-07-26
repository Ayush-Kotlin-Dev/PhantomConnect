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

    // UserDefaults-backed state
    @State private var isConnected = false
    @State private var publicKey = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var signature = ""

    private let logger = Logger(subsystem: "com.phantomconnect.app", category: "ContentView")
    private let userDefaults = UserDefaults.standard

    // Keys for UserDefaults
    private enum Keys {
        static let isConnected = "phantom_is_connected"
        static let publicKey = "phantom_public_key"
        static let isLoading = "phantom_is_loading"
        static let errorMessage = "phantom_error_message"
        static let signature = "phantom_signature"
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                headerView
                connectStepView
                signStepView
                errorView
                debugLogView
                disconnectButton
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
                addDebugLog("✅ Message signed successfully!")
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
        isConnected = userDefaults.bool(forKey: Keys.isConnected)
        publicKey = userDefaults.string(forKey: Keys.publicKey) ?? ""
        isLoading = userDefaults.bool(forKey: Keys.isLoading)
        errorMessage = userDefaults.string(forKey: Keys.errorMessage) ?? ""
        signature = userDefaults.string(forKey: Keys.signature) ?? ""
    }

    private func startPollingUserDefaults() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
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
        }
    }

    private var headerView: some View {
        VStack(spacing: 10) {
            Image(systemName: "wallet.pass")
                .font(.system(size: 60))
                .foregroundColor(.purple)

            Text("Phantom Connect")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Two-step wallet connection")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 20)
    }

    private var connectStepView: some View {
        VStack(spacing: 15) {
            HStack {
                Circle()
                    .fill(isConnected ? Color.green : Color.gray)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Text("1")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text("Connect Wallet")
                        .font(.headline)
                    Text("Get your wallet address")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                }
            }

            if isConnected {
                connectedWalletInfo
            } else {
                connectButton
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(15)
    }

    private var connectedWalletInfo: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Connected Wallet:")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(publicKey)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var connectButton: some View {
        Button(action: {
            Phantom.shared.connect { success, error in
                if success {
                    addDebugLog("✅ Connection request sent!")
                } else if let error = error {
                    addDebugLog("❌ Connection failed: \(error)")
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
        .disabled(isLoading)
    }

    private var signStepView: some View {
        VStack(spacing: 15) {
            HStack {
                Circle()
                    .fill(isConnected ? (signature.isEmpty ? Color.orange : Color.green) : Color.gray)
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

                if !signature.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                }
            }

            if isConnected {
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
        .opacity(isConnected ? 1.0 : 0.6)
    }

    private var signMessageContent: some View {
        VStack(spacing: 10) {
            TextField("Message to sign", text: $messageToSign)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            Button(action: {
                Phantom.shared.signMessage(messageToSign) { success, error in
                    if success {
                        addDebugLog("✅ Sign request sent!")
                    } else if let error = error {
                        addDebugLog("❌ Sign request failed: \(error)")
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
                    Text("Sign Message")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(isLoading || messageToSign.isEmpty)

            if !signature.isEmpty {
                signatureDisplay
            }
        }
    }

    private var signatureDisplay: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Signature:")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(signature)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .lineLimit(3)
        }
    }

    @ViewBuilder
    private var errorView: some View {
        if !errorMessage.isEmpty {
            Text(errorMessage)
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
    private var disconnectButton: some View {
        if isConnected {
            Button("Disconnect") {
                Phantom.shared.disconnect()
                addDebugLog("Wallet disconnected")
            }
            .foregroundColor(.red)
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
