import AVFoundation
import Flutter
import Foundation
import UIKit

public final class FlutterBarcodeScannerSdkPlugin: NSObject, FlutterPlugin {
    private var methodChannel: FlutterMethodChannel?
    private weak var presenter: UIViewController?
    private weak var activeScannerViewController: ScannerViewController?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = FlutterBarcodeScannerSdkPlugin()
        instance.presenter = registrar.viewController
        let channel = FlutterMethodChannel(
            name: "flutter_barcode_scanner_sdk/methods",
            binaryMessenger: registrar.messenger()
        )
        instance.methodChannel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.register(
            EmbeddedScannerPlatformViewFactory(messenger: registrar.messenger()),
            withId: "flutter_barcode_scanner_sdk/scanner_view"
        )
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "scan":
            handleScan(call, result: result)
        case "requestCameraPermission":
            requestCameraPermission { granted in
                result(granted)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleScan(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if activeScannerViewController != nil {
            result(
                FlutterError(
                    code: "SCAN_IN_PROGRESS",
                    message: "A scan is already in progress",
                    details: nil
                )
            )
            return
        }

        requestCameraPermission { [weak self] granted in
            guard let self else { return }
            let config = ScannerConfig(arguments: call.arguments as? [String: Any] ?? [:])

            guard granted else {
                result(
                    FlutterError(
                        code: "PERMISSION_DENIED",
                        message: config.strings.cameraPermissionRequired,
                        details: nil
                    )
                )
                return
            }

            guard let presenter = self.resolvePresenter() else {
                result(
                    FlutterError(
                        code: "NO_VIEW_CONTROLLER",
                        message: "Scanner is not attached to a view controller",
                        details: nil
                    )
                )
                return
            }

            let scannerViewController = ScannerViewController(config: config) { [weak self] payload in
                self?.activeScannerViewController = nil
                result(payload)
            }
            self.activeScannerViewController = scannerViewController
            scannerViewController.modalPresentationStyle = .fullScreen
            presenter.present(scannerViewController, animated: false)
        }
    }

    private func requestCameraPermission(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }

    private func resolvePresenter() -> UIViewController? {
        if let presenter = topPresenter(from: presenter) {
            return presenter
        }

        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }

        for scene in scenes {
            let keyWindow =
                scene.windows.first(where: \.isKeyWindow)
                ?? scene.windows.first(where: { !$0.isHidden && $0.windowLevel == .normal })
                ?? scene.windows.first
            if let presenter = topPresenter(from: keyWindow?.rootViewController) {
                return presenter
            }
        }

        let keyWindow =
            UIApplication.shared.windows.first(where: \.isKeyWindow)
            ?? UIApplication.shared.windows.first(where: { !$0.isHidden && $0.windowLevel == .normal })
            ?? UIApplication.shared.windows.first
        return topPresenter(from: keyWindow?.rootViewController)
    }

    private func topPresenter(from controller: UIViewController?) -> UIViewController? {
        if let navigationController = controller as? UINavigationController {
            return topPresenter(from: navigationController.visibleViewController)
        }
        if let tabController = controller as? UITabBarController {
            return topPresenter(from: tabController.selectedViewController)
        }
        if let presented = controller?.presentedViewController {
            return topPresenter(from: presented)
        }
        return controller
    }
}

private struct ScannerStrings {
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

private struct ScannerConfig {
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
        let formatMap: [String: AVMetadataObject.ObjectType] = [
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

        let allAllowedTypes = Array(formatMap.values)
        let allowedFormats = (arguments["allowedFormats"] as? [String] ?? [])
            .compactMap { formatMap[$0] }
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
        scanWindowWidthFactor =
            CGFloat((windowMap?["widthFactor"] as? NSNumber)?.doubleValue ?? 0.58)
        scanWindowHeightFactor =
            CGFloat((windowMap?["heightFactor"] as? NSNumber)?.doubleValue ?? 0.58)
        scanWindowCornerRadius =
            CGFloat((windowMap?["cornerRadius"] as? NSNumber)?.doubleValue ?? 18)
        statusBarTransparent = statusMap?["isTransparent"] as? Bool ?? false
        statusBarBackgroundColor =
            Self.color(from: statusMap?["backgroundColor"] as? NSNumber)
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
}

private final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let config: ScannerConfig
    private let completion: ([String: Any?]) -> Void
    // Serialize every capture session and metadata output mutation on this queue.
    private let sessionQueue = DispatchQueue(label: "com.eventer.flutter_barcode_scanner_sdk.scanner")

    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let metadataOutput = AVCaptureMetadataOutput()
    private let overlayView = ScannerOverlayView()
    private let statusBarFillView = UIView()
    private let topBar = UIView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let flashButton = UIButton(type: .system)
    private let switchButton = UIButton(type: .system)

