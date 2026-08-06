import AVFoundation
import ImageIO
import UIKit
import Vision

struct ScannerStrings {
    let title: String
    let close: String
    let flashOn: String
    let flashOff: String
    let switchCamera: String
    let cameraPermissionRequired: String
    let cameraUnavailable: String

    init(map: [String: Any]?) {
        title = map?["title"] as? String ?? "Scan Barcode"
        close = map?["close"] as? String ?? "Close"
        flashOn = map?["flashOn"] as? String ?? "Flash on"
        flashOff = map?["flashOff"] as? String ?? "Flash off"
        switchCamera = map?["switchCamera"] as? String ?? "Switch camera"
        cameraPermissionRequired =
            map?["cameraPermissionRequired"] as? String ?? "Camera permission is required"
        cameraUnavailable = map?["cameraUnavailable"] as? String ?? "Camera unavailable"
    }
}

struct ScannerConfig {
    /// The requested format names, used to post-filter decoded results.
    ///
    /// Vision cannot tell UPC-A from EAN-13 — both are the `.ean13` symbology — so filtering on
    /// symbology alone lets a request for one return the other. Decoded results are matched
    /// against these names instead, with the label derived from the value.
    let allowedFormatNames: Set<String>
    let strings: ScannerStrings
    let showFlashButton: Bool
    let showCameraSwitchButton: Bool
    let initialCameraPosition: AVCaptureDevice.Position
    let initialTorchEnabled: Bool
    let keepScreenOn: Bool
    let textDirection: UIUserInterfaceLayoutDirection?
    let scanWindowEnabled: Bool
    let scanWindowWidthFraction: CGFloat
    let scanWindowAspectRatio: CGFloat
    let scanWindowMaxHeightFraction: CGFloat
    let scanWindowHasRect: Bool
    let scanWindowLeft: CGFloat
    let scanWindowTop: CGFloat
    let scanWindowWidth: CGFloat
    let scanWindowHeight: CGFloat
    let scanWindowCornerRadius: CGFloat
    let scanWindowAimMode: String
    let scanConfirmationFrames: Int
    let statusBarTransparent: Bool
    let statusBarBackgroundColor: UIColor?
    let statusBarIconStyle: UIStatusBarStyle
    let appBarTransparent: Bool
    let appBarBackgroundColor: UIColor?
    let appBarForegroundColor: UIColor?
    let overlayColor: UIColor

    init(arguments: [String: Any]) {
        let stringsMap = arguments["strings"] as? [String: Any]
        let uiMap = arguments["uiConfig"] as? [String: Any]
        let windowMap = arguments["scanWindow"] as? [String: Any]
        let statusMap = arguments["statusBarStyle"] as? [String: Any]
        let requestedFormatNames = (arguments["allowedFormats"] as? [String] ?? [])
            .filter { VisionBarcodeFormat.symbologies[$0] != nil }
        allowedFormatNames = requestedFormatNames.isEmpty
            ? Set(VisionBarcodeFormat.symbologies.keys)
            : Set(requestedFormatNames)
        strings = ScannerStrings(map: stringsMap)
        showFlashButton = uiMap?["showFlashButton"] as? Bool ?? true
        showCameraSwitchButton = uiMap?["showCameraSwitchButton"] as? Bool ?? true
        initialCameraPosition =
            (uiMap?["initialCameraLens"] as? String) == "front" ? .front : .back
        initialTorchEnabled = uiMap?["initialTorchEnabled"] as? Bool ?? false
        keepScreenOn = uiMap?["keepScreenOn"] as? Bool ?? false
        if (arguments["textDirection"] as? String) == "rtl" {
            textDirection = .rightToLeft
        } else if (arguments["textDirection"] as? String) == "ltr" {
            textDirection = .leftToRight
        } else {
            textDirection = nil
        }
        let rectMap = windowMap?["rect"] as? [String: Any]
        scanWindowEnabled = windowMap?["enabled"] as? Bool ?? true
        scanWindowWidthFraction = Self.normalizedCGFloat(
            windowMap?["widthFraction"] as? NSNumber,
            fallback: Self.defaultWidthFraction,
            minimum: 0.05,
            maximum: 1
        )
        scanWindowAspectRatio = Self.normalizedCGFloat(
            windowMap?["aspectRatio"] as? NSNumber,
            fallback: Self.defaultAspectRatio,
            minimum: 0.2,
            maximum: 5
        )
        scanWindowMaxHeightFraction = Self.normalizedCGFloat(
            windowMap?["maxHeightFraction"] as? NSNumber,
            fallback: Self.defaultMaxHeightFraction,
            minimum: 0.1,
            maximum: 1
        )
        scanWindowHasRect = rectMap != nil
        scanWindowLeft = Self.normalizedCGFloat(
            rectMap?["left"] as? NSNumber,
            fallback: 0.1,
            minimum: 0,
            maximum: 1
        )
        scanWindowTop = Self.normalizedCGFloat(
            rectMap?["top"] as? NSNumber,
            fallback: 0.3,
            minimum: 0,
            maximum: 1
        )
        scanWindowWidth = Self.normalizedCGFloat(
            rectMap?["width"] as? NSNumber,
            fallback: 0.8,
            minimum: 0.05,
            maximum: 1
        )
        scanWindowHeight = Self.normalizedCGFloat(
            rectMap?["height"] as? NSNumber,
            fallback: 0.4,
            minimum: 0.05,
            maximum: 1
        )
        // An unrecognized mode falls back to the strict one: a mode this version does not know
        // about must never widen what can be reported.
        let requestedAimMode = windowMap?["aimMode"] as? String
        scanWindowAimMode =
            requestedAimMode == Self.aimModeWindow ? Self.aimModeWindow : Self.aimModeCrosshair
        scanConfirmationFrames =
            min(max((arguments["scanConfirmationFrames"] as? NSNumber)?.intValue ?? 2, 1), 10)
        scanWindowCornerRadius = Self.normalizedCGFloat(
            windowMap?["cornerRadius"] as? NSNumber,
            fallback: 18,
            minimum: 0,
            maximum: .greatestFiniteMagnitude
        )
        statusBarTransparent = statusMap?["isTransparent"] as? Bool ?? false
        statusBarBackgroundColor = Self.color(from: statusMap?["backgroundColor"] as? NSNumber)
        let iconBrightness = statusMap?["iconBrightness"] as? String ?? "light"
        statusBarIconStyle = iconBrightness == "dark" ? .darkContent : .lightContent
        appBarTransparent = arguments["appBarTransparent"] as? Bool ?? false
        appBarBackgroundColor = Self.color(from: arguments["appBarBackgroundColor"] as? NSNumber)
        appBarForegroundColor = Self.color(from: arguments["appBarForegroundColor"] as? NSNumber)
        overlayColor =
            Self.color(from: arguments["overlayColor"] as? NSNumber)
            ?? UIColor.black.withAlphaComponent(0.6)
    }

