// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LedgeKit",
    platforms: [.macOS(.v14)],
    products: [
        // What add-ons are written with.
        .library(name: "LedgeKit", targets: ["LedgeKit"]),
        // The other side: running an add-on and reading its package, as Ledge and `ledgekit check` do.
        .library(name: "LedgeKitHost", targets: ["LedgeKitHost"]),
        .executable(name: "ledgekit", targets: ["LedgeKitCLI"]),
    ],
    targets: [
        .target(name: "LedgeKit"),
        .target(name: "LedgeKitHost", dependencies: ["LedgeKit"]),
        .executableTarget(name: "LedgeKitCLI", dependencies: ["LedgeKit", "LedgeKitHost"]),
        // An add-on that can misbehave on purpose, for the runtime's tests.
        .executableTarget(name: "LedgeKitHostFixture", dependencies: ["LedgeKit"]),
        .testTarget(name: "LedgeKitTests", dependencies: ["LedgeKit"]),
        .testTarget(name: "LedgeKitHostTests", dependencies: ["LedgeKitHost", "LedgeKitHostFixture"]),
    ]
)
