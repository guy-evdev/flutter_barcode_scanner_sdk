@testable import flutter_barcode_scanner_sdk
import AVFoundation
import Flutter
import XCTest

class RunnerTests: XCTestCase {
    func testScannerConfigNormalizesWindowValues() {
        let config = ScannerConfig(
            arguments: [
                "scanWindow": [
                    "widthFactor": Double.infinity,
                    "heightFactor": 0.01,
                    "cornerRadius": -4,
                ],
                "uiConfig": ["initialCameraLens": "front"],
            ]
        )

        XCTAssertEqual(config.scanWindowWidthFactor, 0.58)
        XCTAssertEqual(config.scanWindowHeightFactor, 0.2)
        XCTAssertEqual(config.scanWindowCornerRadius, 0)
        XCTAssertEqual(config.initialCameraPosition, AVCaptureDevice.Position.front)
    }

    func testScannerConfigMapsRequestedFormats() {
        let config = ScannerConfig(
            arguments: ["allowedFormats": ["QR_CODE", "CODE_128"]]
        )

        XCTAssertEqual(config.allowedTypes, [.qr, .code128])
    }
}
