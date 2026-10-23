// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorkLog",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "WorkLog", targets: ["WorkLogApp"]),
        .library(name: "WorkLogCore", targets: ["WorkLogCore"]),
    ],
    targets: [
        .target(
            name: "WorkLogCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "WorkLogApp",
            dependencies: ["WorkLogCore"]
        ),
        .testTarget(
            name: "WorkLogCoreTests",
            dependencies: ["WorkLogCore"]
        ),
    ]
)
