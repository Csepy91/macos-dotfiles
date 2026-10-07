// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Launcher",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Launcher", targets: ["Launcher"])
    ],
    targets: [
        .executableTarget(
            name: "Launcher",
            path: "Sources/Launcher",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics")
            ]
        )
    ]
)
