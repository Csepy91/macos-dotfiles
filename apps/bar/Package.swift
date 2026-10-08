// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Bar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Bar", targets: ["Bar"])
    ],
    targets: [
        .executableTarget(
            name: "Bar",
            path: "Sources/Bar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("IOBluetooth")
            ]
        )
    ]
)
