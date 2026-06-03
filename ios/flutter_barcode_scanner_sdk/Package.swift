// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "flutter_barcode_scanner_sdk",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "flutter-barcode-scanner-sdk", targets: ["flutter_barcode_scanner_sdk"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "flutter_barcode_scanner_sdk",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