    /// Aim mode where overlapping the window is enough to qualify.
    static let aimModeWindow = "window"

    /// Aim mode where the barcode must contain the window's centre.
    static let aimModeCrosshair = "crosshair"

    static let defaultWidthFraction: CGFloat = 0.8
    static let defaultAspectRatio: CGFloat = 1.5
    static let defaultMaxHeightFraction: CGFloat = 0.9

    /// The scan window in view points, for a preview of `bounds`.
    ///
    /// Mirrors `FlutterBarcodeScannerScanWindow.resolve` in Dart and
    /// `ScannerConfig.scanWindowRect(width:height:)` in Kotlin. The preview is
    /// not measured until it is laid out natively, so the config cannot carry a
    /// resolved rect and each layer resolves the same rule instead.
    /// `ScannerConfigTests` asserts the numbers the other two produce.
    ///
    /// Without an explicit rect the window is centred, `scanWindowWidthFraction`
    /// of the preview wide and that width divided by `scanWindowAspectRatio`
    /// tall, shrunk to fit while keeping its shape. Fractions on both axes made
    /// the window's shape follow the preview's, so one config drew a flat band
    /// in a short embedded preview and a square in the full-screen scanner.
    func scanWindowRect(in bounds: CGRect) -> CGRect {
        guard scanWindowEnabled, bounds.width > 0, bounds.height > 0 else {
            return .zero
        }
        if scanWindowHasRect {
            return CGRect(
                x: scanWindowLeft * bounds.width,
                y: scanWindowTop * bounds.height,
                width: scanWindowWidth * bounds.width,
                height: scanWindowHeight * bounds.height
            )
        }
        var width = scanWindowWidthFraction * bounds.width
        var height = width / scanWindowAspectRatio
        let maxHeight = bounds.height * scanWindowMaxHeightFraction
        if height > maxHeight {
            height = maxHeight
            width = height * scanWindowAspectRatio
        }
        if width > bounds.width {
            width = bounds.width
            height = width / scanWindowAspectRatio
        }
        return CGRect(
            x: (bounds.width - width) / 2,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        )
    }

    /// Whether a candidate must contain the window's centre to qualify.
    var requiresCenterOnBarcode: Bool { scanWindowAimMode == Self.aimModeCrosshair }

