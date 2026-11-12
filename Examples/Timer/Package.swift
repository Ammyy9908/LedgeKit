// swift-tools-version: 6.0
import PackageDescription

// An example add-on: a countdown beside the notch. Builds against the LedgeKit in this checkout.
let package = Package(
    name: "Timer",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(name: "Timer", dependencies: [.product(name: "LedgeKit", package: "LedgeKit")])
    ]
)
