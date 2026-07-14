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
        let allAllowedTypes = Array(ScannerFormat.allowedTypes.values)
        let allowedFormats = (arguments["allowedFormats"] as? [String] ?? [])
            .compactMap { ScannerFormat.allowedTypes[$0] }

        allowedTypes = allowedFormats.isEmpty ? allAllowedTypes : allowedFormats
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
        default: return "UNKNOWN"
        }
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
