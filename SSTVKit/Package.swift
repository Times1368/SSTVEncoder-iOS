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
        .target(
            name: "BaselineSupport",
            dependencies: ["SSTVKit"],
            path: "TestSupport/BaselineSupport"
        ),
        .executableTarget(
            name: "BaselineGenerator",
            dependencies: ["SSTVKit", "BaselineSupport"]
        ),
        .testTarget(name: "SSTVKitTests", dependencies: ["SSTVKit"]),
        .testTarget(
            name: "BaselineSupportTests",
            dependencies: ["SSTVKit", "BaselineSupport"]
        ),
    ]
)
