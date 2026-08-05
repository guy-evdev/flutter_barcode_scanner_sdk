import AVFoundation
import UIKit

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
    let allowedTypes: [AVMetadataObject.ObjectType]
    /// The requested format names, used to post-filter decoded results.
    ///
    /// AVFoundation cannot tell UPC-A from EAN-13 — `ScannerFormat.allowedTypes` maps both to
    /// `.ean13` — so filtering on `AVMetadataObject.ObjectType` alone lets a request for one
    /// return the other. Decoded results are matched against these names instead.
    let allowedFormatNames: Set<String>
    let strings: ScannerStrings
    let showFlashButton: Bool
    let showCameraSwitchButton: Bool
    let initialCameraPosition: AVCaptureDevice.Position
    let initialTorchEnabled: Bool
    let keepScreenOn: Bool
    let textDirection: UIUserInterfaceLayoutDirection?
    let scanWindowEnabled: Bool
    let scanWindowLeft: CGFloat
    let scanWindowTop: CGFloat
    let scanWindowWidth: CGFloat
    let scanWindowHeight: CGFloat
    let scanWindowCornerRadius: CGFloat
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
            .filter { ScannerFormat.allowedTypes[$0] != nil }
        if requestedFormatNames.isEmpty {
            allowedFormatNames = Set(ScannerFormat.allowedTypes.keys)
            allowedTypes = Array(ScannerFormat.allowedTypes.values)
        } else {
            allowedFormatNames = Set(requestedFormatNames)
            allowedTypes = requestedFormatNames.compactMap { ScannerFormat.allowedTypes[$0] }
        }
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
        scanWindowEnabled = windowMap?["enabled"] as? Bool ?? true
        scanWindowLeft = Self.normalizedCGFloat(
            windowMap?["left"] as? NSNumber,
            fallback: 0.1,
            minimum: 0,
            maximum: 1
        )
        scanWindowTop = Self.normalizedCGFloat(
            windowMap?["top"] as? NSNumber,
            fallback: 0.3,
            minimum: 0,
            maximum: 1
        )
        scanWindowWidth = Self.normalizedCGFloat(
            windowMap?["width"] as? NSNumber,
            fallback: 0.8,
            minimum: 0.05,
            maximum: 1
        )
        scanWindowHeight = Self.normalizedCGFloat(
            windowMap?["height"] as? NSNumber,
            fallback: 0.4,
            minimum: 0.05,
            maximum: 1
        )
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

    /// The scan window in view points.
    ///
    /// The rect arrives already clamped from Dart, so every layer frames the
    /// same region instead of each re-deriving it — the old width/height
    /// factors carried a hidden "equal factors mean square" rule that all three
    /// layers had to reimplement identically.
    func scanWindowRect(in bounds: CGRect) -> CGRect {
        guard scanWindowEnabled, bounds.width > 0, bounds.height > 0 else {
            return .zero
        }
        return CGRect(
            x: scanWindowLeft * bounds.width,
            y: scanWindowTop * bounds.height,
            width: scanWindowWidth * bounds.width,
            height: scanWindowHeight * bounds.height
        )
    }

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

enum ScannerFormat {
    static let allowedTypes: [String: AVMetadataObject.ObjectType] = [
        "QR_CODE": .qr,
        "CODE_128": .code128,
        "CODE_39": .code39,
        "CODE_93": .code93,
        "EAN_13": .ean13,
        "EAN_8": .ean8,
        "UPC_A": .ean13,
        "UPC_E": .upce,
        "ITF": .interleaved2of5,
        "PDF_417": .pdf417,
        "DATA_MATRIX": .dataMatrix,
        "AZTEC": .aztec,
    ]

    static func normalized(
        for type: AVMetadataObject.ObjectType,
        value: String
    ) -> String {
        switch type {
        case .qr: return "QR_CODE"
        case .code128: return "CODE_128"
        case .code39: return "CODE_39"
        case .code93: return "CODE_93"
        case .ean13: return value.count == 13 && value.hasPrefix("0") ? "UPC_A" : "EAN_13"
        case .ean8: return "EAN_8"
        case .upce: return "UPC_E"
        case .interleaved2of5: return "ITF"
        case .pdf417: return "PDF_417"
        case .dataMatrix: return "DATA_MATRIX"
        case .aztec: return "AZTEC"
        default: return ScannerPayload.unknownFormat
        }
    }

    /// The format label to report for a decoded code, or `nil` when it was not requested.
    ///
    /// AVFoundation reports UPC-A barcodes as `.ean13`, and `normalized(for:value:)` relabels
    /// 13-digit leading-zero values as `UPC_A`. Filtering on the metadata type alone therefore
    /// let a request for only `EAN_13` return results labelled `UPC_A`, and a request for only
    /// `UPC_A` match every EAN-13. Post-filtering the decoded label closes both directions.
    static func resolve(
        for type: AVMetadataObject.ObjectType,
        value: String,
        allowedFormatNames: Set<String>
    ) -> String? {
        let format = normalized(for: type, value: value)
        return allowedFormatNames.contains(format) ? format : nil
    }

    /// The requested types the capture session reports as available, in requested order.
    ///
    /// Never widens the request. An empty result means nothing will be detected, which callers
    /// surface as an error rather than substituting a different set — falling back to
    /// `availableMetadataObjectTypes` silently turned a QR-only request into every type the
    /// device can emit, including non-barcode types such as `.face` and `.humanBody`.
    static func supportedTypes(
        requested: [AVMetadataObject.ObjectType],
        available: [AVMetadataObject.ObjectType]
    ) -> [AVMetadataObject.ObjectType] {
        requested.filter { available.contains($0) }
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
    /// Emitted when no requested format is available on the capture device.
    static let unsupportedFormatsCode = "UNSUPPORTED_FORMATS"

    static let unsupportedFormatsMessage =
        "None of the requested barcode formats are available on this capture device."

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
/// Geometry only: values, formats and session state are the caller's to filter first.
enum ScanCandidateSelector {
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
    static func selectNearest(
        candidates: [CGRect?],
        window: CGRect?,
        frameCenter: CGPoint
    ) -> Int? {
        let anchor = window.map { CGPoint(x: $0.midX, y: $0.midY) } ?? frameCenter
        var bestIndex: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for (index, bounds) in candidates.enumerated() {
            guard let bounds, !bounds.isEmpty else {
                // Unpositioned: only usable when there is no window to test it against, and only
                // while nothing positioned has qualified.
                if window == nil, bestIndex == nil {
                    bestIndex = index
                }
                continue
            }
            if let window, !window.intersects(bounds) {
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
