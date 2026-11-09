// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LedgeKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "LedgeKit", targets: ["LedgeKit"]),
               .executable(name: "ledgekit", targets: ["LedgeKitCLI"])],
    targets: [.target(name: "LedgeKit"),
              .executableTarget(name: "LedgeKitCLI", dependencies: ["LedgeKit"]), .testTarget(name: "LedgeKitTests", dependencies: ["LedgeKit"])]
)
