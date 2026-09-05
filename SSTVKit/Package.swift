// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SSTVKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "SSTVKit", targets: ["SSTVKit"]),
        .executable(name: "BaselineGenerator", targets: ["BaselineGenerator"]),
    ],
    targets: [
        .target(name: "SSTVKit"),
        .executableTarget(name: "BaselineGenerator", dependencies: ["SSTVKit"]),
        .testTarget(name: "SSTVKitTests", dependencies: ["SSTVKit"]),
    ]
)
