//
//  ContentView.swift
//  PhantomConnect
//
//  Created by Ayush Rai on 25/07/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var phantomWallet = PhantomWallet()
    @State private var messageToSign = "Hello from PhantomConnect! Test message for signing."
    @State private var signature: String = ""
    @State private var showingSignatureAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Header
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
                
                Spacer()
                
                // Step 1: Connect
                VStack(spacing: 15) {
                    HStack {
                        Circle()
                            .fill(phantomWallet.isConnected ? Color.green : Color.gray)
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
                        
                        if phantomWallet.isConnected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title2)
                        }
                    }
                    
                    if phantomWallet.isConnected {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Connected Wallet:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(phantomWallet.publicKey)
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } else {
                        Button(action: {
                            phantomWallet.connect()
                        }) {
                            HStack {
                                if phantomWallet.isLoading {
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
                        .disabled(phantomWallet.isLoading)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(15)
                
                // Step 2: Sign Message
                VStack(spacing: 15) {
                    HStack {
                        Circle()
                            .fill(phantomWallet.isConnected ? (signature.isEmpty ? Color.orange : Color.green) : Color.gray)
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
                    
                    if phantomWallet.isConnected {
                        VStack(spacing: 10) {
                            TextField("Message to sign", text: $messageToSign)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Button(action: {
                                phantomWallet.signMessage(messageToSign)
                            }) {
                                HStack {
                                    if phantomWallet.isLoading {
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
                            .disabled(phantomWallet.isLoading || messageToSign.isEmpty)
                            
                            if !signature.isEmpty {
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
                        }
                    } else {
                        Text("Complete step 1 first")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(15)
                .opacity(phantomWallet.isConnected ? 1.0 : 0.6)
                
                Spacer()
                
                // Error message
                if !phantomWallet.errorMessage.isEmpty {
                    Text(phantomWallet.errorMessage)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                }
                
                // Disconnect button
                if phantomWallet.isConnected {
                    Button("Disconnect") {
                        phantomWallet.disconnect()
                        signature = ""
                    }
                    .foregroundColor(.red)
                }
            }
            .padding()
            .navigationBarHidden(true)
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .alert("Message Signed", isPresented: $showingSignatureAlert) {
            Button("OK") { }
        } message: {
            Text("Your message has been successfully signed!")
        }
    }
    
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "phantomconnect" else { return }
        
        switch url.host {
        case "connected":
            phantomWallet.handleConnectResponse(url: url)
        case "signed":
            if let sig = phantomWallet.handleSignResponse(url: url) {
                signature = sig
                showingSignatureAlert = true
            }
        default:
            break
        }
    }
}

#Preview {
    ContentView()
}
