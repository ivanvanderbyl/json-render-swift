// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "JSONRender",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "JSONRender", targets: ["JSONRender"]),
        .library(name: "JSONRenderUI", targets: ["JSONRenderUI"]),
        .library(name: "JSONRenderStandard", targets: ["JSONRenderStandard"]),
    ],
    targets: [
        // UI-free core: spec model, JSON values, validation, expressions,
        // state, actions, visibility, repeat and streaming.
        .target(name: "JSONRender"),
        // SwiftUI renderer: draws the core's render tree with host components.
        .target(name: "JSONRenderUI", dependencies: ["JSONRender"]),
        // The React Native standard components, catalog and actions in SwiftUI.
        .target(name: "JSONRenderStandard", dependencies: ["JSONRender", "JSONRenderUI"]),

        .testTarget(name: "JSONRenderTests", dependencies: ["JSONRender"]),
        .testTarget(name: "JSONRenderUITests", dependencies: ["JSONRender", "JSONRenderUI"]),
        .testTarget(name: "JSONRenderStandardTests", dependencies: ["JSONRender", "JSONRenderUI", "JSONRenderStandard"]),
        // The first consumer: Brightfield's Brie surfaces, from their exported schema.
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["JSONRender", "JSONRenderUI"],
            exclude: ["Fixtures"]
        ),
        // Asserts the Swift port matches goldens produced by upstream json-render.
        .testTarget(
            name: "ConformanceTests",
            dependencies: ["JSONRender", "JSONRenderStandard"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