    private static func color(from value: NSNumber?) -> UIColor? {
        guard let value else { return nil }
        let intValue = UInt32(truncating: value)
        let alpha = CGFloat((intValue >> 24) & 0xFF) / 255.0
        let red = CGFloat((intValue >> 16) & 0xFF) / 255.0
        let green = CGFloat((intValue >> 8) & 0xFF) / 255.0
        let blue = CGFloat(intValue & 0xFF) / 255.0
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static func normalizedCGFloat(
        _ value: NSNumber?,
        fallback: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        let candidate = value.map { CGFloat($0.doubleValue) } ?? fallback
        guard candidate.isFinite else { return fallback }
        return min(max(candidate, minimum), maximum)
    }
}


/// Builders for the result payloads returned over the method channel.
///
/// Cancelled and error payloads carry `UNKNOWN` rather than a real format. Reporting
/// `QR_CODE` made every cancellation and every camera failure arrive on the Dart side as
/// `FlutterBarcodeScannerFormat.qrCode`.
enum ScannerPayload {
    /// The format reported when no barcode was decoded.
    static let unknownFormat = "UNKNOWN"

    static func barcode(value: String, format: String) -> [String: Any?] {
        [
            "type": "barcode",
            "rawValue": value,
            "format": format,
            "errorCode": NSNull(),
            "errorMessage": NSNull(),
        ]
    }

    static func cancelled() -> [String: Any?] {
        [
            "type": "cancelled",
            "rawValue": "",
            "format": unknownFormat,
            "errorCode": NSNull(),
            "errorMessage": NSNull(),
        ]
    }

    static func error(code: String, message: String) -> [String: Any?] {
        [
            "type": "error",
            "rawValue": "",
            "format": unknownFormat,
            "errorCode": code,
            "errorMessage": message,
        ]
    }
}

/// Diagnostics and recovery policy for capture-session interruptions and runtime errors.
///
/// Neither scanner observed `AVCaptureSessionWasInterrupted`,
/// `AVCaptureSessionInterruptionEnded` or `AVCaptureSessionRuntimeError`, so a phone call,
/// another app taking the camera, or `AVError.mediaServicesWereReset` left a permanently black
/// preview that emitted nothing and never recovered.
enum ScannerSessionRecovery {
    /// Emitted while the system has interrupted the capture session.
    static let interruptedCode = "SESSION_INTERRUPTED"
    /// Emitted for a runtime error the scanner could not recover from.
    static let runtimeErrorCode = "SESSION_RUNTIME_ERROR"
    /// Emitted when no requested format maps to a symbology this package can detect.
    static let unsupportedFormatsCode = "UNSUPPORTED_FORMATS"

    static let unsupportedFormatsMessage =
        "None of the requested barcode formats are supported by the scanner."

    static let resumeFailedMessage =
        "The camera session could not resume after the interruption ended."

    /// Human-readable explanation for an interruption reason.
    static func message(for reason: AVCaptureSession.InterruptionReason?) -> String {
        switch reason {
        case .videoDeviceNotAvailableInBackground:
            return "The camera is unavailable while the app is in the background."
        case .videoDeviceInUseByAnotherClient, .audioDeviceInUseByAnotherClient:
            return "The camera is in use by another app."
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            return "The camera is unavailable while sharing the screen with another app."
        case .videoDeviceNotAvailableDueToSystemPressure:
            return "The camera is unavailable because the device is under system pressure."
        default:
            return "The camera session was interrupted."
        }
    }

    /// Whether a runtime error is the transient reset that restarting the session recovers from.
    static func isRecoverable(_ error: AVError?) -> Bool {
        error?.code == .mediaServicesWereReset
    }
}

/// Bounded allowance for automatic capture-session restarts.
///
/// `AVError.mediaServicesWereReset` is normally transient and clears after one restart, but a
/// device wedged in that state would otherwise be restarted forever.
struct RestartBudget {
    private let maxAttempts: Int

    /// Restarts consumed since construction or the last ``reset()``.
    private(set) var attempts = 0

    init(maxAttempts: Int) {
        self.maxAttempts = maxAttempts
    }

    /// Consumes one restart and returns true, or returns false once the allowance is spent.
    mutating func tryAgain() -> Bool {
        guard attempts < maxAttempts else { return false }
        attempts += 1
        return true
    }

    /// Restores the full allowance after the session has run cleanly again.
    mutating func reset() {
        attempts = 0
    }
}

/// A decoded barcode that passed the value and format gates, awaiting selection.
struct ScanCandidate {
    /// Bounds after `transformedMetadataObject(for:)`, in view coordinates.
    let bounds: CGRect
    let value: String
    let format: String
}

/// Chooses which of a frame's decoded barcodes the scanner reports.
///
/// AVFoundation returns metadata objects in an order that has no relation to what the user is
/// aiming at. Accepting the first object that passed the scan-window test therefore let a
/// neighbouring code on a dense sheet win silently, and the app validated the wrong code.
/// Candidates are ranked by distance from the scan-window centre instead, and the nearest wins.
///
/// A candidate qualifies when its bounds *overlap* the scan window. Requiring the bounds' centre
/// point to be inside the window rejected codes that visibly sat within the overlay, which is why
/// repositioning the camera eventually worked — the user was hunting for the centre to land.
///
/// `requireCenterOnCandidate` inverts that test rather than restoring it: the *candidate* must
/// contain the window's centre, so aiming is a point instead of an area. That is what makes a
/// dense sheet selectable, and it is why the crosshair mode is opt-in — it is unforgiving of
/// shake and slower to acquire when only one code is ever in frame.
///
/// Geometry only: values, formats and session state are the caller's to filter first.
enum ScanCandidateSelector {
    /// Half-width of the crosshair aim region, as a share of the scan window's shorter side.
    ///
    /// Sized to sit inside the gap between stacked barcodes — on a typical sheet the codes are
    /// roughly twice their own height apart — so it forgives a wobbling or partial bounds report
    /// without ever letting a neighbouring code qualify.
    static let aimRadiusFraction: CGFloat = 0.06

