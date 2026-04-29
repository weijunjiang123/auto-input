// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AutoInput",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "AutoInputCore", targets: ["AutoInputCore"]),
        .executable(name: "AutoInput", targets: ["AutoInput"]),
        .executable(name: "AutoInputCoreTests", targets: ["AutoInputCoreTests"])
    ],
    targets: [
        .target(name: "AutoInputCore"),
        .executableTarget(
            name: "AutoInput",
            dependencies: ["AutoInputCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "AutoInputCoreTests",
            dependencies: ["AutoInputCore"],
            path: "Tests/AutoInputCoreTests"
        )
    ]
)
