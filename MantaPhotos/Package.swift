// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MantaPhotos",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "MantaPhotosCore", targets: ["MantaPhotosCore"]),
        .executable(name: "MantaPhotosMac", targets: ["MantaPhotosMac"]),
        .executable(name: "MantaPhotosChecks", targets: ["MantaPhotosChecks"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.0")
    ],
    targets: [
        .target(
            name: "MantaPhotosCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/MantaPhotosMac",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "MantaPhotosMac",
            dependencies: ["MantaPhotosCore"],
            path: "Sources/MantaPhotosMacApp"
        ),
        .executableTarget(
            name: "MantaPhotosChecks",
            dependencies: [
                "MantaPhotosCore",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/MantaPhotosChecks"
        ),
        .testTarget(
            name: "MantaPhotosMacTests",
            dependencies: ["MantaPhotosCore"]
        )
    ]
)