    private var currentInput: AVCaptureDeviceInput?
    private var currentCameraPosition: AVCaptureDevice.Position
    private var currentScanWindow: CGRect = .zero
    private var hasCompleted = false
    private var hasConfiguredSession = false
    private var isTorchEnabled = false
    private lazy var requestedMetadataTypes: [AVMetadataObject.ObjectType] = {
        var uniqueTypes: [AVMetadataObject.ObjectType] = []
        for type in config.allowedTypes where !uniqueTypes.contains(type) {
            uniqueTypes.append(type)
        }
        return uniqueTypes
    }()

    init(config: ScannerConfig, completion: @escaping ([String: Any?]) -> Void) {
        self.config = config
        self.completion = completion
        self.currentCameraPosition = config.initialCameraPosition
        self.isTorchEnabled = config.initialTorchEnabled
        super.init(nibName: nil, bundle: nil)
        modalPresentationCapturesStatusBarAppearance = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        config.statusBarIconStyle
    }

    override func viewDidLoad() {
        super.viewDidLoad()
#if targetEnvironment(simulator)
        view.backgroundColor = .lightGray
#else
        view.backgroundColor = .black
#endif
        if let direction = config.textDirection {
            view.semanticContentAttribute =
                direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        }
        buildUi()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasConfiguredSession {
            hasConfiguredSession = true
            setupSessionAndStart()
        } else if !session.isRunning {
            sessionQueue.async {
                self.session.startRunning()
                if self.config.initialTorchEnabled {
                    DispatchQueue.main.async {
                        self.setTorch(enabled: true)
                    }
                }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
        DispatchQueue.main.async {
            self.setTorch(enabled: false)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        let topInset = view.safeAreaInsets.top
        let topBarHeight: CGFloat = 56
        let isRightToLeft =
            (config.textDirection ?? view.effectiveUserInterfaceLayoutDirection) == .rightToLeft
        statusBarFillView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: topInset)
        topBar.frame = CGRect(x: 0, y: topInset, width: view.bounds.width, height: topBarHeight)

        let buttonPadding: CGFloat = 12
        closeButton.frame = CGRect(
            x: isRightToLeft ? view.bounds.width - buttonPadding - 36 : buttonPadding,
            y: 10,
            width: 36,
            height: 36
        )
        let closeSystemName = isRightToLeft ? "chevron.forward" : "chevron.backward"
        closeButton.setImage(
            UIImage(systemName: closeSystemName)?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        flashButton.frame = CGRect(x: buttonPadding, y: topInset + topBarHeight + 16, width: 44, height: 44)
        switchButton.frame = CGRect(
            x: view.bounds.width - buttonPadding - 44,
            y: topInset + topBarHeight + 16,
            width: 44,
            height: 44
        )
        flashButton.isHidden = !config.showFlashButton
        switchButton.isHidden = !config.showCameraSwitchButton

        titleLabel.frame = CGRect(
            x: 56,
            y: 10,
            width: view.bounds.width - 112,
            height: 36
        )

        if config.scanWindowEnabled {
            let widthBasedSize = view.bounds.width * config.scanWindowWidthFactor
            let heightBasedSize = view.bounds.height * config.scanWindowHeightFactor
            let usesSquareWindow = abs(config.scanWindowWidthFactor - config.scanWindowHeightFactor) < 0.001
            let scanWidth: CGFloat
            let scanHeight: CGFloat
            if usesSquareWindow {
                let squareSize = min(widthBasedSize, heightBasedSize)
                scanWidth = squareSize
                scanHeight = squareSize
            } else {
                scanWidth = widthBasedSize
                scanHeight = heightBasedSize
            }
            currentScanWindow = CGRect(
                x: (view.bounds.width - scanWidth) / 2,
                y: (view.bounds.height - scanHeight) / 2,
                width: scanWidth,
                height: scanHeight
            )
        } else {
            currentScanWindow = .zero
        }
        overlayView.frame = view.bounds
        overlayView.overlayColor = config.overlayColor
        overlayView.scanWindow = currentScanWindow
        overlayView.cornerRadius = config.scanWindowCornerRadius
        overlayView.isHidden = !config.scanWindowEnabled
        overlayView.setNeedsDisplay()
    }

    private func buildUi() {
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        overlayView.backgroundColor = .clear
        view.addSubview(overlayView)

        let topBackground =
            config.appBarTransparent
            ? UIColor.clear
            : (
                config.appBarBackgroundColor
                    ?? (config.statusBarTransparent ? UIColor.clear : config.statusBarBackgroundColor)
                    ?? UIColor(red: 0.04, green: 0.11, blue: 0.35, alpha: 1)
            )
        statusBarFillView.backgroundColor =
            config.statusBarTransparent ? .clear : (config.statusBarBackgroundColor ?? topBackground)
        view.addSubview(statusBarFillView)
        topBar.backgroundColor = topBackground
        view.addSubview(topBar)

        let foreground = config.appBarForegroundColor ?? .white

        let closeImage = UIImage(systemName: "chevron.backward")?.withRenderingMode(.alwaysTemplate)
        closeButton.setImage(closeImage, for: .normal)
        closeButton.tintColor = foreground
        closeButton.addTarget(self, action: #selector(cancelScan), for: .touchUpInside)
        topBar.addSubview(closeButton)

        let flashBackground = UIColor.black.withAlphaComponent(0.35)
        configureOverlayButton(
            flashButton,
            systemName: "bolt.fill",
            tintColor: foreground,
            backgroundColor: flashBackground
        )
        flashButton.accessibilityLabel = config.strings.flashOn
        flashButton.addTarget(self, action: #selector(toggleFlash), for: .touchUpInside)
        view.addSubview(flashButton)

        configureOverlayButton(
            switchButton,
            systemName: "camera.rotate",
            tintColor: foreground,
            backgroundColor: flashBackground
        )
        switchButton.accessibilityLabel = config.strings.switchCamera
        switchButton.addTarget(self, action: #selector(toggleCamera), for: .touchUpInside)
        view.addSubview(switchButton)

        titleLabel.text = config.strings.title
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = foreground
        topBar.addSubview(titleLabel)
    }

    private func setupSessionAndStart() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            guard let device = self.camera(for: self.currentCameraPosition) else {
                self.session.commitConfiguration()
#if targetEnvironment(simulator)
                return
#else
                DispatchQueue.main.async {
                    self.finishWithError(self.config.strings.cameraUnavailable)
                }
                return
#endif
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.currentInput = input
                }

                if self.session.canAddOutput(self.metadataOutput) {
                    self.session.addOutput(self.metadataOutput)
                    self.metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                }
                self.session.commitConfiguration()
                self.applyMetadataObjectTypes()
                self.session.startRunning()

                if self.config.initialTorchEnabled {
                    DispatchQueue.main.async {
                        self.setTorch(enabled: true)
                    }
                }
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.finishWithError(error.localizedDescription)
                }
            }
        }
    }

    @objc private func cancelScan() {
        finishWithPayload(
            [
                "type": "cancelled",
                "rawValue": "",
                "format": "QR_CODE",
                "errorCode": NSNull(),
                "errorMessage": NSNull(),
            ]
        )
    }

    @objc private func toggleFlash() {
        setTorch(enabled: !isTorchEnabled)
    }

    @objc private func toggleCamera() {
        currentCameraPosition = currentCameraPosition == .back ? .front : .back
        sessionQueue.async {
            self.session.stopRunning()
            self.session.beginConfiguration()
            if let input = self.currentInput {
                self.session.removeInput(input)
            }
            do {
                guard let device = self.camera(for: self.currentCameraPosition) else {
                    self.session.commitConfiguration()
                    return
                }
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.currentInput = input
                }
                self.session.commitConfiguration()
                self.session.startRunning()
            } catch {
                self.session.commitConfiguration()
            }
        }
    }

    private func camera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if let defaultVideoDevice = AVCaptureDevice.default(for: .video) {
            if position == .unspecified || defaultVideoDevice.position == position {
                return defaultVideoDevice
            }
        }

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: supportedDeviceTypes(),
            mediaType: .video,
            position: position
        )
        if let matchingDevice = discoverySession.devices.first {
            return matchingDevice
        }

