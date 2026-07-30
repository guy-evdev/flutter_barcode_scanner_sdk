import AVFoundation
import Flutter
import Foundation
import UIKit

public final class FlutterBarcodeScannerSdkPlugin: NSObject, FlutterPlugin {
    private var methodChannel: FlutterMethodChannel?
    private weak var presenter: UIViewController?
    private weak var activeScannerViewController: ScannerViewController?
    private var isScanPending = false
    private var pendingScanResult: FlutterResult?

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

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        methodChannel?.setMethodCallHandler(nil)
        activeScannerViewController?.dismiss(animated: false)
        finishScan(
            with: FlutterError(
                code: "PLUGIN_DETACHED",
                message: "Scanner plugin detached from the Flutter engine",
                details: nil
            )
        )
        methodChannel = nil
    }

    private func handleScan(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if isScanPending || activeScannerViewController != nil {
            result(
                FlutterError(
                    code: "SCAN_IN_PROGRESS",
                    message: "A scan is already in progress",
                    details: nil
                )
            )
            return
        }

        isScanPending = true
        pendingScanResult = result
        requestCameraPermission { [weak self] granted in
            guard let self else {
                result(
                    FlutterError(
                        code: "PLUGIN_DETACHED",
                        message: "Scanner plugin detached before the scan could start",
                        details: nil
                    )
                )
                return
            }
            let config = ScannerConfig(arguments: call.arguments as? [String: Any] ?? [:])

            guard granted else {
                self.finishScan(
                    with: FlutterError(
                        code: "PERMISSION_DENIED",
                        message: config.strings.cameraPermissionRequired,
                        details: nil
                    )
                )
                return
            }

            guard let presenter = self.resolvePresenter() else {
                self.finishScan(
                    with: FlutterError(
                        code: "NO_VIEW_CONTROLLER",
                        message: "Scanner is not attached to a view controller",
                        details: nil
                    )
                )
                return
            }

            let scannerViewController = ScannerViewController(config: config) { [weak self] payload in
                if let self {
                    self.finishScan(with: payload)
                } else {
                    result(payload)
                }
            }
            self.activeScannerViewController = scannerViewController
            self.isScanPending = false
            scannerViewController.modalPresentationStyle = .fullScreen
            presenter.present(scannerViewController, animated: false)
        }
    }

    private func finishScan(with payload: Any?) {
        let result = pendingScanResult
        pendingScanResult = nil
        activeScannerViewController = nil
        isScanPending = false
        result?(payload)
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

        return nil
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
    private var restartBudget = RestartBudget(maxAttempts: 3)
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
        addSessionObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func addSessionObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded(_:)),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(sessionRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
    }

    /// Resumes the session once the system releases the camera.
    ///
    /// Without this a phone call taken mid-scan left the preview permanently black — the
    /// scanner has no event channel of its own, so an interruption cannot be reported to Dart
    /// and recovering silently is the only useful behaviour.
    // AVFoundation does not document which thread posts these, so every handler hops to the
    // main queue before touching state the rest of the controller owns there.
    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.hasCompleted else { return }
            self.sessionQueue.async {
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            }
        }
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.hasCompleted else { return }
            guard ScannerSessionRecovery.isRecoverable(error), self.restartBudget.tryAgain() else {
                self.finishWithError(
                    error?.localizedDescription ?? self.config.strings.cameraUnavailable,
                    code: ScannerSessionRecovery.runtimeErrorCode
                )
                return
            }
            self.sessionQueue.async {
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            }
        }
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
        updateCameraControlAvailability()

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

            guard let device = ScannerCamera.device(for: self.currentCameraPosition) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.finishWithError(self.config.strings.cameraUnavailable)
                }
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else {
                    throw NSError(
                        domain: "flutter_barcode_scanner_sdk",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "The camera input cannot be added to the capture session."]
                    )
                }
                self.session.addInput(input)
                self.currentInput = input
                self.currentCameraPosition = device.position

                guard self.session.canAddOutput(self.metadataOutput) else {
                    throw NSError(
                        domain: "flutter_barcode_scanner_sdk",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Barcode metadata output is unavailable."]
                    )
                }
                self.session.addOutput(self.metadataOutput)
                self.metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                self.session.commitConfiguration()
                guard !self.applyMetadataObjectTypes().isEmpty else {
                    DispatchQueue.main.async {
                        self.finishWithError(
                            ScannerSessionRecovery.unsupportedFormatsMessage,
                            code: ScannerSessionRecovery.unsupportedFormatsCode
                        )
                    }
                    return
                }
                self.session.startRunning()

                DispatchQueue.main.async {
                    self.updateCameraControlAvailability()
                    if self.config.initialTorchEnabled {
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
        finishWithPayload(ScannerPayload.cancelled())
    }

    @objc private func toggleFlash() {
        setTorch(enabled: !isTorchEnabled)
    }

    @objc private func toggleCamera() {
        let requestedPosition: AVCaptureDevice.Position =
            currentCameraPosition == .back ? .front : .back
        sessionQueue.async {
            let wasRunning = self.session.isRunning
            if wasRunning {
                self.session.stopRunning()
            }
            self.session.beginConfiguration()
            let previousInput = self.currentInput
            do {
                guard let device = ScannerCamera.device(for: requestedPosition, allowFallback: false) else {
                    throw NSError(
                        domain: "flutter_barcode_scanner_sdk",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "The requested camera lens is unavailable."]
                    )
                }
                let input = try AVCaptureDeviceInput(device: device)
                if let previousInput {
                    self.session.removeInput(previousInput)
                }
                guard self.session.canAddInput(input) else {
                    if let previousInput, self.session.canAddInput(previousInput) {
                        self.session.addInput(previousInput)
                    }
                    throw NSError(
                        domain: "flutter_barcode_scanner_sdk",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "The requested camera cannot be added to the capture session."]
                    )
                }
                self.session.addInput(input)
                self.currentInput = input
                self.currentCameraPosition = requestedPosition
                self.session.commitConfiguration()
                if wasRunning {
                    self.session.startRunning()
                }
                DispatchQueue.main.async {
                    self.isTorchEnabled = false
                    self.updateCameraControlAvailability()
                }
            } catch {
                if let previousInput, !self.session.inputs.contains(previousInput), self.session.canAddInput(previousInput) {
                    self.session.addInput(previousInput)
                    self.currentInput = previousInput
                }
                self.session.commitConfiguration()
                if wasRunning {
                    self.session.startRunning()
                }
                DispatchQueue.main.async {
                    self.updateCameraControlAvailability()
                }
            }
        }
    }

    /// Applies exactly the requested formats the session reports as available.
    ///
    /// - Returns: the applied types. Empty means nothing will be detected — the caller must
    ///   surface that rather than fall back to every available type.
    @discardableResult
    private func applyMetadataObjectTypes() -> [AVMetadataObject.ObjectType] {
        let selectedTypes = ScannerFormat.supportedTypes(
            requested: requestedMetadataTypes,
            available: metadataOutput.availableMetadataObjectTypes
        )
        metadataOutput.metadataObjectTypes = selectedTypes
        return selectedTypes
    }

    private func setTorch(enabled: Bool) {
        guard let device = currentInput?.device, device.hasTorch else {
            isTorchEnabled = false
            updateCameraControlAvailability()
            return
        }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if enabled {
                try device.setTorchModeOn(level: 1)
            } else {
                device.torchMode = .off
            }
            isTorchEnabled = enabled
            let symbol = enabled ? "bolt.slash.fill" : "bolt.fill"
            flashButton.setImage(
                UIImage(systemName: symbol)?.withRenderingMode(.alwaysTemplate),
                for: .normal
            )
            flashButton.accessibilityLabel =
                enabled ? config.strings.flashOff : config.strings.flashOn
            updateCameraControlAvailability()
        } catch {
            isTorchEnabled = device.torchMode == .on
            updateCameraControlAvailability()
            return
        }
    }

    private func updateCameraControlAvailability() {
        flashButton.isHidden =
            !config.showFlashButton || currentInput?.device.hasTorch != true
        let flashSymbol = isTorchEnabled ? "bolt.slash.fill" : "bolt.fill"
        flashButton.setImage(
            UIImage(systemName: flashSymbol)?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        flashButton.accessibilityLabel =
            isTorchEnabled ? config.strings.flashOff : config.strings.flashOn
        switchButton.isHidden =
            !config.showCameraSwitchButton || !hasFrontAndBackCameras()
    }

    private func hasFrontAndBackCameras() -> Bool {
        ScannerCamera.hasFrontAndBackCameras
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
                !config.scanWindowEnabled || isCodeCenteredInScanWindow(transformed),
                let format = ScannerFormat.resolve(
                    for: transformed.type,
                    value: stringValue,
                    allowedFormatNames: config.allowedFormatNames
                )
            else {
                continue
            }

            finishWithPayload(ScannerPayload.barcode(value: stringValue, format: format))
            break
        }
    }

    private func isCodeCenteredInScanWindow(_ code: AVMetadataMachineReadableCodeObject) -> Bool {
        if !config.scanWindowEnabled || currentScanWindow.isEmpty {
            return true
        }
        return currentScanWindow.contains(CGPoint(x: code.bounds.midX, y: code.bounds.midY))
    }

    private func finishWithError(_ message: String, code: String = "CAMERA_UNAVAILABLE") {
        finishWithPayload(ScannerPayload.error(code: code, message: message))
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
        let autoStart = args?["autoStart"] as? Bool ?? true
        let autoPauseOnScan = args?["autoPauseOnScan"] as? Bool ?? true
        scannerView = EmbeddedScannerNativeView(
            frame: frame,
            config: config,
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
            scannerView.switchCamera(lens: lens) { error in
                if let error {
                    result(
                        FlutterError(
                            code: "CAMERA_UNAVAILABLE",
                            message: error.localizedDescription,
                            details: nil
                        )
                    )
                } else {
                    result(nil)
                }
            }
        case "updateConfig":
            let arguments = call.arguments as? [String: Any] ?? [:]
            scannerView.updateConfig(
                ScannerConfig(arguments: arguments),
                autoPauseOnScan: arguments["autoPauseOnScan"] as? Bool
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
    private let channel: FlutterMethodChannel
    // Serialize every capture session and metadata output mutation on this queue.
    private let sessionQueue = DispatchQueue(label: "com.eventer.flutter_barcode_scanner_sdk.embedded")
    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let metadataOutput = AVCaptureMetadataOutput()

    private var currentInput: AVCaptureDeviceInput?
    private var currentCameraPosition: AVCaptureDevice.Position
    private var currentScanWindow: CGRect = .zero
    private var shouldStartSession = false
    private var startGeneration = 0
    private var isRunning = false
    private var hasEverStartedSession = false
    private var isDetectionPaused = false
    private var isDisposed = false
    private var isTorchEnabled = false
    private var requestedMetadataTypes: [AVMetadataObject.ObjectType]
    private var restartBudget = RestartBudget(maxAttempts: 3)

    init(
        frame: CGRect,
        config: ScannerConfig,
        autoStart: Bool,
        autoPauseOnScan: Bool,
        channel: FlutterMethodChannel
    ) {
        self.config = config
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
        addSessionObservers()
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
                if emit && !self.isDisposed {
                    self.emitState("cameraStopped")
                }
            }
        }
    }

    func pauseDetection() {
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
        emitState("running")
    }

    func toggleFlash(enabled: Bool?) -> Bool {
        setTorch(enabled: enabled ?? !isTorchEnabled)
        return isTorchEnabled
    }

    func switchCamera(lens: String?, completion: @escaping (Error?) -> Void) {
        let requestedPosition: AVCaptureDevice.Position
        if lens == "front" {
            requestedPosition = .front
        } else if lens == "back" {
            requestedPosition = .back
        } else {
            requestedPosition = currentCameraPosition == .back ? .front : .back
        }

        guard requestedPosition != currentCameraPosition else {
            completion(nil)
            return
        }

        guard ScannerCamera.device(for: requestedPosition, allowFallback: false) != nil else {
            completion(
                NSError(
                    domain: "flutter_barcode_scanner_sdk",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The requested camera lens is unavailable."]
                )
            )
            return
        }

        guard isRunning else {
            currentCameraPosition = requestedPosition
            isTorchEnabled = false
            completion(nil)
            return
        }

        sessionQueue.async {
            let previousInput = self.currentInput
            self.session.beginConfiguration()
            do {
                guard let device = ScannerCamera.device(for: requestedPosition, allowFallback: false) else {
                    throw NSError(
                        domain: "flutter_barcode_scanner_sdk",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "The requested camera lens is unavailable."]
                    )
                }
                let input = try AVCaptureDeviceInput(device: device)
                if let previousInput {
                    self.session.removeInput(previousInput)
                }
                guard self.session.canAddInput(input) else {
                    if let previousInput, self.session.canAddInput(previousInput) {
                        self.session.addInput(previousInput)
                    }
                    throw NSError(
                        domain: "flutter_barcode_scanner_sdk",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "The requested camera cannot be added to the capture session."]
                    )
                }
                self.session.addInput(input)
                self.currentInput = input
                self.currentCameraPosition = requestedPosition
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.isTorchEnabled = false
                    completion(nil)
                }
            } catch {
                if let previousInput,
                    !self.session.inputs.contains(previousInput),
                    self.session.canAddInput(previousInput)
                {
                    self.session.addInput(previousInput)
                    self.currentInput = previousInput
                }
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }

    func updateConfig(
        _ config: ScannerConfig,
        autoPauseOnScan: Bool?
    ) {
        self.config = config
        if let autoPauseOnScan {
            self.autoPauseOnScan = autoPauseOnScan
        }
        requestedMetadataTypes = Self.uniqueTypes(config.allowedTypes)
        if !hasEverStartedSession {
            currentCameraPosition = config.initialCameraPosition
            isTorchEnabled = config.initialTorchEnabled
        }
        updateScanWindow()
        sessionQueue.async {
            let appliedTypes = self.applyMetadataObjectTypes()
            self.applyRectOfInterest()
            // The session keeps running: a later updateConfig with a supported format set
            // recovers, so reporting the error without forcing the error state is honest.
            if appliedTypes.isEmpty, self.session.outputs.contains(self.metadataOutput) {
                DispatchQueue.main.async {
                    self.emitError(
                        ScannerSessionRecovery.unsupportedFormatsCode,
                        ScannerSessionRecovery.unsupportedFormatsMessage
                    )
                }
            }
        }
        if isRunning {
            setTorch(enabled: isTorchEnabled)
        }
    }

    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        NotificationCenter.default.removeObserver(self)
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
                guard let device = ScannerCamera.device(for: self.currentCameraPosition) else {
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
                    guard self.session.canAddInput(input) else {
                        throw NSError(
                            domain: "flutter_barcode_scanner_sdk",
                            code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "The camera input cannot be added to the capture session."]
                        )
                    }
                    self.session.addInput(input)
                    self.currentInput = input
                    self.currentCameraPosition = device.position
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

            if !self.session.outputs.contains(self.metadataOutput) {
                guard self.session.canAddOutput(self.metadataOutput) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.shouldStartSession = false
                        self.emitError("CAMERA_UNAVAILABLE", "Barcode metadata output is unavailable.")
                        self.emitState("error")
                    }
                    return
                }
                self.session.addOutput(self.metadataOutput)
                self.metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            }

            self.session.commitConfiguration()
            let appliedTypes = self.applyMetadataObjectTypes()
            self.applyRectOfInterest()

            guard !appliedTypes.isEmpty else {
                DispatchQueue.main.async {
                    self.shouldStartSession = false
                    self.emitError(
                        ScannerSessionRecovery.unsupportedFormatsCode,
                        ScannerSessionRecovery.unsupportedFormatsMessage
                    )
                    self.emitState("error")
                }
                return
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }

            DispatchQueue.main.async {
                self.shouldStartSession = false
                self.isRunning = true
                self.hasEverStartedSession = true
                self.restartBudget.reset()
                self.setTorch(enabled: self.isTorchEnabled)
                self.emitState(self.isDetectionPaused ? "detectionPaused" : "running")
            }
        }
    }

    private func addSessionObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(sessionWasInterrupted(_:)),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded(_:)),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(sessionRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
    }

    // AVFoundation does not document which thread posts these notifications, so every handler
    // hops to the main queue before touching state the rest of the view owns there.

    /// Reports a system interruption — a phone call, another app taking the camera, screen
    /// sharing — that the Flutter-side lifecycle handling cannot observe.
    ///
    /// No state is emitted: the scanner has no state that describes "interrupted", and every
    /// existing value would misdescribe it. `interruptionEnded` re-emits the running state
    /// once the camera comes back.
    @objc private func sessionWasInterrupted(_ notification: Notification) {
        let reason = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int)
            .flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isDisposed, self.isRunning else { return }
            self.emitError(
                ScannerSessionRecovery.interruptedCode,
                ScannerSessionRecovery.message(for: reason)
            )
        }
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isDisposed, self.isRunning else { return }
            self.resumeAfterInterruption()
        }
    }

    private func resumeAfterInterruption() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
            let resumed = self.session.isRunning
            DispatchQueue.main.async {
                guard !self.isDisposed, self.isRunning else { return }
                if resumed {
                    self.emitState(self.isDetectionPaused ? "detectionPaused" : "running")
                } else {
                    self.emitError(
                        ScannerSessionRecovery.interruptedCode,
                        ScannerSessionRecovery.resumeFailedMessage
                    )
                    self.emitState("error")
                }
            }
        }
    }

    /// Recovers from `AVError.mediaServicesWereReset` by restarting, and reports anything else.
    ///
    /// Without this, a media-services reset left the preview black forever with no error.
    @objc private func sessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isDisposed else { return }
            guard ScannerSessionRecovery.isRecoverable(error),
                self.isRunning,
                self.restartBudget.tryAgain()
            else {
                self.isRunning = false
                self.emitError(
                    ScannerSessionRecovery.runtimeErrorCode,
                    error?.localizedDescription ?? self.config.strings.cameraUnavailable
                )
                self.emitState("error")
                return
            }
            self.restartAfterRuntimeError(error)
        }
    }

    private func restartAfterRuntimeError(_ error: AVError?) {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
            let restarted = self.session.isRunning
            DispatchQueue.main.async {
                guard !self.isDisposed else { return }
                if restarted {
                    self.emitState(self.isDetectionPaused ? "detectionPaused" : "running")
                } else {
                    self.isRunning = false
                    self.emitError(
                        ScannerSessionRecovery.runtimeErrorCode,
                        error?.localizedDescription ?? self.config.strings.cameraUnavailable
                    )
                    self.emitState("error")
                }
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

    /// Applies exactly the requested formats the session reports as available.
    ///
    /// - Returns: the applied types. Empty means nothing will be detected — the caller must
    ///   surface that rather than fall back to every available type.
    @discardableResult
    private func applyMetadataObjectTypes() -> [AVMetadataObject.ObjectType] {
        guard session.outputs.contains(metadataOutput) else { return [] }
        let selectedTypes = ScannerFormat.supportedTypes(
            requested: requestedMetadataTypes,
            available: metadataOutput.availableMetadataObjectTypes
        )
        metadataOutput.metadataObjectTypes = selectedTypes
        return selectedTypes
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
                !config.scanWindowEnabled || isCodeCenteredInScanWindow(transformed),
                let format = ScannerFormat.resolve(
                    for: transformed.type,
                    value: stringValue,
                    allowedFormatNames: config.allowedFormatNames
                )
            else {
                continue
            }

            if autoPauseOnScan {
                isDetectionPaused = true
            }
            emitResult(value: stringValue, format: format)
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

    private func setTorch(enabled: Bool) {
        guard let device = currentInput?.device, device.hasTorch else {
            isTorchEnabled = false
            return
        }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if enabled {
                try device.setTorchModeOn(level: 1)
            } else {
                device.torchMode = .off
            }
            isTorchEnabled = enabled
        } catch {
            return
        }
    }

    private func emitResult(value: String, format: String) {
        emit("onResult", ScannerPayload.barcode(value: value, format: format))
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

    private static func uniqueTypes(_ types: [AVMetadataObject.ObjectType]) -> [AVMetadataObject.ObjectType] {
        var uniqueTypes: [AVMetadataObject.ObjectType] = []
        for type in types where !uniqueTypes.contains(type) {
            uniqueTypes.append(type)
        }
        return uniqueTypes
    }
}
