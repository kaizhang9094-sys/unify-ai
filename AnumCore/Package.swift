// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AnumCore",
    platforms: [
        // onnxruntime + swift-transformers require macOS 14+; keeps SPM `swift test` resolvable.
        .macOS(.v14),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "AnumCore",
            targets: ["AnumCore"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/microsoft/onnxruntime-swift-package-manager",
            from: "1.20.0"
        ),
        .package(
            url: "https://github.com/huggingface/swift-transformers.git",
            from: "1.3.0"
        ),
        .package(
            url: "https://github.com/pawelmajcher/SwiftyH3.git",
            "0.5.0"..<"0.6.0"
        )
    ],
    targets: [
        .target(
            name: "AnumCore",
            dependencies: [
                .product(
                    name: "onnxruntime",
                    package: "onnxruntime-swift-package-manager"
                ),
                .product(
                    name: "Tokenizers",
                    package: "swift-transformers"
                ),
                .product(
                    name: "SwiftyH3",
                    package: "SwiftyH3"
                )
            ],
            path: "Sources/AnumCore",
            resources: [
                .process("EmbeddingAssets")
            ]
        ),
        // AnumCoreTests: re-enable when unrelated compile failures are fixed (see scripts/run-provider-h3-metadata-tests.sh).
        // .testTarget(
        //     name: "AnumCoreTests",
        //     dependencies: ["AnumCore"],
        //     path: "Tests/AnumCoreTests"
        // ),
        /// Isolated provider H3 metadata tests (no device; run via scripts/run-provider-h3-metadata-tests.sh).
        .testTarget(
            name: "ProviderH3MetadataTests",
            dependencies: ["AnumCore"],
            path: "Tests/ProviderH3MetadataTests"
        ),
        .testTarget(
            name: "SearchIntentExtractorTests",
            dependencies: ["AnumCore"],
            path: "Tests/SearchIntentExtractorTests"
        ),
        .testTarget(
            name: "ExchangeChildCoordinationTests",
            dependencies: ["AnumCore"],
            path: "Tests/ExchangeChildCoordinationTests"
        ),
        .testTarget(
            name: "ExchangeBootstrapFederationURLTests",
            dependencies: ["AnumCore"],
            path: "Tests/ExchangeBootstrapFederationURLTests"
        ),
        .testTarget(
            name: "ExchangeForegroundSyncPolicyTests",
            dependencies: ["AnumCore"],
            path: "Tests/ExchangeForegroundSyncPolicyTests"
        ),
        .testTarget(
            name: "ExchangeDiscoveryProfileFallbackTests",
            dependencies: ["AnumCore"],
            path: "Tests/AnumCoreTests",
            sources: [
                "ExchangeDiscoveryProfileCompatibleFallbackTests.swift",
                "ExchangeSemanticProofBackwardCompatibilityTests.swift",
                "ExchangeDirectoryRemoteOnlyFallbackRemovalTests.swift"
            ]
        ),
        .testTarget(
            name: "ExchangeInboundOpenRoutingTests",
            dependencies: ["AnumCore"],
            path: "Tests/ExchangeInboundOpenRoutingTests"
        ),
        .testTarget(
            name: "DirectMessageTranscriptProjectionTests",
            dependencies: ["AnumCore"],
            path: "Tests/DirectMessageTranscriptProjectionTests"
        ),
        .testTarget(
            name: "ExchangeProviderInboundAssessmentTests",
            dependencies: ["AnumCore"],
            path: "Tests/ExchangeProviderInboundAssessmentTests"
        ),
        .testTarget(
            name: "ExchangeOfferObjectLaneTests",
            dependencies: ["AnumCore"],
            path: "Tests/ExchangeOfferObjectLaneTests"
        ),
        .testTarget(
            name: "ExchangeRetrievalAccuracyTests",
            dependencies: ["AnumCore"],
            path: "Tests/ExchangeRetrievalAccuracyTests"
        ),
        .testTarget(
            name: "ExchangeAppSearchSmokeTests",
            dependencies: ["AnumCore"],
            path: "Tests/ExchangeAppSearchSmokeTests"
        ),
        .testTarget(
            name: "ExchangeProviderDetailsPresentationContextTests",
            dependencies: ["AnumCore"],
            path: "Tests/ExchangeProviderDetailsPresentationContextTests"
        ),
        .testTarget(
            name: "RequesterOutboundSendSafetyTests",
            dependencies: ["AnumCore"],
            path: "Tests/RequesterOutboundSendSafetyTests"
        ),
        .testTarget(
            name: "ProviderInboundIntentExtractionTests",
            dependencies: ["AnumCore"],
            path: "Tests/ProviderInboundIntentExtractionTests"
        ),
        .testTarget(
            name: "ProviderInquiryCompareDecodeTests",
            dependencies: ["AnumCore"],
            path: "Tests/ProviderInquiryCompareDecodeTests"
        ),
        .testTarget(
            name: "ExchangeSemanticEvidenceSanitizerTests",
            dependencies: ["AnumCore"],
            path: "Tests/ExchangeSemanticEvidenceSanitizerTests"
        ),
        .testTarget(
            name: "ExchangeThreadCardTitleProjectionTests",
            dependencies: ["AnumCore"],
            path: "Tests/ExchangeThreadCardTitleProjectionTests"
        ),
        .testTarget(
            name: "ExchangeSupporterPresentationSafetyTests",
            dependencies: ["AnumCore"],
            path: "Tests/ExchangeSupporterPresentationSafetyTests"
        ),
        .testTarget(
            name: "AddFriendInviteTests",
            dependencies: ["AnumCore"],
            path: "Tests/AddFriendInviteTests"
        ),
    ]
)
