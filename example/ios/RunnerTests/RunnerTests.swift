@testable import flutter_barcode_scanner_sdk
import AVFoundation
import Vision
import Flutter
import XCTest

class RunnerTests: XCTestCase {
    func testScannerConfigNormalizesWindowValues() {
        let config = ScannerConfig(
            arguments: [
                "scanWindow": [
                    "widthFraction": Double.infinity,
                    "aspectRatio": 99,
                    "cornerRadius": -4,
                ],
                "uiConfig": ["initialCameraLens": "front"],
            ]
        )

        XCTAssertEqual(config.scanWindowWidthFraction, 0.8)
        XCTAssertEqual(config.scanWindowAspectRatio, 5)
        XCTAssertEqual(config.scanWindowCornerRadius, 0)
        XCTAssertEqual(config.initialCameraPosition, AVCaptureDevice.Position.front)
    }

    // MARK: - Aspect-ratio scan window

    /// The shape has to survive the container. Fractions on both axes did not: the same config
    /// drew a 2.2:1 band in a short embedded preview and a 1:1 square full-screen.
    func testWindowKeepsItsShapeAcrossPreviewAspectRatios() {
        let config = ScannerConfig(arguments: ["scanWindow": ["enabled": true]])

        let tall = config.scanWindowRect(in: CGRect(x: 0, y: 0, width: 400, height: 800))
        let short = config.scanWindowRect(in: CGRect(x: 0, y: 0, width: 400, height: 340))

        XCTAssertEqual(tall.width / tall.height, 1.5, accuracy: 0.001)
        XCTAssertEqual(short.width / short.height, 1.5, accuracy: 0.001)
    }

    func testDefaultWindowIsCentredAtEightyPercentWidthAndThreeToTwo() {
        let config = ScannerConfig(arguments: ["scanWindow": ["enabled": true]])

        let rect = config.scanWindowRect(in: CGRect(x: 0, y: 0, width: 400, height: 800))

        XCTAssertEqual(rect.width, 320, accuracy: 0.001)
        XCTAssertEqual(rect.height, 320 / 1.5, accuracy: 0.001)
        XCTAssertEqual(rect.midX, 200, accuracy: 0.001)
        XCTAssertEqual(rect.midY, 400, accuracy: 0.001)
    }

    func testWindowShrinksRatherThanLosingItsShapeOnAShortPreview() {
        let config = ScannerConfig(
            arguments: ["scanWindow": ["enabled": true, "aspectRatio": 0.5]]
        )

        let rect = config.scanWindowRect(in: CGRect(x: 0, y: 0, width: 400, height: 200))

        XCTAssertEqual(rect.height, 180, accuracy: 0.001)
        XCTAssertEqual(rect.width, 90, accuracy: 0.001)
        XCTAssertEqual(rect.width / rect.height, 0.5, accuracy: 0.001)
    }

    func testExplicitRectOverridesAspectSizing() {
        let config = ScannerConfig(
            arguments: [
                "scanWindow": [
                    "enabled": true,
                    "rect": ["left": 0.1, "top": 0.2, "width": 0.8, "height": 0.4],
                ],
            ]
        )

        let rect = config.scanWindowRect(in: CGRect(x: 0, y: 0, width: 400, height: 800))

        XCTAssertEqual(rect.minX, 40, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 160, accuracy: 0.001)
        XCTAssertEqual(rect.width, 320, accuracy: 0.001)
        XCTAssertEqual(rect.height, 320, accuracy: 0.001)
    }

    func testDisabledWindowIsEmpty() {
        let config = ScannerConfig(arguments: ["scanWindow": ["enabled": false]])

        XCTAssertTrue(
            config.scanWindowRect(in: CGRect(x: 0, y: 0, width: 400, height: 800)).isEmpty
        )
    }

    // MARK: - Aim mode

    /// Crosshair is the default: it is the only rule that cannot report an unaimed barcode.
    func testAimModeDefaultsToCrosshair() {
        let config = ScannerConfig(arguments: [:])

        XCTAssertTrue(config.requiresCenterOnBarcode)
    }

    /// An unrecognized mode must never widen what can be reported.
    func testUnknownAimModeFallsBackToCrosshair() {
        let config = ScannerConfig(arguments: ["scanWindow": ["aimMode": "laser"]])

        XCTAssertTrue(config.requiresCenterOnBarcode)
    }

