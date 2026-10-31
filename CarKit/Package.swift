// swift-tools-version:5.9
// The cars' packet formats, kept apart from the app so they are tested on their own (`swift test`, also in CI).
import PackageDescription

let package = Package(
    name: "CarKit",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "CarKit", targets: ["CarKit"])],
    targets: [
        .target(name: "CarKit"),
        .testTarget(name: "CarKitTests", dependencies: ["CarKit"]),
    ]
)
