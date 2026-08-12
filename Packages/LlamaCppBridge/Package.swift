// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LlamaCppBridge",
    platforms: [
        .macOS(.v15),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "LlamaCppBridge",
            targets: ["LlamaCppBridge"]
        )
    ],
    targets: [
        // Prebuilt llama binary for Apple platforms (iOS + macOS)
        .binaryTarget(
            name: "llama",
            path: "vendor/llama.cpp/build-apple/llama.xcframework"
        ),

        // Swift API surface + embeds dylibs into the final app bundle
        .target(
            name: "LlamaCppBridge",
            dependencies: ["LlamaCppBridgeC"],
            path: "Sources/LlamaCppBridge"
        ),

        // C/C++ bridge that includes llama.h and links against libllama + ggml
        .target(
            name: "LlamaCppBridgeC",
            dependencies: ["llama"],
            path: "Sources/LlamaCppBridgeC",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("../../vendor/llama.cpp/include"),
                .headerSearchPath("../../vendor/llama.cpp/ggml/include"),
            ],
            cxxSettings: [
                .headerSearchPath("../../vendor/llama.cpp/include"),
                .headerSearchPath("../../vendor/llama.cpp/ggml/include"),
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit")
            ]
        ),

        .testTarget(
            name: "LlamaCppBridgeTests",
            dependencies: ["LlamaCppBridge"],
            path: "Tests/LlamaCppBridgeTests"
        ),
    ]
)