    func testWindowAimModeIsCarried() {
        let config = ScannerConfig(arguments: ["scanWindow": ["aimMode": "window"]])

        XCTAssertFalse(config.requiresCenterOnBarcode)
    }

    // MARK: - Confirmation frames

    func testConfirmationFramesDefaultsToTwo() {
        XCTAssertEqual(ScannerConfig(arguments: [:]).scanConfirmationFrames, 2)
    }

    func testConfirmationFramesIsClamped() {
        XCTAssertEqual(
            ScannerConfig(arguments: ["scanConfirmationFrames": 0]).scanConfirmationFrames,
            1
        )
        XCTAssertEqual(
            ScannerConfig(arguments: ["scanConfirmationFrames": 99]).scanConfirmationFrames,
            10
        )
    }

    func testTrackerHoldsBackUntilTheRunCompletes() {
        var tracker = ScanConfirmationTracker(requiredObservations: 3)

        XCTAssertFalse(tracker.observe("A", now: 0))
        XCTAssertFalse(tracker.observe("A", now: 0.1))
        XCTAssertTrue(tracker.observe("A", now: 0.2))
    }

    func testTrackerConsumesTheRunSoAHeldCodeDoesNotRepeat() {
        var tracker = ScanConfirmationTracker(requiredObservations: 2)

        XCTAssertFalse(tracker.observe("A", now: 0))
        XCTAssertTrue(tracker.observe("A", now: 0.1))
        XCTAssertFalse(tracker.observe("A", now: 0.2))
        XCTAssertTrue(tracker.observe("A", now: 0.3))
    }

    /// The point of the feature: a code caught while sweeping towards another never confirms.
    func testTrackerDiscardsAValueSweptPast() {
        var tracker = ScanConfirmationTracker(requiredObservations: 2)

        XCTAssertFalse(tracker.observe("PASSING", now: 0))
        XCTAssertFalse(tracker.observe("TARGET", now: 0.1))
        XCTAssertTrue(tracker.observe("TARGET", now: 0.2))
    }

    func testTrackerDiscardsAStaleRun() {
        var tracker = ScanConfirmationTracker(requiredObservations: 2, staleAfter: 0.5)

        XCTAssertFalse(tracker.observe("A", now: 0))
        XCTAssertFalse(tracker.observe("A", now: 10))
        XCTAssertTrue(tracker.observe("A", now: 10.1))
    }

    /// Several codes sharing the window is when a hasty result is most likely to be wrong.
    func testAnAmbiguousFrameNeedsALongerRun() {
        var tracker = ScanConfirmationTracker(requiredObservations: 2)

        XCTAssertFalse(tracker.observe("A", now: 0, ambiguous: true))
        XCTAssertFalse(tracker.observe("A", now: 0.1, ambiguous: true))
        XCTAssertFalse(tracker.observe("A", now: 0.2, ambiguous: true))
        XCTAssertTrue(tracker.observe("A", now: 0.3, ambiguous: true))
    }

    func testAnUnambiguousFrameKeepsTheShortRun() {
        var tracker = ScanConfirmationTracker(requiredObservations: 2)

        XCTAssertFalse(tracker.observe("A", now: 0))
        XCTAssertTrue(tracker.observe("A", now: 0.1))
    }

    /// AVFoundation reports an unpredictable subset, so callbacks that decode nothing useful are
    /// routine. Breaking the run on each one meant a scan took seconds.
    func testAShortGapDoesNotBreakTheRun() {
        var tracker = ScanConfirmationTracker(requiredObservations: 2)

        XCTAssertFalse(tracker.observe("A", now: 0))
        XCTAssertTrue(tracker.observe("A", now: 0.2))
    }

    func testALongGapStillBreaksTheRun() {
        var tracker = ScanConfirmationTracker(requiredObservations: 2, staleAfter: 0.5)

        XCTAssertFalse(tracker.observe("A", now: 0))
        XCTAssertFalse(tracker.observe("A", now: 0.9))
        XCTAssertTrue(tracker.observe("A", now: 1.0))
    }

    func testScannerConfigMapsRequestedFormats() {
        let config = ScannerConfig(
            arguments: ["allowedFormats": ["QR_CODE", "CODE_128"]]
        )

        XCTAssertEqual(config.allowedFormatNames, ["QR_CODE", "CODE_128"])
    }