    /// The aim radius in view points for a window of `shorterSide` points.
    static func aimRadius(shorterSide: CGFloat) -> CGFloat {
        min(max(shorterSide * aimRadiusFraction, 8), 48)
    }

    /// The index of the candidate to report, or nil when none qualifies.
    ///
    /// - Parameters:
    ///   - candidates: transformed bounds per decoded candidate, in view coordinates, in the
    ///     order AVFoundation supplied them. A nil entry is a candidate whose bounds could not be
    ///     resolved: it never qualifies while `window` applies, and ranks behind every positioned
    ///     candidate when it does not.
    ///   - window: the scan window in view coordinates, or nil when the scan window is disabled or
    ///     has no area. When nil every candidate qualifies and ranking falls back to `frameCenter`
    ///     — nearest to the middle of the preview, which is still a better answer than whichever
    ///     object AVFoundation happened to list first.
    ///   - frameCenter: centre of the preview, used only when `window` is nil.
    ///   - requireCenterOnCandidate: when true a candidate qualifies only if its own bounds reach
    ///     the aim region — a square of half-width `aimRadius` around the window's centre, or the
    ///     preview's when there is none.
    ///   - aimRadius: half-width of that aim region. A region rather than a bare point because
    ///     AVFoundation reports partial and wobbling bounds: a code sitting visibly under the
    ///     crosshair whose reported bounds miss the exact centre pixel would otherwise be
    ///     unscannable no matter how carefully the user aimed. Small enough to sit inside the gap
    ///     between adjacent codes, so a neighbour still cannot qualify.
    static func selectNearest(
        candidates: [CGRect?],
        window: CGRect?,
        frameCenter: CGPoint,
        requireCenterOnCandidate: Bool = false,
        aimRadius: CGFloat = 0
    ) -> Int? {
        let anchor = window.map { CGPoint(x: $0.midX, y: $0.midY) } ?? frameCenter
        var bestIndex: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for (index, bounds) in candidates.enumerated() {
            guard let bounds, !bounds.isEmpty else {
                // Unpositioned: only usable when there is no window to test it against, and only
                // while nothing positioned has qualified.
                // Crosshair aiming never accepts one — there is no way to show it was under
                // the anchor.
                if window == nil, !requireCenterOnCandidate, bestIndex == nil {
                    bestIndex = index
                }
                continue
            }
            if requireCenterOnCandidate {
                let aim = CGRect(
                    x: anchor.x - aimRadius,
                    y: anchor.y - aimRadius,
                    width: aimRadius * 2,
                    height: aimRadius * 2
                )
                if !bounds.insetBy(dx: -0.5, dy: -0.5).intersects(aim.insetBy(dx: -0.5, dy: -0.5)) {
                    continue
                }
            } else if let window, !window.intersects(bounds) {
                continue
            }
            let dx = bounds.midX - anchor.x
            let dy = bounds.midY - anchor.y
            let distance = (dx * dx + dy * dy).squareRoot()
            // Strictly nearer, so the earliest candidate wins a tie and selection stays stable
            // across frames.
            if bestIndex == nil || distance < bestDistance {
                bestIndex = index
                bestDistance = distance
            }
        }
        return bestIndex
    }
}

/// Focus and exposure configuration for barcode scanning.
///
/// The plugin previously locked the capture device only to toggle the torch: it set no
/// `focusMode`, `exposureMode`, `autoFocusRangeRestriction` or subject-area monitoring at all.
/// AVFoundation therefore never re-ran autofocus when the *subject* changed but the scene did
/// not — swapping one barcode for another at the same distance — which is why pulling the camera
/// away and back was what made the next code register. CameraX gives Android continuous AF/AE
/// with metering regions by default, so this asymmetry was entirely iOS's missing configuration.
///
/// iOS only. Nothing here has an Android counterpart to keep in step.
enum ScannerFocus {
    /// Configures continuous autofocus and auto-exposure biased towards close subjects.
    ///
    /// - Parameters:
    ///   - device: the active capture device.
    ///   - point: the aim point in *capture device* coordinates (0…1, origin top-left), normally
    ///     the scan window's centre converted with
    ///     `AVCaptureVideoPreviewLayer.captureDevicePointConverted(fromLayerPoint:)`.
    static func configureForScanning(_ device: AVCaptureDevice, aimingAt point: CGPoint) {
        apply(to: device) {
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            // Barcodes are held close; restricting the sweep to the near half of the range stops
            // autofocus hunting out to infinity between codes.
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            // The notification this enables is what lets a swapped subject re-trigger focus.
            device.isSubjectAreaChangeMonitoringEnabled = true
        }
    }

