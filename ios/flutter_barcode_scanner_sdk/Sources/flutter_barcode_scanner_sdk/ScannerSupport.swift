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
        title = map?["title"] as? String ?? "Scan Ticket"
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
    let textDirection: UIUserInterfaceLayoutDirection?
    let scanWindowEnabled: Bool
    let scanWindowWidthFactor: CGFloat
    let scanWindowHeightFactor: CGFloat
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
        if (arguments["textDirection"] as? String) == "rtl" {
            textDirection = .rightToLeft
        } else if (arguments["textDirection"] as? String) == "ltr" {
            textDirection = .leftToRight
        } else {
            textDirection = nil
        }
        scanWindowEnabled = windowMap?["enabled"] as? Bool ?? true
        scanWindowWidthFactor = Self.normalizedCGFloat(
            windowMap?["widthFactor"] as? NSNumber,
            fallback: 0.58,
            minimum: 0.2,
            maximum: 0.95
        )
        scanWindowHeightFactor = Self.normalizedCGFloat(
            windowMap?["heightFactor"] as? NSNumber,
            fallback: 0.58,
            minimum: 0.2,
            maximum: 0.9
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

enum ScannerCamera {
    static func device(
        for position: AVCaptureDevice.Position,
        allowFallback: Bool = true
    ) -> AVCaptureDevice? {
        if let defaultVideoDevice = AVCaptureDevice.default(for: .video),
           position == .unspecified || defaultVideoDevice.position == position
        {
            return defaultVideoDevice
        }

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: supportedDeviceTypes,
            mediaType: .video,
            position: position
        )
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