    func testScannerConfigDropsUnknownFormatNames() {
        let config = ScannerConfig(
            arguments: ["allowedFormats": ["QR_CODE", "NOT_A_FORMAT"]]
        )

        XCTAssertEqual(config.allowedFormatNames, ["QR_CODE"])
    }

    func testScannerConfigWithoutRequestedFormatsAllowsEveryFormat() {
        let config = ScannerConfig(arguments: [:])

        XCTAssertEqual(config.allowedFormatNames, Set(VisionBarcodeFormat.symbologies.keys))
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

    // MARK: - B14, permission contract

    func testAuthorizedMapsToGranted() {
        XCTAssertEqual(ScannerPermission.status(for: .authorized), "granted")
    }

    func testNotDeterminedIsPreserved() {
        XCTAssertEqual(ScannerPermission.status(for: .notDetermined), "notDetermined")
    }

    func testRestrictedIsPreserved() {
        XCTAssertEqual(ScannerPermission.status(for: .restricted), "restricted")
    }

    func testDeniedMapsToPermanentlyDenied() {
        // iOS prompts once per install, so a refusal is already final. Reporting
        // plain "denied" would invite a re-request that silently does nothing.
        XCTAssertEqual(ScannerPermission.status(for: .denied), "permanentlyDenied")
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

    private func select(
        _ candidates: [CGRect?],
        window: CGRect?,
        crosshair: Bool = false,
        aimRadius: CGFloat = 0
    ) -> Int? {
        ScanCandidateSelector.selectNearest(
            candidates: candidates,
            window: window,
            frameCenter: frameCenter,
            requireCenterOnCandidate: crosshair,
            aimRadius: aimRadius
        )
    }

    private func select(
        _ candidates: [CGRect?],
        crosshair: Bool = false,
        aimRadius: CGFloat = 0
    ) -> Int? {
        select(candidates, window: scanWindow, crosshair: crosshair, aimRadius: aimRadius)
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

    // MARK: - Crosshair aiming

    /// The dense-sheet case. A neighbouring code can sit entirely inside the window and still
    /// lose, because the aim point is not on it.
    func testCrosshairRejectsANeighbourInsideTheWindow() {
        let neighbour = CGRect(x: 220, y: 220, width: 80, height: 40)

        XCTAssertEqual(select([neighbour]), 0)
        XCTAssertNil(select([neighbour], crosshair: true))
    }

    func testCrosshairAcceptsTheCodeUnderTheAimPoint() {
        let underAim = CGRect(x: 360, y: 380, width: 80, height: 40)

        XCTAssertTrue(underAim.contains(CGPoint(x: scanWindow.midX, y: scanWindow.midY)))
        XCTAssertEqual(select([underAim], crosshair: true), 0)
    }

    func testCrosshairPicksTheOneUnderTheAimPointNotTheNearest() {
        let nearMiss = CGRect(x: 300, y: 380, width: 40, height: 40)
        let underAim = CGRect(x: 360, y: 380, width: 80, height: 40)

        XCTAssertEqual(select([nearMiss, underAim], crosshair: true), 1)
    }

    func testCrosshairFallsBackToThePreviewCentreWithoutAWindow() {
        let underCentre = CGRect(x: 360, y: 360, width: 80, height: 80)
        let elsewhere = CGRect(x: 20, y: 20, width: 80, height: 40)

        XCTAssertEqual(select([elsewhere, underCentre], window: nil, crosshair: true), 1)
    }

    func testCrosshairNeverAcceptsAnUnpositionedCandidate() {
        XCTAssertEqual(select([nil], window: nil), 0)
        XCTAssertNil(select([nil], window: nil, crosshair: true))
    }

    /// A bare point was too brittle: AVFoundation reports partial and wobbling bounds, so a code
    /// sitting visibly under the crosshair could be unscannable however carefully the user aimed.
    func testCrosshairToleratesBoundsThatMissTheExactCentre() {
        let partial = CGRect(x: 300, y: 380, width: 90, height: 40)

        XCTAssertNil(select([partial], crosshair: true))
        XCTAssertEqual(select([partial], crosshair: true, aimRadius: 24), 0)
    }

    func testTheAimRegionIsStillTooSmallForANeighbour() {
        let neighbour = CGRect(x: 220, y: 220, width: 80, height: 40)

        XCTAssertNil(select([neighbour], crosshair: true, aimRadius: 24))
    }

    func testTheAimRadiusIsClampedToASensibleRange() {
        XCTAssertEqual(ScanCandidateSelector.aimRadius(shorterSide: 10), 8)
        XCTAssertEqual(ScanCandidateSelector.aimRadius(shorterSide: 10_000), 48)
        XCTAssertEqual(ScanCandidateSelector.aimRadius(shorterSide: 193), 11.58, accuracy: 0.01)
    }

    // MARK: - Vision detection

    /// Vision normalizes with a bottom-left origin; the preview layer conversion expects
    /// top-left. Getting this backwards puts every reported barcode in the wrong place.
    func testVisionBoundingBoxFlipsToMetadataSpace() {
        let box = CGRect(x: 0.1, y: 0.7, width: 0.2, height: 0.1)

        let rect = VisionGeometry.metadataRect(fromVisionBoundingBox: box)

        XCTAssertEqual(rect.minX, 0.1, accuracy: 0.0001)
        XCTAssertEqual(rect.minY, 0.2, accuracy: 0.0001)   // 1 - (0.7 + 0.1)
        XCTAssertEqual(rect.width, 0.2, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 0.1, accuracy: 0.0001)
    }

    func testTheFlipIsItsOwnInverse() {
        let original = CGRect(x: 0.25, y: 0.35, width: 0.4, height: 0.2)

        let there = VisionGeometry.metadataRect(fromVisionBoundingBox: original)
        let back = VisionGeometry.visionRegionOfInterest(fromMetadataRect: there)

        XCTAssertEqual(back.minX, original.minX, accuracy: 0.0001)
        XCTAssertEqual(back.minY, original.minY, accuracy: 0.0001)
        XCTAssertEqual(back.height, original.height, accuracy: 0.0001)
    }

    /// A window resolved against a cropped preview can fall outside the unit square; Vision would
    /// reject it, so it is clamped rather than left to disable detection entirely.
    func testAnOutOfBoundsRegionIsClampedNotDropped() {
        let region = VisionGeometry.visionRegionOfInterest(
            fromMetadataRect: CGRect(x: -0.5, y: -0.5, width: 3, height: 3)
        )

        XCTAssertGreaterThan(region.width, 0)
        XCTAssertGreaterThan(region.height, 0)
        XCTAssertLessThanOrEqual(region.maxX, 1.0001)
        XCTAssertLessThanOrEqual(region.maxY, 1.0001)
    }

    func testImageOrientationFollowsTheCaptureRotation() {
        XCTAssertEqual(VisionGeometry.imageOrientation(forVideoRotationAngle: 0), .up)
        XCTAssertEqual(VisionGeometry.imageOrientation(forVideoRotationAngle: 90), .right)
        XCTAssertEqual(VisionGeometry.imageOrientation(forVideoRotationAngle: 180), .down)
        XCTAssertEqual(VisionGeometry.imageOrientation(forVideoRotationAngle: 270), .left)
    }

    /// UPC-A has no symbology of its own — Vision reports it as EAN-13, so the label comes from
    /// the value, exactly as the AVFoundation path did.
    func testUpcAIsDistinguishedFromEan13ByValue() {
        XCTAssertEqual(
            VisionBarcodeFormat.formatName(for: .ean13, value: "0123456789012"),
            "UPC_A"
        )
        XCTAssertEqual(
            VisionBarcodeFormat.formatName(for: .ean13, value: "5901234123457"),
            "EAN_13"
        )
    }

    func testASymbologyThisPackageDoesNotModelIsDropped() {
        XCTAssertNil(VisionBarcodeFormat.formatName(for: .codabar, value: "A123A"))
    }

    /// An empty request means every format this package models — never every symbology Vision
    /// supports, which would surface results that then have to be discarded.
    func testAnEmptyRequestAsksForEveryModelledFormat() {
        let all = VisionBarcodeFormat.requestedSymbologies(for: [])

        XCTAssertTrue(all.contains(.qr))
        XCTAssertTrue(all.contains(.code128))
        XCTAssertFalse(all.contains(.codabar))
    }

    func testRequestedSymbologiesAreDeduplicated() {
        // EAN_13 and UPC_A both map to .ean13.
        let requested = VisionBarcodeFormat.requestedSymbologies(for: ["EAN_13", "UPC_A"])

        XCTAssertEqual(requested, [.ean13])
    }
}