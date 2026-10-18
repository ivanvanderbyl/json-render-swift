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
    ],
    targets: [
        // UI-free core: spec model, JSON values, validation, expressions,
        // state, actions, visibility, repeat and streaming.
        .target(name: "JSONRender"),

        .testTarget(name: "JSONRenderTests", dependencies: ["JSONRender"]),
    ],
    swiftLanguageModes: [.v6]
)
