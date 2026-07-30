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
        XCTAssertEqual(config.allowedFormatNames, ["QR_CODE", "CODE_128"])
    }

    func testScannerConfigDropsUnknownFormatNames() {
        let config = ScannerConfig(
            arguments: ["allowedFormats": ["QR_CODE", "NOT_A_FORMAT"]]
        )

        XCTAssertEqual(config.allowedTypes, [.qr])
        XCTAssertEqual(config.allowedFormatNames, ["QR_CODE"])
    }

    func testScannerConfigWithoutRequestedFormatsAllowsEveryFormat() {
        let config = ScannerConfig(arguments: [:])

        XCTAssertEqual(config.allowedFormatNames, Set(ScannerFormat.allowedTypes.keys))
        XCTAssertTrue(config.allowedFormatNames.contains("UPC_A"))
        XCTAssertTrue(config.allowedFormatNames.contains("EAN_13"))
    }

    // MARK: - B5, format-filter integrity

    func testSupportedTypesKeepsOnlyRequestedTypesInRequestedOrder() {
        let selected = ScannerFormat.supportedTypes(
            requested: [.qr, .code128, .pdf417],
            available: [.pdf417, .face, .qr]
        )

        XCTAssertEqual(selected, [.qr, .pdf417])
    }

    func testSupportedTypesNeverWidensToAvailableTypes() {
        let selected = ScannerFormat.supportedTypes(
            requested: [.qr],
            available: [.face, .humanBody, .catBody]
        )

        XCTAssertTrue(selected.isEmpty, "A QR-only request must never become every available type")
    }

    func testSupportedTypesIsEmptyWhenTheSessionReportsNothing() {
        let selected = ScannerFormat.supportedTypes(requested: [.qr, .ean13], available: [])

        XCTAssertTrue(selected.isEmpty)
    }

    // MARK: - B6, UPC-A / EAN-13 separation

    func testEan13OnlyRequestRejectsAUpcALabelledResult() {
        // AVFoundation reports UPC-A as .ean13; normalized() relabels the leading-zero form.
        let resolved = ScannerFormat.resolve(
            for: .ean13,
            value: "0123456789012",
            allowedFormatNames: ["EAN_13"]
        )

        XCTAssertNil(resolved)
    }

    func testEan13OnlyRequestAcceptsAGenuineEan13() {
        let resolved = ScannerFormat.resolve(
            for: .ean13,
            value: "5901234123457",
            allowedFormatNames: ["EAN_13"]
        )

        XCTAssertEqual(resolved, "EAN_13")
    }

    func testUpcAOnlyRequestRejectsAPlainEan13() {
        let resolved = ScannerFormat.resolve(
            for: .ean13,
            value: "5901234123457",
            allowedFormatNames: ["UPC_A"]
        )

        XCTAssertNil(resolved)
    }

    func testUpcAOnlyRequestAcceptsAUpcA() {
        let resolved = ScannerFormat.resolve(
            for: .ean13,
            value: "0123456789012",
            allowedFormatNames: ["UPC_A"]
        )

        XCTAssertEqual(resolved, "UPC_A")
    }

    func testRequestingBothKeepsEachLabelDistinct() {
        let allowed: Set<String> = ["UPC_A", "EAN_13"]

        XCTAssertEqual(
            ScannerFormat.resolve(for: .ean13, value: "0123456789012", allowedFormatNames: allowed),
            "UPC_A"
        )
        XCTAssertEqual(
            ScannerFormat.resolve(for: .ean13, value: "5901234123457", allowedFormatNames: allowed),
            "EAN_13"
        )
    }

    func testResolveRejectsAnUnrequestedFormat() {
        let resolved = ScannerFormat.resolve(
            for: .code128,
            value: "TICKET-1",
            allowedFormatNames: ["QR_CODE"]
        )

        XCTAssertNil(resolved)
    }

    func testResolveRejectsUnknownMetadataTypes() {
        let resolved = ScannerFormat.resolve(
            for: .face,
            value: "whatever",
            allowedFormatNames: Set(ScannerFormat.allowedTypes.keys)
        )

        XCTAssertNil(resolved, "A non-barcode type must never be reported as a barcode format")
    }

    // MARK: - B7, non-barcode payload formats

    func testCancelledPayloadReportsUnknownFormat() {
        let payload = ScannerPayload.cancelled()

        XCTAssertEqual(payload["type"] as? String, "cancelled")
        XCTAssertEqual(payload["format"] as? String, "UNKNOWN")
        XCTAssertEqual(payload["rawValue"] as? String, "")
    }

    func testErrorPayloadReportsUnknownFormat() {
        let payload = ScannerPayload.error(code: "CAMERA_UNAVAILABLE", message: "nope")

        XCTAssertEqual(payload["type"] as? String, "error")
        XCTAssertEqual(payload["format"] as? String, "UNKNOWN")
        XCTAssertEqual(payload["errorCode"] as? String, "CAMERA_UNAVAILABLE")
        XCTAssertEqual(payload["errorMessage"] as? String, "nope")
    }

    func testBarcodePayloadCarriesTheResolvedFormat() {
        let payload = ScannerPayload.barcode(value: "TICKET-1", format: "CODE_128")

        XCTAssertEqual(payload["type"] as? String, "barcode")
        XCTAssertEqual(payload["format"] as? String, "CODE_128")
        XCTAssertEqual(payload["rawValue"] as? String, "TICKET-1")
    }

    // MARK: - B8, interruption and runtime-error recovery

    func testMediaServicesResetIsTreatedAsRecoverable() {
        let error = AVError(.mediaServicesWereReset)

        XCTAssertTrue(ScannerSessionRecovery.isRecoverable(error))
    }

    func testOtherRuntimeErrorsAreNotRecoverable() {
        XCTAssertFalse(ScannerSessionRecovery.isRecoverable(AVError(.sessionNotRunning)))
        XCTAssertFalse(ScannerSessionRecovery.isRecoverable(nil))
    }

    func testInterruptionReasonsMapToDistinctMessages() {
        let inUse = ScannerSessionRecovery.message(for: .videoDeviceInUseByAnotherClient)
        let background = ScannerSessionRecovery.message(for: .videoDeviceNotAvailableInBackground)
        let unknown = ScannerSessionRecovery.message(for: nil)

        XCTAssertNotEqual(inUse, background)
        XCTAssertNotEqual(inUse, unknown)
        XCTAssertFalse(unknown.isEmpty)
    }

    func testRestartBudgetGrantsExactlyItsAllowance() {
        var budget = RestartBudget(maxAttempts: 2)

        XCTAssertTrue(budget.tryAgain())
        XCTAssertTrue(budget.tryAgain())
        XCTAssertFalse(budget.tryAgain())
        XCTAssertEqual(budget.attempts, 2)
    }

    func testRestartBudgetResetRestoresTheAllowance() {
        var budget = RestartBudget(maxAttempts: 1)

        XCTAssertTrue(budget.tryAgain())
        XCTAssertFalse(budget.tryAgain())

        budget.reset()

        XCTAssertEqual(budget.attempts, 0)
        XCTAssertTrue(budget.tryAgain())
    }
}
