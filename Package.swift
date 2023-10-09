// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "SwiftProxy",
    platforms: [
        .macOS(.v10_14),
        .iOS(.v14)
    ],
    products: [
        .library(name: "SwiftProxy", targets: ["SwiftProxy"]),
        .executable(name: "SwiftProxyCLI", targets: ["SwiftProxyCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.14.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
			name: "SwiftProxyCLI",
			dependencies: [
				"SwiftProxy",
				.product(name: "ArgumentParser", package:  "swift-argument-parser")
			]
		),
        .target(
			name: "SwiftProxy",
			dependencies: [
				.product(name: "NIO", package: "swift-nio"),
				.product(name: "NIOHTTP1", package: "swift-nio"),
				.product(name: "NIOFoundationCompat", package: "swift-nio"),
				.product(name: "Logging", package: "swift-log"),
				.product(name: "NIOSSL", package: "swift-nio-ssl"),
				.product(name: "NIOHTTPCompression", package: "swift-nio-extras"),
			]
		),
		.testTarget( // Add test target
			name: "SwiftProxyTests",
			dependencies: ["SwiftProxy"],
			resources: [
				.copy("Resources/localhost.crt"),
				.copy("Resources/localhost.key.pem"),
			]
		)
    ]
)