        let unspecifiedDiscoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: supportedDeviceTypes(),
            mediaType: .video,
            position: .unspecified
        )
        return unspecifiedDiscoverySession.devices.first
    }

    private func applyMetadataObjectTypes() {
        let availableTypes = metadataOutput.availableMetadataObjectTypes
        let selectedTypes: [AVMetadataObject.ObjectType]
        if availableTypes.isEmpty {
            selectedTypes = requestedMetadataTypes
        } else {
            let filteredTypes = requestedMetadataTypes.filter { availableTypes.contains($0) }
            selectedTypes = filteredTypes.isEmpty ? availableTypes : filteredTypes
        }
        metadataOutput.metadataObjectTypes = selectedTypes
    }

    private func supportedDeviceTypes() -> [AVCaptureDevice.DeviceType] {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInTrueDepthCamera,
        ]
        if #available(iOS 13.0, *) {
            deviceTypes.append(.builtInTripleCamera)
        }
        return deviceTypes
    }

    private func setTorch(enabled: Bool) {
        guard let device = currentInput?.device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if enabled {
                try device.setTorchModeOn(level: 1)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
            isTorchEnabled = enabled
            let symbol = enabled ? "bolt.slash.fill" : "bolt.fill"
            flashButton.setImage(
                UIImage(systemName: symbol)?.withRenderingMode(.alwaysTemplate),
                for: .normal
            )
            flashButton.accessibilityLabel =
                enabled ? config.strings.flashOff : config.strings.flashOn
        } catch {
            return
        }
    }

    private func configureOverlayButton(
        _ button: UIButton,
        systemName: String,
        tintColor: UIColor,
        backgroundColor: UIColor
    ) {
        button.setImage(
            UIImage(systemName: systemName)?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        button.tintColor = tintColor
        button.backgroundColor = backgroundColor
        button.layer.cornerRadius = 22
        button.clipsToBounds = true
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        if hasCompleted {
            return
        }

        for metadataObject in metadataObjects {
            guard
                let code = metadataObject as? AVMetadataMachineReadableCodeObject,
                let transformed = previewLayer.transformedMetadataObject(for: code)
                    as? AVMetadataMachineReadableCodeObject,
                let stringValue = transformed.stringValue,
                !stringValue.isEmpty,
                !config.scanWindowEnabled || isCodeCenteredInScanWindow(transformed)
            else {
                continue
            }

            finishWithPayload(
                [
                    "type": "barcode",
                    "rawValue": stringValue,
                    "format": normalizedFormat(for: transformed.type),
                    "errorCode": NSNull(),
                    "errorMessage": NSNull(),
                ]
            )
            break
        }
    }

    private func isCodeCenteredInScanWindow(_ code: AVMetadataMachineReadableCodeObject) -> Bool {
        if !config.scanWindowEnabled || currentScanWindow.isEmpty {
            return true
        }
        return currentScanWindow.contains(CGPoint(x: code.bounds.midX, y: code.bounds.midY))
    }

    private func finishWithError(_ message: String) {
        finishWithPayload(
            [
                "type": "error",
                "rawValue": "",
                "format": "QR_CODE",
                "errorCode": "CAMERA_UNAVAILABLE",
                "errorMessage": message,
            ]
        )
    }

    private func finishWithPayload(_ payload: [String: Any?]) {
        if hasCompleted {
            return
        }
        hasCompleted = true
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.dismiss(animated: false) {
                    self.completion(payload)
                }
            }
        }
    }

    private func normalizedFormat(for type: AVMetadataObject.ObjectType) -> String {
        switch type {
        case .qr:
            return "QR_CODE"
        case .code128:
            return "CODE_128"
        case .code39:
            return "CODE_39"
        case .code93:
            return "CODE_93"
        case .ean13:
            return "EAN_13"
        case .ean8:
            return "EAN_8"
        case .upce:
            return "UPC_E"
        case .interleaved2of5:
            return "ITF"
        case .pdf417:
            return "PDF_417"
        case .dataMatrix:
            return "DATA_MATRIX"
        case .aztec:
            return "AZTEC"
        default:
            return "QR_CODE"
        }
    }
}

