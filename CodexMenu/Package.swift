// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexMenu",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CodexMenu", targets: ["CodexMenu"])],
    targets: [
        .executableTarget(name: "CodexMenu", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "CodexMenuTests", dependencies: ["CodexMenu"], path: "Tests")
    ]
)