    /// Re-triggers focus and exposure at `point` without disturbing the rest of the configuration.
    ///
    /// Reassigning the point of interest is what restarts a continuous scan; leaving the mode
    /// alone would let AVFoundation sit on a converged lens position indefinitely.
    static func nudge(_ device: AVCaptureDevice, aimingAt point: CGPoint) {
        apply(to: device) {
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposurePointOfInterestSupported,
               device.isExposureModeSupported(.continuousAutoExposure)
            {
                device.exposurePointOfInterest = point
                device.exposureMode = .continuousAutoExposure
            }
            device.isSubjectAreaChangeMonitoringEnabled = true
        }
    }

    /// The aim point to focus on: the scan window's centre, or the preview's when there is none.
    ///
    /// Returned in layer coordinates; the caller converts to device coordinates through its
    /// preview layer.
    static func aimPoint(scanWindow: CGRect, viewBounds: CGRect) -> CGPoint {
        if scanWindow.isEmpty {
            return CGPoint(x: viewBounds.midX, y: viewBounds.midY)
        }
        return CGPoint(x: scanWindow.midX, y: scanWindow.midY)
    }

    private static func apply(to device: AVCaptureDevice, _ changes: () -> Void) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            changes()
        } catch {
            // A device that cannot be locked keeps whatever configuration it already had; the
            // scanner still runs, it just focuses the way it did before.
            return
        }
    }
}

enum ScannerCamera {
    static func device(
        for position: AVCaptureDevice.Position,
        allowFallback: Bool = true
    ) -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: supportedDeviceTypes,
            mediaType: .video,
            position: position
        )
        if let closeRangeDevice = bestCloseRangeDevice(among: discoverySession.devices) {
            return closeRangeDevice
        }

        if let defaultVideoDevice = AVCaptureDevice.default(for: .video),
           position == .unspecified || defaultVideoDevice.position == position
        {
            return defaultVideoDevice
        }

        if let matchingDevice = discoverySession.devices.first {
            return matchingDevice
        }

        guard allowFallback else { return nil }
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: supportedDeviceTypes,
            mediaType: .video,
            position: .unspecified
        ).devices.first
    }

    /// The device best able to focus on a barcode held close to the lens.
    ///
    /// `AVCaptureDevice.default(for: .video)` returns the wide camera, whose minimum focus
    /// distance on recent iPhones makes a small code held close fail to focus at all.
    static func bestCloseRangeDevice(among devices: [AVCaptureDevice]) -> AVCaptureDevice? {
        let ranked = devices.map {
            CloseRangeRank(deviceType: $0.deviceType, minimumFocusDistance: $0.minimumFocusDistance)
        }
        guard let index = preferredCloseRangeIndex(among: ranked) else { return nil }
        return devices[index]
    }

    /// The comparable properties of a capture device for close-range ranking.
    struct CloseRangeRank {
        let deviceType: AVCaptureDevice.DeviceType
        /// Millimetres, or -1 when the device does not report one.
        let minimumFocusDistance: Int
    }

    /// Index of the device to prefer for close-range scanning, or nil when the list is empty.
    ///
    /// A virtual device that contains an ultra-wide constituent wins first: the system switches
    /// to the ultra-wide by itself once the subject comes nearer than the wide lens can focus,
    /// which keeps the wide lens's detail at normal distances and still focuses up close.
    /// Otherwise the smallest reported minimum focus distance wins. Devices that report no
    /// distance rank last, since preferring an unknown over a measured one is a guess.
    static func preferredCloseRangeIndex(among devices: [CloseRangeRank]) -> Int? {
        if let virtualIndex = devices.firstIndex(where: {
            closeRangeVirtualDeviceTypes.contains($0.deviceType)
        }) {
            return virtualIndex
        }

        var bestIndex: Int?
        var bestDistance = Int.max
        for (index, device) in devices.enumerated() where device.minimumFocusDistance > 0 {
            if device.minimumFocusDistance < bestDistance {
                bestIndex = index
                bestDistance = device.minimumFocusDistance
            }
        }
        if let bestIndex {
            return bestIndex
        }
        return devices.isEmpty ? nil : 0
    }

    /// Virtual devices whose constituents include the ultra-wide camera.
    private static let closeRangeVirtualDeviceTypes: Set<AVCaptureDevice.DeviceType> = [
        .builtInTripleCamera,
        .builtInDualWideCamera,
    ]

    static var hasFrontAndBackCameras: Bool {
        device(for: .front, allowFallback: false) != nil
            && device(for: .back, allowFallback: false) != nil
    }

    private static var supportedDeviceTypes: [AVCaptureDevice.DeviceType] {
        [
            .builtInWideAngleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInTrueDepthCamera,
            .builtInTripleCamera,
        ]
    }
}

