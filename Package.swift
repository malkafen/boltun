// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Boltun",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Boltun", targets: ["Boltun"]),
        .library(name: "BoltunKit", targets: ["BoltunKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0"),
    ],
    targets: [
        .target(name: "BoltunKit"),
        .target(
            name: "BoltunMarkup",
            dependencies: [
                "BoltunKit",
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        ),
        .target(
            name: "BoltunUI",
            dependencies: ["BoltunKit", "BoltunMarkup"]
        ),
        .executableTarget(
            name: "Boltun",
            dependencies: ["BoltunUI"]
        ),
        .testTarget(name: "BoltunKitTests", dependencies: ["BoltunKit"]),
        .testTarget(name: "BoltunMarkupTests", dependencies: ["BoltunMarkup", "BoltunKit"]),
        .testTarget(name: "BoltunUITests", dependencies: ["BoltunUI", "BoltunKit", "BoltunMarkup"]),
    ]
)
