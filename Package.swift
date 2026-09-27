// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Folio",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FolioCore", targets: ["FolioCore"]),
        .executable(name: "FolioDesktop", targets: ["FolioApp"]),
        .executable(name: "FolioCLI", targets: ["FolioCLI"]),
        .executable(name: "FolioPreviewHost", targets: ["FolioPreview"]),
        .executable(name: "FolioBench", targets: ["FolioBench"]),
    ],
    dependencies: [.package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0")],
    targets: [
        .target(name: "FolioCore", dependencies: [.product(name: "Markdown", package: "swift-markdown")],
                resources: [.process("Resources")]),
        .executableTarget(name: "FolioApp", dependencies: ["FolioCore"]),
        .executableTarget(name: "FolioCLI", dependencies: ["FolioCore"]),
        .executableTarget(name: "FolioPreview", dependencies: ["FolioCore"], path: "Extension", exclude: ["Info.plist", "FolioPreview.entitlements"]),
        .executableTarget(name: "FolioBench", dependencies: ["FolioCore"], path: "Tools/FolioBench"),
        .testTarget(name: "FolioCoreTests", dependencies: ["FolioCore"]),
        .testTarget(name: "FolioAppTests", dependencies: ["FolioApp"]),
    ],
    swiftLanguageModes: [.v5]
)