/// Maps `AVAuthorizationStatus` onto the Dart permission contract.
///
/// iOS reports its own state directly, unlike Android, but two mappings are
/// deliberate rather than mechanical:
///
/// - `.denied` becomes `permanentlyDenied`. iOS shows the camera prompt exactly
///   once per install, so a refusal is already final — reporting plain `denied`
///   would invite callers to ask again and silently do nothing.
/// - `restricted` has no Android equivalent. It means a policy such as Screen
///   Time or MDM forbids the camera, and even Settings will not help.
enum ScannerPermission {
    static let granted = "granted"
    static let permanentlyDenied = "permanentlyDenied"
    static let restricted = "restricted"
    static let notDetermined = "notDetermined"

    /// Maps a raw authorization status. Separated for testability.
    static func status(for authorization: AVAuthorizationStatus) -> String {
        switch authorization {
        case .authorized: return granted
        case .notDetermined: return notDetermined
        case .restricted: return restricted
        case .denied: return permanentlyDenied
        @unknown default: return permanentlyDenied
        }
    }

    /// The current status, without prompting.
    static func currentStatus() -> String {
        status(for: AVCaptureDevice.authorizationStatus(for: .video))
    }

    /// Requests access, prompting only when the system still would.
    static func request(_ completion: @escaping (String) -> Void) {
        let current = AVCaptureDevice.authorizationStatus(for: .video)
        guard current == .notDetermined else {
            completion(status(for: current))
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { _ in
            DispatchQueue.main.async {
                completion(currentStatus())
            }
        }
    }

    /// Opens this app's page in Settings.
    static func openAppSettings(_ completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url)
        else {
            completion(false)
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { opened in
                completion(opened)
            }
        }
    }
}

/// Holds the display-sleep lock while a scanner is running.
///
/// Reference counted because the embedded view and the full-screen scanner can
/// both be alive at once: a plain boolean would let whichever stopped first
/// release a lock the other still needs.
enum ScannerIdleTimer {
    private static var holders = 0

