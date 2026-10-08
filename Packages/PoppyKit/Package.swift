// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PoppyKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PoppyKit", targets: ["PoppyKit"])],
    targets: [
        .target(name: "PoppyKit"),
        .testTarget(name: "PoppyKitTests", dependencies: ["PoppyKit"]),
    ]
)
