// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RemindersStats",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "RemindersStats",
            targets: ["RemindersStats"]
        ),
        .executable(
            name: "reminders-stats",
            targets: ["reminders-stats"]
        ),
    ],
    targets: [
        .target(
            name: "RemindersStats"
        ),
        .executableTarget(
            name: "reminders-stats",
            dependencies: ["RemindersStats"],
            path: "Sources/reminders-stats",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "\(Context.packageDirectory)/Resources/Info.plist",
                ])
            ]
        ),
        .testTarget(
            name: "RemindersStatsTests",
            dependencies: ["RemindersStats"]
        ),
    ]
)
