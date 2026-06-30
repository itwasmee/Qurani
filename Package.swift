// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QuraniKit",
    platforms: [.macOS(.v26)],
    products: [.library(name: "QuraniKit", targets: ["QuraniKit"])],
    targets: [
        .target(
            name: "QuraniKit",
            resources: [.process("Data/Resources"), .process("Sources/Resources")],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .testTarget(name: "QuraniKitTests", dependencies: ["QuraniKit"])
    ]
)
