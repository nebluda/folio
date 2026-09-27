// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Folio",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FolioCore", targets: ["FolioCore"]),
        .executable(name: "Folio", targets: ["FolioApp"]),
        .executable(name: "folio", targets: ["FolioCLI"]),
        .executable(name: "FolioPreview", targets: ["FolioPreview"]),
    ],
    dependencies: [.package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0")],
    targets: [
        .target(name: "FolioCore", dependencies: [.product(name: "Markdown", package: "swift-markdown")],
                resources: [.process("Resources")]),
        .executableTarget(name: "FolioApp", dependencies: ["FolioCore"]),
        .executableTarget(name: "FolioCLI", dependencies: ["FolioCore"]),
        .executableTarget(name: "FolioPreview", dependencies: ["FolioCore"], path: "Extension", exclude: ["Info.plist", "FolioPreview.entitlements"]),
        .testTarget(name: "FolioCoreTests", dependencies: ["FolioCore"]),
        .testTarget(name: "FolioAppTests", dependencies: ["FolioApp"]),
    ],
    swiftLanguageModes: [.v5]
)
