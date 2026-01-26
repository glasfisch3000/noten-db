// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "noten-db",
	platforms: [
		.macOS(.v26)
	],
	products: [
		.executable(name: "App", targets: ["NotenDB"]),
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.0"),
		.package(url: "https://github.com/vapor/vapor.git", exact: "4.115.0"),
		.package(url: "https://github.com/vapor/fluent.git", exact: "4.12.0"),
		.package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.11.0"),
		.package(url: "https://github.com/vapor/leaf.git", from: "4.5.0"),
	],
    targets: [
        .executableTarget(
            name: "NotenDB",
			dependencies: [
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
				.product(name: "Vapor", package: "vapor"),
				.product(name: "Fluent", package: "fluent"),
				.product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
				.product(name: "Leaf", package: "leaf"),
			],
			path: "Sources"
        ),
    ]
)
