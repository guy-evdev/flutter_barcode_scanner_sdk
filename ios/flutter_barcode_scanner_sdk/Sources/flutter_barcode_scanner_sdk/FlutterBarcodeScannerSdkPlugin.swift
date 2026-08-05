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
        case "checkCameraPermission":
            result(ScannerPermission.currentStatus())
        case "requestCameraPermission":
            ScannerPermission.request { status in
                result(status)
            }
        case "openAppSettings":
            ScannerPermission.openAppSettings { opened in
                result(opened)
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
        ScannerPermission.request { status in
            completion(status == ScannerPermission.granted)
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

private final class ScannerViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let config: ScannerConfig
    private lazy var confirmationTracker =
        ScanConfirmationTracker(requiredObservations: config.scanConfirmationFrames)
    private let completion: ([String: Any?]) -> Void
    // Serialize every capture session and metadata output mutation on this queue.
    private let sessionQueue = DispatchQueue(label: "com.eventer.flutter_barcode_scanner_sdk.scanner")

    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let videoOutput = AVCaptureVideoDataOutput()
    /// Detection runs here so a slow frame never blocks capture or the main thread.
    private let detectionQueue = DispatchQueue(
        label: "com.eventer.flutter_barcode_scanner_sdk.scanner.detect"
    )
    private lazy var detector = VisionBarcodeDetector(
        allowedFormatNames: config.allowedFormatNames
    )
    /// Rotation the capture connection is delivering, kept in step with the preview.
    private var captureRotationAngle: CGFloat = 90
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
    private var holdsIdleTimer = false

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
        if config.keepScreenOn {
            ScannerIdleTimer.acquire()
            holdsIdleTimer = true
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if holdsIdleTimer {
            ScannerIdleTimer.release()
        }
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
        // Posted only while `isSubjectAreaChangeMonitoringEnabled` is set, which
        // `ScannerFocus.configureForScanning` does once the input is attached.
        center.addObserver(
            self,
            selector: #selector(subjectAreaDidChange(_:)),
            name: AVCaptureDevice.subjectAreaDidChangeNotification,
            object: nil
        )
    }

    /// Configures continuous autofocus and exposure on the scan window's centre.
    ///
    /// The layout is read on the main queue and the device is configured back on the session
    /// queue, so this is safe to call from either.
    private func configureFocus(for device: AVCaptureDevice) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.hasCompleted else { return }
            let devicePoint = self.previewLayer.captureDevicePointConverted(
                fromLayerPoint: ScannerFocus.aimPoint(
                    scanWindow: self.currentScanWindow,
                    viewBounds: self.view.bounds
                )
            )
            self.sessionQueue.async {
                ScannerFocus.configureForScanning(device, aimingAt: devicePoint)
            }
        }
    }

    /// Re-runs autofocus when the subject changes but the scene does not — one barcode swapped
    /// for another at the same distance, which is the dense-sheet case.
    @objc private func subjectAreaDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.hasCompleted, let device = self.currentInput?.device else {
                return
            }
            let devicePoint = self.previewLayer.captureDevicePointConverted(
                fromLayerPoint: ScannerFocus.aimPoint(
                    scanWindow: self.currentScanWindow,
                    viewBounds: self.view.bounds
                )
            )
            self.sessionQueue.async {
                ScannerFocus.nudge(device, aimingAt: devicePoint)
            }
        }
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

        currentScanWindow = config.scanWindowRect(in: view.bounds)
        overlayView.frame = view.bounds
        overlayView.overlayColor = config.overlayColor
        overlayView.scanWindow = currentScanWindow
        overlayView.cornerRadius = config.scanWindowCornerRadius
        overlayView.showsCrosshair = config.requiresCenterOnBarcode
        overlayView.isHidden = !config.scanWindowEnabled
        overlayView.setNeedsDisplay()
        applyDetectionRegion()
        alignCaptureRotation()
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
                self.configureFocus(for: device)

                guard self.session.canAddOutput(self.videoOutput) else {
                    throw NSError(
                        domain: "flutter_barcode_scanner_sdk",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Barcode metadata output is unavailable."]
                    )
                }
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.session.addOutput(self.videoOutput)
                self.videoOutput.setSampleBufferDelegate(self, queue: self.detectionQueue)
                self.session.commitConfiguration()
                guard !VisionBarcodeFormat.requestedSymbologies(
                    for: self.config.allowedFormatNames
                ).isEmpty else {
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
                self.configureFocus(for: input.device)
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

    /// Keeps the capture connection's rotation in step with the preview's.
    private func alignCaptureRotation() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let angle: CGFloat
            if #available(iOS 17.0, *) {
                angle = self.previewLayer.connection?.videoRotationAngle ?? 90
            } else {
                switch self.previewLayer.connection?.videoOrientation {
                case .landscapeRight: angle = 0
                case .portraitUpsideDown: angle = 270
                case .landscapeLeft: angle = 180
                default: angle = 90
                }
            }
            self.detectionQueue.async { self.captureRotationAngle = angle }
        }
    }

    /// Points Vision at the scan window, so it never spends time on the part of the sensor frame
    /// the preview crops away.
    private func applyDetectionRegion() {
        guard let window = activeScanWindow, view.bounds.width > 0, view.bounds.height > 0 else {
            detectionQueue.async { [detector] in detector.updateRegionOfInterest(metadataRect: nil) }
            return
        }
        let generous = window.insetBy(dx: -window.width / 2, dy: -window.height / 2)
        let metadataRect = previewLayer.metadataOutputRectConverted(fromLayerRect: generous)
        detectionQueue.async { [detector] in
            detector.updateRegionOfInterest(metadataRect: metadataRect)
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !hasCompleted, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        detector.detect(
            pixelBuffer: pixelBuffer,
            videoRotationAngle: captureRotationAngle,
            now: ProcessInfo.processInfo.systemUptime
        ) { [weak self] detections in
            guard !detections.isEmpty else { return }
            DispatchQueue.main.async {
                self?.handle(detections: detections)
            }
        }
    }

    /// Selects and reports one barcode from a frame's detections.
    private func handle(detections: [VisionBarcodeDetector.Detection]) {
        guard !hasCompleted else { return }

        let candidates: [ScanCandidate] = detections.map {
            ScanCandidate(
                bounds: previewLayer.layerRectConverted(fromMetadataOutputRect: $0.metadataRect),
                value: $0.value,
                format: $0.format
            )
        }
        let window = activeScanWindow
        let selectedIndex = ScanCandidateSelector.selectNearest(
            candidates: candidates.map { $0.bounds },
            window: window,
            frameCenter: CGPoint(x: view.bounds.midX, y: view.bounds.midY),
            requireCenterOnCandidate: config.requiresCenterOnBarcode,
            aimRadius: ScanCandidateSelector.aimRadius(
                shorterSide: min(
                    window?.width ?? .greatestFiniteMagnitude,
                    window?.height ?? .greatestFiniteMagnitude
                )
            )
        )
        guard let selectedIndex else { return }

        let selected = candidates[selectedIndex]
        let codesInWindow = candidates.filter { candidate in
            window.map { $0.intersects(candidate.bounds) } ?? true
        }.count
        let fired = confirmationTracker.observe(
            selected.value,
            now: ProcessInfo.processInfo.systemUptime,
            ambiguous: !config.requiresCenterOnBarcode && codesInWindow > 1
        )
        guard fired else { return }
        finishWithPayload(ScannerPayload.barcode(value: selected.value, format: selected.format))
    }

    /// The scan window to select against, or nil when it is disabled or has no area.
    private var activeScanWindow: CGRect? {
        guard config.scanWindowEnabled, !currentScanWindow.isEmpty else { return nil }
        return currentScanWindow
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

    /// Whether to mark the aim point, drawn under crosshair aiming.
    ///
    /// Without it the mode changes what gets scanned with nothing on screen to explain why a
    /// code sitting inside the frame was ignored.
    var showsCrosshair = false

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

        guard showsCrosshair else { return }
        let arm: CGFloat = 12
        let gap: CGFloat = 4
        let centre = CGPoint(x: scanWindow.midX, y: scanWindow.midY)
        let crosshair = UIBezierPath()
        crosshair.move(to: CGPoint(x: centre.x - arm, y: centre.y))
        crosshair.addLine(to: CGPoint(x: centre.x - gap, y: centre.y))
        crosshair.move(to: CGPoint(x: centre.x + gap, y: centre.y))
        crosshair.addLine(to: CGPoint(x: centre.x + arm, y: centre.y))
        crosshair.move(to: CGPoint(x: centre.x, y: centre.y - arm))
        crosshair.addLine(to: CGPoint(x: centre.x, y: centre.y - gap))
        crosshair.move(to: CGPoint(x: centre.x, y: centre.y + gap))
        crosshair.addLine(to: CGPoint(x: centre.x, y: centre.y + arm))
        crosshair.lineWidth = 2
        crosshair.lineCapStyle = .round
        crosshair.stroke()
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

private final class EmbeddedScannerNativeView: UIView, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var config: ScannerConfig
    private lazy var confirmationTracker =
        ScanConfirmationTracker(requiredObservations: config.scanConfirmationFrames)
    private var autoPauseOnScan: Bool
    private let channel: FlutterMethodChannel
    // Serialize every capture session and metadata output mutation on this queue.
    private let sessionQueue = DispatchQueue(label: "com.eventer.flutter_barcode_scanner_sdk.embedded")
    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let videoOutput = AVCaptureVideoDataOutput()
    /// Detection runs here so a slow frame never blocks capture or the main thread.
    private let detectionQueue = DispatchQueue(
        label: "com.eventer.flutter_barcode_scanner_sdk.embedded.detect"
    )
    private lazy var detector = VisionBarcodeDetector(
        allowedFormatNames: config.allowedFormatNames
    )

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
        applyDetectionRegion()
    }

    /// Points Vision at the scan window, so it never spends time on the part of the sensor frame
    /// the preview crops away.
    private func applyDetectionRegion() {
        guard let window = activeScanWindow, bounds.width > 0, bounds.height > 0 else {
            detectionQueue.async { [detector] in detector.updateRegionOfInterest(metadataRect: nil) }
            return
        }
        // Generous around the window: a long 1D code needs its quiet zones inside the region, and
        // clipping tightly to the drawn box is what made edge codes fail before.
        let generous = window.insetBy(dx: -window.width / 2, dy: -window.height / 2)
        let metadataRect = previewLayer.metadataOutputRectConverted(fromLayerRect: generous)
        detectionQueue.async { [detector] in
            detector.updateRegionOfInterest(metadataRect: metadataRect)
        }
    }

    /// Keeps the capture connection's rotation in step with the preview's.
    ///
    /// Without it Vision is handed frames in the sensor's native landscape orientation while the
    /// preview shows portrait, and every reported bounding box lands rotated.
    private func alignCaptureRotation() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let angle: CGFloat
            if #available(iOS 17.0, *) {
                angle = self.previewLayer.connection?.videoRotationAngle ?? 90
            } else {
                // Pre-17 the preview reports an orientation enum; portrait is a 90° rotation of
                // the sensor's native landscape frame.
                switch self.previewLayer.connection?.videoOrientation {
                case .landscapeRight: angle = 0
                case .portraitUpsideDown: angle = 270
                case .landscapeLeft: angle = 180
                default: angle = 90
                }
            }
            self.detectionQueue.async { self.captureRotationAngle = angle }
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
        confirmationTracker.reset()
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
        confirmationTracker.reset()
        // The scene has not changed while detection was paused, so AVFoundation has no reason to
        // re-run autofocus by itself; without this nudge the first code after a resume is scanned
        // against a lens still focused on whatever was in frame when the pause began.
        nudgeFocus()
        emitState("running")
    }

    /// Configures continuous autofocus and exposure on the scan window's centre.
    ///
    /// The layout is read on the main queue and the device is configured back on the session
    /// queue, so this is safe to call from either.
    private func configureFocus(for device: AVCaptureDevice) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isDisposed else { return }
            let devicePoint = self.previewLayer.captureDevicePointConverted(
                fromLayerPoint: ScannerFocus.aimPoint(
                    scanWindow: self.currentScanWindow,
                    viewBounds: self.bounds
                )
            )
            self.sessionQueue.async {
                ScannerFocus.configureForScanning(device, aimingAt: devicePoint)
            }
        }
    }

    /// Re-triggers focus and exposure on the scan window's centre.
    private func nudgeFocus() {
        guard let device = currentInput?.device else { return }
        let layerPoint = ScannerFocus.aimPoint(scanWindow: currentScanWindow, viewBounds: bounds)
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
        sessionQueue.async {
            ScannerFocus.nudge(device, aimingAt: devicePoint)
        }
    }

    /// Re-runs autofocus when the subject changes but the scene does not — one barcode swapped
    /// for another at the same distance, which is the dense-sheet case.
    @objc private func subjectAreaDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isDisposed, self.isRunning else { return }
            self.nudgeFocus()
        }
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
                self.configureFocus(for: input.device)
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
        confirmationTracker =
            ScanConfirmationTracker(requiredObservations: config.scanConfirmationFrames)
        if let autoPauseOnScan {
            self.autoPauseOnScan = autoPauseOnScan
        }
        if !hasEverStartedSession {
            currentCameraPosition = config.initialCameraPosition
            isTorchEnabled = config.initialTorchEnabled
        }
        updateScanWindow()
        sessionQueue.async {
            self.detector.updateFormats(self.config.allowedFormatNames)
            self.alignCaptureRotation()
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
        let videoOutput = videoOutput
        let channel = channel
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
            videoOutput.setSampleBufferDelegate(nil, queue: nil)
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
                    self.configureFocus(for: device)
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

            if !self.session.outputs.contains(self.videoOutput) {
                guard self.session.canAddOutput(self.videoOutput) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.shouldStartSession = false
                        self.emitError("CAMERA_UNAVAILABLE", "Barcode video output is unavailable.")
                        self.emitState("error")
                    }
                    return
                }
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.session.addOutput(self.videoOutput)
                self.videoOutput.setSampleBufferDelegate(self, queue: self.detectionQueue)
            }

            self.session.commitConfiguration()
            self.alignCaptureRotation()
            self.detector.updateFormats(self.config.allowedFormatNames)

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
        // Posted only while `isSubjectAreaChangeMonitoringEnabled` is set, which
        // `ScannerFocus.configureForScanning` does once the input is attached.
        center.addObserver(
            self,
            selector: #selector(subjectAreaDidChange(_:)),
            name: AVCaptureDevice.subjectAreaDidChangeNotification,
            object: nil
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
        currentScanWindow = config.scanWindowRect(in: bounds)
    }

    /// Applies exactly the requested formats the session reports as available.
    ///
    /// - Returns: the applied types. Empty means nothing will be detected — the caller must
    ///   surface that rather than fall back to every available type.

    /// Rotation the capture connection is delivering, kept in step with the preview.
    private var captureRotationAngle: CGFloat = 90

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isDisposed, isRunning, !isDetectionPaused,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        detector.detect(
            pixelBuffer: pixelBuffer,
            videoRotationAngle: captureRotationAngle,
            now: ProcessInfo.processInfo.systemUptime
        ) { [weak self] detections in
            guard !detections.isEmpty else { return }
            DispatchQueue.main.async {
                self?.handle(detections: detections)
            }
        }
    }

    /// Selects and reports one barcode from a frame's detections.
    private func handle(detections: [VisionBarcodeDetector.Detection]) {
        guard !isDisposed, isRunning, !isDetectionPaused else { return }

        let candidates: [ScanCandidate] = detections.map {
            ScanCandidate(
                bounds: previewLayer.layerRectConverted(fromMetadataOutputRect: $0.metadataRect),
                value: $0.value,
                format: $0.format
            )
        }
        let window = activeScanWindow
        let index = ScanCandidateSelector.selectNearest(
            candidates: candidates.map { $0.bounds },
            window: window,
            frameCenter: CGPoint(x: bounds.midX, y: bounds.midY),
            requireCenterOnCandidate: config.requiresCenterOnBarcode,
            aimRadius: ScanCandidateSelector.aimRadius(
                shorterSide: min(
                    window?.width ?? .greatestFiniteMagnitude,
                    window?.height ?? .greatestFiniteMagnitude
                )
            )
        )
        guard let index else { return }

        let selected = candidates[index]
        let codesInWindow = candidates.filter { candidate in
            window.map { $0.intersects(candidate.bounds) } ?? true
        }.count
        let fired = confirmationTracker.observe(
            selected.value,
            now: ProcessInfo.processInfo.systemUptime,
            // Crosshair aiming already makes a neighbour unreportable, so the longer run would
            // only add latency.
            ambiguous: !config.requiresCenterOnBarcode && codesInWindow > 1
        )
        guard fired else { return }

        if autoPauseOnScan {
            isDetectionPaused = true
        }
        emitResult(value: selected.value, format: selected.format)
        if autoPauseOnScan {
            emitState("detectionPaused")
        }
    }

    /// The scan window to select against, or nil when it is disabled or has no area.
    private var activeScanWindow: CGRect? {
        guard config.scanWindowEnabled, !currentScanWindow.isEmpty else { return nil }
        return currentScanWindow
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

}
