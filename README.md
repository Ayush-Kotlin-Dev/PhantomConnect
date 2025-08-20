# PhantomConnect - Multi-Wallet Integration

A Swift iOS app that demonstrates wallet integration with both **Phantom** and **WalletConnect (Reown)** support.

## Features

- ✅ **Phantom Wallet Integration** - Native Solana wallet connection
- ✅ **WalletConnect Integration** - Multi-chain wallet support via Reown SDK
- ✅ **Message Signing** - Sign messages with both wallet types
- ✅ **Modular Architecture** - Separate business logic and UI components
- ✅ **Deep Link Handling** - Proper URL scheme handling for both wallets

## Architecture

The project follows a modular architecture with separation of concerns:

### Core Components

1. **Phantom.swift** - Business logic for Phantom wallet integration
2. **PhantomDeepLinkHandler.swift** - Handles Phantom deep link responses
3. **ReownWallet.swift** - Business logic for WalletConnect integration
4. **ReownDeepLinkHandler.swift** - Handles WalletConnect deep link responses
5. **ContentView.swift** - Main UI with dual wallet support

### UI Flow

1. **Step 1: Connect Wallet** - Users can choose between Phantom or WalletConnect
2. **Step 2: Sign Message** - Connected wallets can sign test messages
3. **Real-time Status** - UI updates automatically when wallet state changes

## Setup Instructions

### 1. Add Reown SDK Dependency

#### Using Xcode:
1. Open your project in Xcode
2. Go to File → Add Packages
3. Paste the repo URL: `https://github.com/reown-com/reown-swift`
4. Add the **AppKit** product to your app target

#### Using Package.swift:
```swift
dependencies: [
    .package(url: "https://github.com/reown-com/reown-swift", from: "1.0.0")
]
```

### 2. Configure Project ID

1. Create a project at [Reown Dashboard](https://cloud.reown.com)
2. Get your Project ID
3. Update `ReownWallet.swift` with your actual project ID:

```swift
AppKit.configure(
    projectId: "YOUR_PROJECT_ID", // Replace with your project ID
    metadata: metadata
)
```

### 3. URL Scheme Configuration

The `Info.plist` is already configured with necessary URL schemes:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>phantomconnect</string>
        </array>
    </dict>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>wc</string>
        </array>
    </dict>
</array>
```

### 4. Wallet Detection

Wallet apps that can be detected are configured in `LSApplicationQueriesSchemes`:
- MetaMask
- Trust Wallet
- Rainbow
- Coinbase Wallet
- And more...

## Usage

### Connect via Phantom
```swift
Phantom.shared.connect { success, error in
    if success {
        print("Connected to Phantom")
    }
}
```

### Connect via WalletConnect
```swift
ReownWallet.shared.presentWalletSelection { success, error in
    if success {
        ReownWallet.shared.connect { connectSuccess, connectError in
            // Handle connection result
        }
    }
}
```

### Sign Messages
```swift
// Phantom
Phantom.shared.signMessage("Hello World") { success, error in
    // Handle signature
}

// WalletConnect
ReownWallet.shared.signMessage("Hello World") { success, error in
    // Handle signature
}
```

## Implementation Notes

### Current State
- ✅ Complete UI implementation with dual wallet support
- ✅ Modular business logic separation
- ✅ Deep link handling infrastructure
- ⚠️ Simulated WalletConnect responses (for demonstration)

### To Complete Integration
1. Uncomment and configure the actual Reown AppKit calls in `ReownWallet.swift`
2. Add proper error handling for AppKit responses
3. Implement session management and persistence
4. Add wallet-specific UI improvements

### Security Considerations
- Never commit your Reown Project ID to public repositories
- Use environment variables or secure configuration for production
- Validate all deep link responses
- Implement proper session management

## Dependencies

- **TweetNacl** - Cryptographic operations for Phantom
- **Reown AppKit** - WalletConnect integration
- **CryptoKit** - Native iOS cryptography
- **SwiftUI** - Modern iOS UI framework

## License

This project is for educational and demonstration purposes.
