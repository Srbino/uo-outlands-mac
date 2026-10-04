// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OutlandsInstaller",
    platforms: [.macOS("14.6")],
    products: [.executable(name: "OutlandsInstaller", targets: ["OutlandsInstaller"])],
    targets: [
        .systemLibrary(name: "CArchive"),
        .target(name: "OutlandsCore", dependencies: ["CArchive"], resources: [.copy("recipe.json")]),
        .executableTarget(name: "OutlandsInstaller", dependencies: ["OutlandsCore"], resources: [.copy("Resources/GameIcons")]),
        .testTarget(name: "OutlandsCoreTests", dependencies: ["OutlandsCore"])
    ]
)
