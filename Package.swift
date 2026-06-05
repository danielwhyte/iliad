// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Iliad",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "Iliad",
            dependencies: ["SwiftTerm"],
            path: "Sources",
            resources: [
                .copy("Resources/Literata.ttf"),
                .copy("Resources/Literata-Italic.ttf"),
                .copy("Resources/themes.json")
            ]
        )
    ]
)