private final class ScannerOverlayView: UIView {
    var scanWindow: CGRect = .zero
    var cornerRadius: CGFloat = 18
    var overlayColor: UIColor = UIColor.black.withAlphaComponent(0.6)

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(overlayColor.cgColor)
        context.fill(bounds)
        context.setBlendMode(.clear)
        let path = UIBezierPath(
            roundedRect: scanWindow,
            cornerRadius: cornerRadius
        )
        context.addPath(path.cgPath)
        context.fillPath()
        context.setBlendMode(.normal)

        UIColor.white.setStroke()
        path.lineWidth = 3
        path.stroke()
    }
}

private final class EmbeddedScannerPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        EmbeddedScannerPlatformView(
            frame: frame,
            viewId: viewId,
            args: args as? [String: Any],
            messenger: messenger
        )
    }
}

private final class EmbeddedScannerPlatformView: NSObject, FlutterPlatformView {
    private let scannerView: EmbeddedScannerNativeView

    init(
        frame: CGRect,
        viewId: Int64,
        args: [String: Any]?,
        messenger: FlutterBinaryMessenger
    ) {
        let channel = FlutterMethodChannel(
            name: "flutter_barcode_scanner_sdk/scanner_view/\(viewId)",
            binaryMessenger: messenger
        )
        let config = ScannerConfig(arguments: args?["config"] as? [String: Any] ?? [:])
        let widgetConfig = args?["widgetConfig"] as? [String: Any]
        let autoStart = args?["autoStart"] as? Bool ?? true
        let autoPauseOnScan = args?["autoPauseOnScan"] as? Bool ?? true
        scannerView = EmbeddedScannerNativeView(
            frame: frame,
            config: config,
            freezePreviewWhenPaused: widgetConfig?["freezePreviewWhenPaused"] as? Bool ?? false,
            autoStart: autoStart,
            autoPauseOnScan: autoPauseOnScan,
            channel: channel
        )
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    func view() -> UIView {
        scannerView
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startCamera":
            scannerView.startCamera()
            result(nil)
        case "stopCamera":
            scannerView.stopCamera()
            result(nil)
        case "pauseDetection":
            scannerView.pauseDetection()
            result(nil)
        case "resumeDetection":
            scannerView.resumeDetection()
            result(nil)
        case "toggleFlash":
            let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool
            result(scannerView.toggleFlash(enabled: enabled))
        case "switchCamera":
            let lens = (call.arguments as? [String: Any])?["lens"] as? String
            scannerView.switchCamera(lens: lens)
            result(nil)
        case "updateConfig":
            let arguments = call.arguments as? [String: Any] ?? [:]
            let widgetConfig = arguments["widgetConfig"] as? [String: Any]
            scannerView.updateConfig(
                ScannerConfig(arguments: arguments),
                autoPauseOnScan: arguments["autoPauseOnScan"] as? Bool,
                freezePreviewWhenPaused: widgetConfig?["freezePreviewWhenPaused"] as? Bool
            )
            result(nil)
        case "dispose":
            scannerView.dispose()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

private final class EmbeddedScannerNativeView: UIView, AVCaptureMetadataOutputObjectsDelegate {
    private var config: ScannerConfig
    private var autoPauseOnScan: Bool
    private var freezePreviewWhenPaused: Bool
    private let channel: FlutterMethodChannel
    // Serialize every capture session and metadata output mutation on this queue.
    private let sessionQueue = DispatchQueue(label: "com.eventer.flutter_barcode_scanner_sdk.embedded")
    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let freezeImageView = UIImageView()
    private let metadataOutput = AVCaptureMetadataOutput()

    private var currentInput: AVCaptureDeviceInput?
    private var currentCameraPosition: AVCaptureDevice.Position
    private var currentScanWindow: CGRect = .zero
    private var shouldStartSession = false
    private var startGeneration = 0
    private var isRunning = false
    private var isDetectionPaused = false
    private var isDisposed = false
    private var isTorchEnabled = false
    private var requestedMetadataTypes: [AVMetadataObject.ObjectType]

    init(
        frame: CGRect,
        config: ScannerConfig,
        freezePreviewWhenPaused: Bool,
        autoStart: Bool,
        autoPauseOnScan: Bool,
        channel: FlutterMethodChannel
    ) {
        self.config = config
        self.freezePreviewWhenPaused = freezePreviewWhenPaused
        self.autoPauseOnScan = autoPauseOnScan
        self.channel = channel
        self.currentCameraPosition = config.initialCameraPosition
        self.isTorchEnabled = config.initialTorchEnabled
        self.requestedMetadataTypes = Self.uniqueTypes(config.allowedTypes)
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
        freezeImageView.contentMode = .scaleToFill
        freezeImageView.isHidden = true
        addSubview(freezeImageView)
        if autoStart {
            startCamera()
        } else {
            emitState("idle")
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        dispose()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        freezeImageView.frame = bounds
        updateScanWindow()
        sessionQueue.async {
            self.applyRectOfInterest()
        }
    }

    func startCamera() {
        guard !isDisposed, !isRunning, !shouldStartSession else { return }
        shouldStartSession = true
        startGeneration += 1
        let generation = startGeneration
        emitState("initializing")
        clearFrozenPreview()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStartSession(generation: generation)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.startGeneration == generation else { return }
                    if granted {
                        self.configureAndStartSession(generation: generation)
                    } else {
                        self.shouldStartSession = false
                        self.emitError("PERMISSION_DENIED", self.config.strings.cameraPermissionRequired)
                        self.emitState("error")
                    }
                }
            }
        default:
            shouldStartSession = false
            emitError("PERMISSION_DENIED", config.strings.cameraPermissionRequired)
            emitState("error")
        }
    }

    func stopCamera(emit: Bool = true) {
        shouldStartSession = false
        startGeneration += 1
        isRunning = false
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.clearFrozenPreview()
                if emit && !self.isDisposed {
                    self.emitState("cameraStopped")
                }
            }
        }
    }

    func pauseDetection() {
        showFrozenPreview()
        isDetectionPaused = true
        if isRunning {
            emitState("detectionPaused")
        }
    }

    func resumeDetection() {
        guard isRunning else {
            emitState("cameraStopped")
            return
        }
        isDetectionPaused = false
        clearFrozenPreview()
        emitState("running")
    }

    func toggleFlash(enabled: Bool?) -> Bool {
        setTorch(enabled: enabled ?? !isTorchEnabled)
        return isTorchEnabled
    }

    func switchCamera(lens: String?) {
        if lens == "front" {
            currentCameraPosition = .front
        } else if lens == "back" {
            currentCameraPosition = .back
        } else {
            currentCameraPosition = currentCameraPosition == .back ? .front : .back
        }
        guard isRunning else { return }
        configureAndStartSession(reconfigure: true)
    }

    func updateConfig(
        _ config: ScannerConfig,
        autoPauseOnScan: Bool?,
        freezePreviewWhenPaused: Bool?
    ) {
        self.config = config
        if let autoPauseOnScan {
            self.autoPauseOnScan = autoPauseOnScan
        }
        if let freezePreviewWhenPaused {
            self.freezePreviewWhenPaused = freezePreviewWhenPaused
            if !freezePreviewWhenPaused {
                clearFrozenPreview()
            } else if isDetectionPaused {
                showFrozenPreview()
            }
        }
        requestedMetadataTypes = Self.uniqueTypes(config.allowedTypes)
        currentCameraPosition = config.initialCameraPosition
        isTorchEnabled = config.initialTorchEnabled
        updateScanWindow()
        sessionQueue.async {
            self.applyMetadataObjectTypes()
            self.applyRectOfInterest()
        }
        if isRunning {
            setTorch(enabled: isTorchEnabled)
        }
    }

    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        let previewLayer = previewLayer
        if Thread.isMainThread {
            previewLayer.session = nil
        } else {
            DispatchQueue.main.async {
                previewLayer.session = nil
            }
        }
        let session = session
        let metadataOutput = metadataOutput
        let channel = channel
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
            metadataOutput.setMetadataObjectsDelegate(nil, queue: nil)
            session.beginConfiguration()
            for input in session.inputs {
                session.removeInput(input)
            }
            for output in session.outputs {
                session.removeOutput(output)
            }
            session.commitConfiguration()
            DispatchQueue.main.async {
                channel.setMethodCallHandler(nil)
                channel.invokeMethod("onState", arguments: "disposed")
            }
        }
    }

    private func configureAndStartSession(reconfigure: Bool = false, generation: Int? = nil) {
        sessionQueue.async {
            if self.isDisposed ||
                (!reconfigure && !self.shouldStartSession) ||
                (reconfigure && !self.isRunning) ||
                (generation != nil && generation != self.startGeneration) {
                return
            }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            if reconfigure, let input = self.currentInput {
                self.session.removeInput(input)
                self.currentInput = nil
            }

            if self.currentInput == nil {
                guard let device = self.camera(for: self.currentCameraPosition) else {
#if targetEnvironment(simulator)
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.shouldStartSession = false
                        self.isRunning = true
                        self.emitState("running")
                    }
                    return
#else
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.shouldStartSession = false
                        self.emitError("CAMERA_UNAVAILABLE", self.config.strings.cameraUnavailable)
                        self.emitState("error")
                    }
                    return
#endif
                }

                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    if self.session.canAddInput(input) {
                        self.session.addInput(input)
                        self.currentInput = input
                    }
                } catch {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.shouldStartSession = false
                        self.emitError("CAMERA_UNAVAILABLE", error.localizedDescription)
                        self.emitState("error")
                    }
                    return
                }
            }

            if !self.session.outputs.contains(self.metadataOutput), self.session.canAddOutput(self.metadataOutput) {
                self.session.addOutput(self.metadataOutput)
                self.metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            }

            self.session.commitConfiguration()
            self.applyMetadataObjectTypes()
            self.applyRectOfInterest()

            if !self.session.isRunning {
                self.session.startRunning()
            }

            DispatchQueue.main.async {
                self.shouldStartSession = false
                self.isRunning = true
                self.setTorch(enabled: self.isTorchEnabled)
                self.emitState(self.isDetectionPaused ? "detectionPaused" : "running")
            }
        }
    }

    private func updateScanWindow() {
        guard config.scanWindowEnabled, bounds.width > 0, bounds.height > 0 else {
            currentScanWindow = .zero
            return
        }
        let widthBasedSize = bounds.width * config.scanWindowWidthFactor
        let heightBasedSize = bounds.height * config.scanWindowHeightFactor
        let usesSquareWindow = abs(config.scanWindowWidthFactor - config.scanWindowHeightFactor) < 0.001
        let scanWidth: CGFloat
        let scanHeight: CGFloat
        if usesSquareWindow {
            let squareSize = min(widthBasedSize, heightBasedSize)
            scanWidth = squareSize
            scanHeight = squareSize
        } else {
            scanWidth = widthBasedSize
            scanHeight = heightBasedSize
        }
        currentScanWindow = CGRect(
            x: (bounds.width - scanWidth) / 2,
            y: (bounds.height - scanHeight) / 2,
            width: scanWidth,
            height: scanHeight
        )
    }

    private func applyMetadataObjectTypes() {
        guard session.outputs.contains(metadataOutput) else { return }
        let availableTypes = metadataOutput.availableMetadataObjectTypes
        let selectedTypes: [AVMetadataObject.ObjectType]
        if availableTypes.isEmpty {
            selectedTypes = requestedMetadataTypes
        } else {
            let filteredTypes = requestedMetadataTypes.filter { availableTypes.contains($0) }
            selectedTypes = filteredTypes.isEmpty ? availableTypes : filteredTypes
        }
        metadataOutput.metadataObjectTypes = selectedTypes
    }

    private func applyRectOfInterest() {
        guard session.outputs.contains(metadataOutput) else { return }
        // AVFoundation can miss long 1D codes when metadata detection is
        // pre-clipped to the visual scan box. Scan the full frame and apply the
        // transformed center-point ROI check in metadataOutput(_:didOutput:from:).
        metadataOutput.rectOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !isDisposed, isRunning, !isDetectionPaused else { return }

        for metadataObject in metadataObjects {
            guard
                let code = metadataObject as? AVMetadataMachineReadableCodeObject,
                let transformed = previewLayer.transformedMetadataObject(for: code)
                    as? AVMetadataMachineReadableCodeObject,
                let stringValue = transformed.stringValue,
                !stringValue.isEmpty,
                !config.scanWindowEnabled || isCodeCenteredInScanWindow(transformed)
            else {
                continue
            }

            if autoPauseOnScan {
                showFrozenPreview()
                isDetectionPaused = true
            }
            emitResult(value: stringValue, type: transformed.type)
            if autoPauseOnScan {
                emitState("detectionPaused")
            }
            break
        }
    }

    private func isCodeCenteredInScanWindow(_ code: AVMetadataMachineReadableCodeObject) -> Bool {
        if !config.scanWindowEnabled || currentScanWindow.isEmpty {
            return true
        }
        return currentScanWindow.contains(CGPoint(x: code.bounds.midX, y: code.bounds.midY))
    }

    private func showFrozenPreview() {
        guard freezePreviewWhenPaused, !bounds.isEmpty else { return }
        DispatchQueue.main.async {
            let wasHidden = self.freezeImageView.isHidden
            self.freezeImageView.isHidden = true
            let renderer = UIGraphicsImageRenderer(bounds: self.bounds)
            let image = renderer.image { context in
                self.layer.render(in: context.cgContext)
            }
            self.freezeImageView.image = image
            self.freezeImageView.isHidden = false
            if wasHidden {
                self.bringSubviewToFront(self.freezeImageView)
            }
        }
    }

    private func clearFrozenPreview() {
        DispatchQueue.main.async {
            self.freezeImageView.image = nil
            self.freezeImageView.isHidden = true
        }
    }

    private func camera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if let defaultVideoDevice = AVCaptureDevice.default(for: .video) {
            if position == .unspecified || defaultVideoDevice.position == position {
                return defaultVideoDevice
            }
        }

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: supportedDeviceTypes(),
            mediaType: .video,
            position: position
        )
        if let matchingDevice = discoverySession.devices.first {
            return matchingDevice
        }

        let unspecifiedDiscoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: supportedDeviceTypes(),
            mediaType: .video,
            position: .unspecified
        )
        return unspecifiedDiscoverySession.devices.first
    }

    private func supportedDeviceTypes() -> [AVCaptureDevice.DeviceType] {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInTrueDepthCamera,
        ]
        if #available(iOS 13.0, *) {
            deviceTypes.append(.builtInTripleCamera)
        }
        return deviceTypes
    }

    private func setTorch(enabled: Bool) {
        guard let device = currentInput?.device, device.hasTorch else {
            isTorchEnabled = false
            return
        }
        do {
            try device.lockForConfiguration()
            if enabled {
                try device.setTorchModeOn(level: 1)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
            isTorchEnabled = enabled
        } catch {
            return
        }
    }

    private func emitResult(value: String, type: AVMetadataObject.ObjectType) {
        emit(
            "onResult",
            [
                "type": "barcode",
                "rawValue": value,
                "format": normalizedFormat(for: type),
                "errorCode": NSNull(),
                "errorMessage": NSNull(),
            ]
        )
    }

    private func emitState(_ state: String) {
        emit("onState", state)
    }

    private func emitError(_ code: String, _ message: String) {
        emit(
            "onError",
            [
                "code": code,
                "message": message,
                "details": NSNull(),
            ]
        )
    }

    private func emit(_ method: String, _ arguments: Any?) {
        DispatchQueue.main.async {
            self.channel.invokeMethod(method, arguments: arguments)
        }
    }

    private func normalizedFormat(for type: AVMetadataObject.ObjectType) -> String {
        switch type {
        case .qr:
            return "QR_CODE"
        case .code128:
            return "CODE_128"
        case .code39:
            return "CODE_39"
        case .code93:
            return "CODE_93"
        case .ean13:
            return "EAN_13"
        case .ean8:
            return "EAN_8"
        case .upce:
            return "UPC_E"
        case .interleaved2of5:
            return "ITF"
        case .pdf417:
            return "PDF_417"
        case .dataMatrix:
            return "DATA_MATRIX"
        case .aztec:
            return "AZTEC"
        default:
            return "QR_CODE"
        }
    }

    private static func uniqueTypes(_ types: [AVMetadataObject.ObjectType]) -> [AVMetadataObject.ObjectType] {
        var uniqueTypes: [AVMetadataObject.ObjectType] = []
        for type in types where !uniqueTypes.contains(type) {
            uniqueTypes.append(type)
        }
        return uniqueTypes
    }
}
