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
            value: "CODE-1",
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
        let payload = ScannerPayload.barcode(value: "CODE-1", format: "CODE_128")

        XCTAssertEqual(payload["type"] as? String, "barcode")
        XCTAssertEqual(payload["format"] as? String, "CODE_128")
        XCTAssertEqual(payload["rawValue"] as? String, "CODE-1")
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

    // MARK: - B21, B22, scan-result selection

    /// A 400x400 window centred in an 800x800 preview.
    private var scanWindow: CGRect { CGRect(x: 200, y: 200, width: 400, height: 400) }
    private var frameCenter: CGPoint { CGPoint(x: 400, y: 400) }

    private func select(_ candidates: [CGRect?], window: CGRect?) -> Int? {
        ScanCandidateSelector.selectNearest(
            candidates: candidates,
            window: window,
            frameCenter: frameCenter
        )
    }

    private func select(_ candidates: [CGRect?]) -> Int? {
        select(candidates, window: scanWindow)
    }

    // B21 — AVFoundation's ordering must not decide the result.

    func testNearestToTheWindowCentreWinsOverAnEarlierCandidate() {
        let neighbour = CGRect(x: 210, y: 210, width: 80, height: 40)
        let aimedAt = CGRect(x: 370, y: 380, width: 60, height: 40)

        XCTAssertEqual(select([neighbour, aimedAt]), 1)
    }

    func testNearestWinsRegardlessOfWhichEndOfTheListItIsOn() {
        let aimedAt = CGRect(x: 370, y: 380, width: 60, height: 40)
        let neighbour = CGRect(x: 210, y: 210, width: 80, height: 40)

        XCTAssertEqual(select([aimedAt, neighbour]), 0)
    }

    func testTheNearestOfSeveralCandidatesWins() {
        let candidates: [CGRect?] = [
            CGRect(x: 205, y: 205, width: 60, height: 30),
            CGRect(x: 520, y: 520, width: 60, height: 30),
            CGRect(x: 390, y: 405, width: 60, height: 30),
            CGRect(x: 240, y: 500, width: 60, height: 30),
        ]

        XCTAssertEqual(select(candidates), 2)
    }

    func testEquallyDistantCandidatesResolveToTheEarliestSoSelectionIsStable() {
        let left = CGRect(x: 300, y: 390, width: 40, height: 20)
        let right = CGRect(x: 460, y: 390, width: 40, height: 20)

        XCTAssertEqual(select([left, right]), 0)
        XCTAssertEqual(select([right, left]), 0)
    }

    // B22 — overlapping the window is enough; the centre point need not be inside it.

    func testACodeOverlappingTheWindowQualifiesEvenWhenItsCentreIsOutside() {
        // A long 1D code crossing the window's left edge: the centre sits well outside.
        let overlapping = CGRect(x: 20, y: 390, width: 240, height: 30)

        XCTAssertFalse(scanWindow.contains(CGPoint(x: overlapping.midX, y: overlapping.midY)))
        XCTAssertEqual(select([overlapping]), 0)
    }

    func testACodeEntirelyOutsideTheWindowNeverQualifies() {
        let outside = CGRect(x: 20, y: 20, width: 160, height: 40)

        XCTAssertNil(select([outside]))
    }

    func testTouchingTheWindowEdgeIsNotOverlapping() {
        let touching = CGRect(x: 100, y: 390, width: 100, height: 20)

        XCTAssertNil(select([touching]))
    }

    func testAnOverlappingCandidateLosesToOneCentredNearerTheWindow() {
        let overlapping = CGRect(x: 20, y: 390, width: 240, height: 30)
        let centred = CGRect(x: 380, y: 390, width: 60, height: 30)

        XCTAssertEqual(select([overlapping, centred]), 1)
    }

    // Unpositioned candidates.

    func testACandidateWithoutBoundsNeverQualifiesWhileTheWindowApplies() {
        XCTAssertNil(select([nil]))
    }

    func testZeroAreaBoundsAreTreatedAsUnpositioned() {
        XCTAssertNil(select([CGRect(x: 400, y: 400, width: 0, height: 0)]))
    }

    func testAPositionedCandidateBeatsAnUnpositionedOneWithNoWindow() {
        let positioned = CGRect(x: 700, y: 700, width: 60, height: 30)

        XCTAssertEqual(select([nil, positioned], window: nil), 1)
    }

    func testAnUnpositionedCandidateIsStillReportedWhenNothingElseQualifies() {
        XCTAssertEqual(select([nil], window: nil), 0)
    }

    // No scan window — ranking falls back to the centre of the preview.

    func testWithoutAWindowTheCandidateNearestThePreviewCentreWins() {
        let edge = CGRect(x: 20, y: 20, width: 60, height: 30)
        let middle = CGRect(x: 370, y: 380, width: 60, height: 40)

        XCTAssertEqual(select([edge, middle], window: nil), 1)
    }

    func testWithoutAWindowNothingIsRejectedForBeingFarAway() {
        let faraway = CGRect(x: 760, y: 760, width: 40, height: 30)

        XCTAssertEqual(select([faraway], window: nil), 0)
    }

    // Degenerate input.

    func testNoCandidatesSelectsNothing() {
        XCTAssertNil(select([]))
        XCTAssertNil(select([], window: nil))
    }

    func testEveryCandidateOutsideTheWindowSelectsNothing() {
        let candidates: [CGRect?] = [
            CGRect(x: 20, y: 20, width: 80, height: 40),
            CGRect(x: 650, y: 650, width: 130, height: 50),
            nil,
        ]

        XCTAssertNil(select(candidates))
    }
}
