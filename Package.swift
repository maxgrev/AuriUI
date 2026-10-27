// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AuriUI",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .watchOS(.v9),
    ],
    products: [
        .library(name: "AuriUI", targets: ["AuriUI"]),
        .library(name: "AuriUIRenderer", targets: ["AuriUIRenderer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/MarkdownUI", from: "2.4.1"),
    ],
    targets: [
        .target(name: "AuriUI"),
        .target(
            name: "AuriUIRenderer",
            dependencies: [
                "AuriUI",
                .product(
                    name: "MarkdownUI",
                    package: "MarkdownUI",
                    condition: .when(platforms: [.iOS, .macOS])
                ),
            ]
        ),
        .testTarget(
            name: "AuriUITests",
            dependencies: ["AuriUI"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "AuriUIRendererTests",
            dependencies: ["AuriUIRenderer", "AuriUI"]
        ),
    ]
)