    static func acquire() {
        holders += 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    static func release() {
        holders = max(0, holders - 1)
        if holders == 0 {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    /// Current hold count. Exposed for tests.
    static var activeHolders: Int { holders }

    /// Drops every hold. Exposed for tests.
    static func resetForTesting() {
        holders = 0
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

/// Holds a scan back until the same value has been selected several times in a row.
///
/// A camera decodes many times a second, so the first code to satisfy the scan window wins — even
/// when the phone is still sweeping towards the one the user meant. A code caught in passing does
/// not stay the best candidate, so requiring a short run of agreement discards it while costing
/// roughly one observation of latency each.
///
/// **An observation is not a frame here.** `AVCaptureMetadataOutput` only calls its delegate when
/// something decodes, so a run is a run of *callbacks*. Android counts analyzer frames, which
/// arrive whether or not anything decodes.
///
/// A callback that decodes nothing useful does **not** break the run. AVFoundation reports an
/// unpredictable subset of the barcodes it can see, so demanding strictly back-to-back
/// observations means a run almost never completes and the scan takes seconds. Progress is
/// discarded only after `staleAfter`, which is what separates "a gap of a few frames" from "the
/// user looked away".
///
/// Not thread-safe: call it from the single queue that handles metadata output.
struct ScanConfirmationTracker {
    /// How many consecutive observations of one value are needed, at least 1.
    private let required: Int

    /// How long a run survives without a new observation.
    private let staleAfter: TimeInterval

    private var currentValue: String?
    private var streak = 0
    private var lastObservedAt: TimeInterval = 0

    init(requiredObservations: Int, staleAfter: TimeInterval = 0.5) {
        required = max(requiredObservations, 1)
        self.staleAfter = staleAfter
    }

    /// Records an observation and reports whether it completes a run.
    ///
    /// - Parameters:
    ///   - value: the selected candidate's value.
    ///   - now: a monotonic clock reading, normally `ProcessInfo.processInfo.systemUptime`.
    ///   - ambiguous: whether more than one barcode was inside the scan window. When it was, the
    ///     run has to be twice as long: several codes in the frame is exactly when a hasty result
    ///     is the wrong one, and the extra observations give the user time to centre the code they
    ///     meant.
    /// - Returns: true once `value` has been observed the required number of times in a row, at
    ///   which point the run is consumed — the next observation starts a new one, so a barcode
    ///   held in frame does not re-report on every subsequent callback.
    mutating func observe(
        _ value: String,
        now: TimeInterval,
        ambiguous: Bool = false
    ) -> Bool {
        if currentValue != value || now - lastObservedAt > staleAfter {
            currentValue = value
            streak = 0
        }
        lastObservedAt = now
        streak += 1
        let needed = ambiguous ? required * Self.ambiguousMultiplier : required
        if streak >= needed {
            reset()
            return true
        }
        return false
    }

    /// How much longer the run must be when several barcodes share the window.
    static let ambiguousMultiplier = 2

    /// Drops any run in progress. Call when detection pauses, stops, or is reconfigured.
    mutating func reset() {
        currentValue = nil
        streak = 0
        lastObservedAt = 0
    }
}

// MARK: - Vision detection

/// Maps between this package's format names and Vision's symbologies.
///
/// Vision is used instead of `AVCaptureMetadataOutput` because that API cannot serve this
/// package's core job. Apple's Technical Note TN2325 states that only a **single** 1-dimensional
/// code is returned per delegate callback, and that it is "the center-most decodable barcode in
/// the `rectOfInterest`" — so the scanner never receives a candidate list to rank, and the code it
/// receives is chosen by AVFoundation against the whole camera frame rather than by the user's
/// aim. 2D codes fare slightly better at a limit of four. Vision returns every barcode it finds,
/// which is what Android's ML Kit does and what the selection logic here has always assumed.
enum VisionBarcodeFormat {
    /// Vision symbologies for a requested format name.
    ///
    /// UPC-A has no symbology of its own: Vision reports those codes as EAN-13, exactly as
    /// AVFoundation did, so both names map to `.ean13` and the label is resolved from the value.
    static let symbologies: [String: [VNBarcodeSymbology]] = [
        "QR_CODE": [.qr],
        "CODE_128": [.code128],
        "CODE_39": [.code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum],
        "CODE_93": [.code93, .code93i],
        "EAN_13": [.ean13],
        "EAN_8": [.ean8],
        "UPC_A": [.ean13],
        "UPC_E": [.upce],
        "ITF": [.itf14, .i2of5, .i2of5Checksum],
        "PDF_417": [.pdf417],
        "DATA_MATRIX": [.dataMatrix],
        "AZTEC": [.aztec],
    ]

    /// The package format name for a Vision symbology, or nil when it is one this package does
    /// not model.
    ///
    /// EAN-13 and UPC-A share a symbology, so the label is derived from the value the same way the
    /// AVFoundation path did: a 13-digit value beginning with zero is a UPC-A.
    static func formatName(for symbology: VNBarcodeSymbology, value: String) -> String? {
        switch symbology {
        case .qr: return "QR_CODE"
        case .code128: return "CODE_128"
        case .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum: return "CODE_39"
        case .code93, .code93i: return "CODE_93"
        case .ean13: return value.count == 13 && value.hasPrefix("0") ? "UPC_A" : "EAN_13"
        case .ean8: return "EAN_8"
        case .upce: return "UPC_E"
        case .itf14, .i2of5, .i2of5Checksum: return "ITF"
        case .pdf417: return "PDF_417"
        case .dataMatrix: return "DATA_MATRIX"
        case .aztec: return "AZTEC"
        default: return nil
        }
    }

    /// The symbologies to request for a set of format names, deduplicated and order-stable.
    ///
    /// An empty request means "every format this package models", never "every symbology Vision
    /// supports" — asking for symbologies the package cannot label would surface results it would
    /// then have to discard.
    static func requestedSymbologies(for names: Set<String>) -> [VNBarcodeSymbology] {
        let keys = names.isEmpty ? Set(symbologies.keys) : names
        var seen = Set<VNBarcodeSymbology>()
        var ordered: [VNBarcodeSymbology] = []
        for key in keys.sorted() {
            for symbology in symbologies[key] ?? [] where !seen.contains(symbology) {
                seen.insert(symbology)
                ordered.append(symbology)
            }
        }
        return ordered
    }
}

/// Converts between Vision's coordinate space and the capture/preview spaces.
///
/// Vision reports `boundingBox` normalized to the image with a **bottom-left** origin, while
/// `AVCaptureVideoPreviewLayer.layerRectConverted(fromMetadataOutputRect:)` — the only conversion
/// that correctly accounts for `videoGravity` cropping — expects a normalized rect with a
/// **top-left** origin. Flipping between them is a single subtraction, and getting it wrong puts
/// every reported barcode in the wrong place, so it lives here with unit tests rather than inline.
enum VisionGeometry {
    /// A Vision bounding box as a metadata-output-style rect.
    static func metadataRect(fromVisionBoundingBox box: CGRect) -> CGRect {
        CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }

    /// A scan window in metadata-output space as a Vision region of interest.
    ///
    /// The same flip in the other direction. Vision clamps its region to the unit square, so a
    /// window resolved against a preview that is cropped by `videoGravity` is intersected here
    /// rather than left to produce an empty region.
    static func visionRegionOfInterest(fromMetadataRect rect: CGRect) -> CGRect {
        let flipped = CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let clamped = flipped.intersection(unit)
        return clamped.isNull || clamped.isEmpty ? unit : clamped
    }

    /// The image orientation to hand Vision for a capture rotation, in degrees clockwise from the
    /// device's native landscape sensor orientation.
    ///
    /// Passing the orientation is cheaper than rotating the pixel buffer, and it keeps
    /// `boundingBox` in the same space the preview is showing.
    static func imageOrientation(forVideoRotationAngle angle: CGFloat) -> CGImagePropertyOrientation {
        switch Int(angle.rounded()) % 360 {
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .up
        }
    }
}

/// Runs `VNDetectBarcodesRequest` over capture frames and reports every barcode it finds.
///
/// One request is in flight at a time and frames arriving during it are dropped, because barcode
/// detection is slower than the capture rate and a queue of stale frames would add latency without
/// adding information. `minimumInterval` throttles further: a scan does not become useful faster
/// than a person can move the phone, and every skipped frame is battery saved on a workload that
/// runs for hours.
///
/// Not thread-safe. Drive it from a single serial queue.
final class VisionBarcodeDetector {
    /// A barcode found in a frame, in normalized metadata-output space (top-left origin).
    struct Detection {
        let value: String
        let format: String
        let metadataRect: CGRect
    }

    /// Shortest gap between two detection passes.
    private let minimumInterval: TimeInterval

    private var symbologies: [VNBarcodeSymbology]
    private var regionOfInterest: CGRect
    private var isBusy = false
    private var nextAllowedRun: TimeInterval = 0

    init(allowedFormatNames: Set<String>, minimumInterval: TimeInterval = 1.0 / 15.0) {
        symbologies = VisionBarcodeFormat.requestedSymbologies(for: allowedFormatNames)
        regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
        self.minimumInterval = minimumInterval
    }

    /// Replaces the requested formats.
    func updateFormats(_ allowedFormatNames: Set<String>) {
        symbologies = VisionBarcodeFormat.requestedSymbologies(for: allowedFormatNames)
    }

    /// Limits detection to `rect`, given in normalized metadata-output space.
    ///
    /// Not only an optimisation: Vision spends its time on the region, so a window keeps it off
    /// the parts of the sensor frame the preview never shows.
    func updateRegionOfInterest(metadataRect rect: CGRect?) {
        guard let rect else {
            regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
            return
        }
        regionOfInterest = VisionGeometry.visionRegionOfInterest(fromMetadataRect: rect)
    }

    /// Frees the detector to accept another frame. Call when detection pauses or stops.
    func reset() {
        isBusy = false
        nextAllowedRun = 0
    }

    /// Runs detection over `pixelBuffer` unless a pass is already running or throttled.
    ///
    /// `completion` runs on Vision's own queue with every barcode found, and is not called at all
    /// for a dropped frame.
    func detect(
        pixelBuffer: CVPixelBuffer,
        videoRotationAngle: CGFloat,
        now: TimeInterval,
        completion: @escaping ([Detection]) -> Void
    ) {
        guard !isBusy, now >= nextAllowedRun else { return }
        isBusy = true
        nextAllowedRun = now + minimumInterval

        let request = VNDetectBarcodesRequest { [weak self] request, _ in
            defer { self?.isBusy = false }
            let observations = request.results as? [VNBarcodeObservation] ?? []
            completion(Self.detections(from: observations))
        }
        if !symbologies.isEmpty {
            request.symbologies = symbologies
        }
        request.regionOfInterest = regionOfInterest

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: VisionGeometry.imageOrientation(forVideoRotationAngle: videoRotationAngle),
            options: [:]
        )
        do {
            try handler.perform([request])
        } catch {
            // A frame Vision cannot read is not worth surfacing: the next one is milliseconds
            // away, and reporting it would turn a transient hiccup into a UI event.
            isBusy = false
        }
    }

    /// The observations this package can label, as detections.
    static func detections(from observations: [VNBarcodeObservation]) -> [Detection] {
        observations.compactMap { observation in
            guard
                let value = observation.payloadStringValue,
                !value.isEmpty,
                let format = VisionBarcodeFormat.formatName(
                    for: observation.symbology,
                    value: value
                )
            else {
                return nil
            }
            return Detection(
                value: value,
                format: format,
                metadataRect: VisionGeometry.metadataRect(
                    fromVisionBoundingBox: observation.boundingBox
                )
            )
        }
    }
}
