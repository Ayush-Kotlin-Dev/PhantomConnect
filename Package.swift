// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "PhantomConnect",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "PhantomConnect",
            targets: ["PhantomConnect"])
    ],
    dependencies: [
        .package(url: "https://github.com/bitmark-inc/tweetnacl-swiftwrap", from: "1.0.0"),
        .package(url: "https://github.com/reown-com/reown-swift", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "PhantomConnect",
            dependencies: [
                .product(name: "TweetNacl", package: "tweetnacl-swiftwrap"),
                .product(name: "AppKit", package: "reown-swift")
            ]
        )
    ]
)