// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AutoMounty",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AutoMounty", targets: ["AutoMounty"])
    ],
    targets: [
        .target(
            name: "AutoMountyModel",
            dependencies: [],
            path: "source/Models"
        ),
        .executableTarget(
            name: "AutoMounty",
            dependencies: ["AutoMountyModel"],
            path: "source",
            exclude: ["Models"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("NetFS"),
                .linkedFramework("CoreWLAN")
            ]
        ),
        .testTarget(
            name: "AutoMountyTests",
            dependencies: ["AutoMountyModel"]
        )
    ]
)
