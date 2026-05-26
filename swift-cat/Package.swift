// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DesktopCat",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DesktopCat", targets: ["DesktopCat"])
    ],
    targets: [
        .executableTarget(
            name: "DesktopCat",
            path: "Sources/DesktopCat",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
