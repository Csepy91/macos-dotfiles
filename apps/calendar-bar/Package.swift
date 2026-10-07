// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CalendarBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CalendarBar", targets: ["CalendarBar"])
    ],
    targets: [
        .executableTarget(
            name: "CalendarBar",
            path: "Sources/CalendarBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("EventKit")
            ]
        )
    ]
)
