import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../flutter_barcode_scanner.dart';
import '../flutter_barcode_scanner_controller.dart';
import '../models/flutter_barcode_scanner_models.dart';

/// Builds custom overlay content above the embedded native scanner preview.
///
/// [scanWindow] is the Flutter-side scan-window rectangle in widget
/// coordinates, or `null` when scan-window rendering is disabled.
typedef FlutterBarcodeScannerOverlayBuilder =
    Widget Function(
      BuildContext context,
      Rect? scanWindow,
      FlutterBarcodeScannerController controller,
    );

/// Builds custom loading content for an embedded scanner state.
typedef FlutterBarcodeScannerStateBuilder =
    Widget Function(
      BuildContext context,
      FlutterBarcodeScannerViewState state,
      FlutterBarcodeScannerController controller,
    );

/// Builds custom content for a camera-permission state that blocks scanning.
///
/// [retry] re-requests permission, and is a no-op when the platform will no
/// longer prompt — check [FlutterBarcodePermissionStatus.canRequest] before
/// offering it. Use [FlutterBarcodeScanner.openAppSettings] for the states
/// where only Settings can help.
typedef FlutterBarcodeScannerPermissionBuilder =
    Widget Function(
      BuildContext context,
      FlutterBarcodePermissionStatus status,
      VoidCallback retry,
    );

/// Builds custom error content for native embedded scanner errors.
typedef FlutterBarcodeScannerErrorBuilder =
    Widget Function(
      BuildContext context,
      PlatformException error,
      FlutterBarcodeScannerController controller,
    );

/// Embeds the native barcode scanner inside a Flutter widget tree.
///
/// The widget creates an Android `AndroidView` or iOS `UiKitView`, forwards
/// native scan results through [onScan], and exposes camera controls through
/// [controller].
class FlutterBarcodeScannerView extends StatefulWidget {
  /// Creates an embedded native scanner view.
  const FlutterBarcodeScannerView({
    required this.config,
    this.widgetConfig = const FlutterBarcodeScannerWidgetConfig(),
    this.controller,
    this.onScan,
    this.onScanValidate,
    this.autoStart = true,
    this.autoPauseOnScan = true,
    this.overlayBuilder,
    this.loadingBuilder,
    this.errorBuilder,
    this.permissionBuilder,
    super.key,
  });

  /// Shared scanner configuration passed to native code.
  final FlutterBarcodeScannerConfig config;

  /// Flutter-side options for embedded scanner behavior and default overlays.
  final FlutterBarcodeScannerWidgetConfig widgetConfig;

  /// Optional controller used to drive the embedded native scanner.
  ///
  /// When omitted, the widget creates and owns an internal controller.
  final FlutterBarcodeScannerController? controller;

  /// Called whenever the native embedded scanner emits a scan result.
  ///
  /// Fires for every result, including cancellations and errors, and before
  /// [onScanValidate].
  final ValueChanged<FlutterBarcodeScanResult>? onScan;

  /// Validates each barcode and drives the accept/reject loop.
  ///
  /// Supplying this turns the scanner into a scan → validate → accept/reject
  /// loop and takes over pause and resume: detection is held while the returned
  /// future is awaited, accepted or rejected feedback is shown for
  /// [FlutterBarcodeScannerWidgetConfig.validationFeedbackDuration], and
  /// detection then resumes automatically. Do not call
  /// [FlutterBarcodeScannerController.resumeDetection] yourself while using it.
  ///
  /// Detection is held for the whole decision regardless of [autoPauseOnScan],
  /// so a slow backend cannot produce a second scan of the same code. Results
  /// arriving while a decision is pending, or while its feedback is showing,
  /// are passed to [onScan] but not validated again.
  ///
  /// If the future throws, the error is reported through `FlutterError` and the
  /// scan is treated as rejected, so a failing backend leaves the scanner
  /// usable rather than wedged. A decision that completes after the widget is
  /// disposed, or after the scanner moved on, is discarded.
  ///
  /// ```dart
  /// onScanValidate: (result) async {
  ///   final check = await api.validate(result.rawValue);
  ///   return check.isValid
  ///       ? const ScanDecision.accept(message: 'Admitted')
  ///       : const ScanDecision.reject(message: 'Already used');
  /// }
  /// ```
  final Future<ScanDecision> Function(FlutterBarcodeScanResult)? onScanValidate;

  /// Whether the native camera should start automatically after the platform
  /// view is created.
  final bool autoStart;

  /// Whether native detection pauses automatically after a barcode result.
  final bool autoPauseOnScan;

  /// Optional builder for replacing the default scanner overlay controls.
  final FlutterBarcodeScannerOverlayBuilder? overlayBuilder;

  /// Optional builder for replacing the default loading overlay.
  final FlutterBarcodeScannerStateBuilder? loadingBuilder;

  /// Optional builder for replacing the default error overlay.
  final FlutterBarcodeScannerErrorBuilder? errorBuilder;

  /// Optional builder for replacing the default permission-denied UI.
  final FlutterBarcodeScannerPermissionBuilder? permissionBuilder;

  @override
  State<FlutterBarcodeScannerView> createState() =>
      _FlutterBarcodeScannerViewState();
}

/// Where the validate loop currently is.
///
/// Only [idle] accepts a new result for validation; the other two exist so a
/// second decode during a decision or its feedback cannot start a second cycle.
enum _ValidationPhase { idle, validating, showingFeedback }

class _FlutterBarcodeScannerViewState extends State<FlutterBarcodeScannerView>
    with WidgetsBindingObserver {
  late FlutterBarcodeScannerController _controller;
  late bool _ownsController;
  StreamSubscription<FlutterBarcodeScanResult>? _resultSubscription;
  StreamSubscription<PlatformException>? _errorSubscription;
  FlutterBarcodeScannerViewState _state = FlutterBarcodeScannerViewState.idle;
  PlatformException? _lastError;
  FlutterBarcodePermissionStatus? _permissionStatus;
  bool _isRequestingPermission = false;
  bool _restartCameraOnResume = false;
  bool _restorePausedDetectionOnResume = false;
  bool _torchEnabled = false;
  int _platformViewGeneration = 0;
  _ValidationPhase _validationPhase = _ValidationPhase.idle;
  // Bumped whenever a validation cycle starts, is abandoned, or the widget goes
  // away. A decision that resolves against a stale generation is discarded,
  // which is what makes a slow backend safe.
  int _validationGeneration = 0;
  Timer? _feedbackTimer;
  String? _cooldownValue;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _torchEnabled = widget.config.uiConfig.initialTorchEnabled;
    _setController(
      widget.controller,
      ownsController: widget.controller == null,
    );
    unawaited(_ensureCameraPermission());
  }

  @override
  void didUpdateWidget(covariant FlutterBarcodeScannerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _releaseController();
      _platformViewGeneration += 1;
      _setController(
        widget.controller,
        ownsController: widget.controller == null,
      );
    }
    // Config models carry value equality, so this is a direct comparison
    // rather than serializing both configs to nested maps on every rebuild.
    final configChanged = oldWidget.config != widget.config;
    final widgetConfigChanged = oldWidget.widgetConfig != widget.widgetConfig;
    if ((configChanged ||
            widgetConfigChanged ||
            oldWidget.autoPauseOnScan != widget.autoPauseOnScan) &&
        _controller.isAttached) {
      unawaited(
        _runControllerAction(
          () => _controller.updateConfig(
            widget.config,
            autoPauseOnScan: widget.autoPauseOnScan,
            widgetConfig: widget.widgetConfig,
          ),
        ),
      );
    }
    if (oldWidget.widgetConfig.autoRequestCameraPermission !=
        widget.widgetConfig.autoRequestCameraPermission) {
      unawaited(_ensureCameraPermission());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-read rather than re-request: the user may have just granted access
      // in Settings, and prompting again there would be wrong.
      unawaited(_refreshPermissionOnResume());
      unawaited(_ensureCameraPermission());
    }
    if (!_controller.isAttached) {
      return;
    }
    // Deliberately not `inactive`: on iOS that fires for a notification
    // banner, Control Center and the app switcher, and each one used to cost a
    // full camera stop and rebind — hundreds of milliseconds of dead time,
    // repeatedly, during a shift.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      final shouldRestart =
          _state == FlutterBarcodeScannerViewState.running ||
          _state == FlutterBarcodeScannerViewState.detectionPaused;
      if (shouldRestart && !_restartCameraOnResume) {
        _restartCameraOnResume = true;
        _restorePausedDetectionOnResume =
            _state == FlutterBarcodeScannerViewState.detectionPaused;
        unawaited(_runControllerAction(_controller.stopCamera));
      }
      return;
    }
    if (state == AppLifecycleState.resumed && _restartCameraOnResume) {
      _restartCameraOnResume = false;
      final restorePausedDetection = _restorePausedDetectionOnResume;
      _restorePausedDetectionOnResume = false;
      unawaited(
        _runControllerAction(() async {
          await _controller.startCamera();
          if (restorePausedDetection) {
            await _controller.pauseDetection();
          }
        }),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _abandonValidation();
    _releaseController();
    super.dispose();
  }

  /// Drops any pending decision and clears feedback.
  ///
  /// Incrementing the generation is what makes an already-running validator
  /// harmless: its result no longer matches and is discarded on arrival.
  void _abandonValidation() {
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    _cooldownValue = null;
    _validationGeneration += 1;
    _validationPhase = _ValidationPhase.idle;
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
  }

  /// Whether this result repeats the value that is currently in cooldown.
  ///
  /// Compares the decoded value, not merely elapsed time: a burst of the same
  /// code is noise, but the next *different* code is the user moving on and
  /// must never be swallowed.
  bool _isDuplicate(FlutterBarcodeScanResult result) =>
      result.isBarcode && result.rawValue == _cooldownValue;

  /// Suppresses [value] until the cooldown elapses.
  ///
  /// A timer rather than a stored timestamp: timers are driven by the same
  /// clock as the rest of the widget, which keeps the expiry observable in
  /// tests instead of depending on wall time.
  void _startCooldown(String value) {
    final cooldown = widget.widgetConfig.duplicateScanCooldown;
    if (cooldown <= Duration.zero) {
      return;
    }
    _cooldownTimer?.cancel();
    _cooldownValue = value;
    _cooldownTimer = Timer(cooldown, () {
      _cooldownValue = null;
      _cooldownTimer = null;
    });
  }

  Future<void> _handleResult(FlutterBarcodeScanResult result) async {
    if (_isDuplicate(result)) {
      return;
    }
    if (result.isBarcode) {
      _startCooldown(result.rawValue);
    }

    widget.onScan?.call(result);

    final validate = widget.onScanValidate;
    if (validate == null || !result.isBarcode) {
      return;
    }
    // A result arriving mid-cycle is reported but never validated twice.
    if (_validationPhase != _ValidationPhase.idle) {
      return;
    }

    final generation = ++_validationGeneration;
    if (mounted) {
      setState(() => _validationPhase = _ValidationPhase.validating);
    } else {
      _validationPhase = _ValidationPhase.validating;
    }

    // Hold detection even when the caller opted out of native auto-pause, so
    // the decision cannot race a second read of the same code.
    if (!widget.autoPauseOnScan) {
      await _invokeControllerSafely(_controller.pauseDetection);
    }

    ScanDecision decision;
    try {
      decision = await validate(result);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'flutter_barcode_scanner_sdk',
          context: ErrorDescription('while validating a scan result'),
        ),
      );
      decision = const ScanDecision.reject();
    }

    if (!mounted || generation != _validationGeneration) {
      return;
    }

    if (decision.isAccepted) {
      // Deliberately not awaited: the banner must appear immediately, not after
      // a platform round trip for a haptic.
      unawaited(_playAcceptFeedback());
    }

    _controller.publishFeedback(
      FlutterBarcodeScanFeedback(decision: decision, result: result),
    );
    setState(() => _validationPhase = _ValidationPhase.showingFeedback);

    final holdFor = widget.widgetConfig.validationFeedbackDuration;
    if (holdFor <= Duration.zero) {
      await _finishValidation(generation);
      return;
    }
    _feedbackTimer = Timer(
      holdFor,
      () => unawaited(_finishValidation(generation)),
    );
  }

  Future<void> _finishValidation(int generation) async {
    if (!mounted || generation != _validationGeneration) {
      return;
    }
    _feedbackTimer = null;
    _controller.publishFeedback(null);
    setState(() => _validationPhase = _ValidationPhase.idle);
    await _invokeControllerSafely(_controller.resumeDetection);
  }

  /// Haptic and audible confirmation for an accepted scan.
  ///
  /// Reduce Motion suppresses the haptic. The sound is the platform system
  /// sound rather than a bundled asset, so the iOS silent switch mutes it
  /// without the package needing to read a switch Flutter does not expose.
  Future<void> _playAcceptFeedback() async {
    final config = widget.widgetConfig;
    if (config.hapticFeedbackOnAccept && mounted) {
      final reduceMotion =
          MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (!reduceMotion) {
        await HapticFeedback.selectionClick();
      }
    }
    if (config.soundOnAccept) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  /// Runs a controller call that is meaningless once the view is detached.
  ///
  /// The controller throws [StateError] when it has no platform view, which is
  /// an ordinary outcome if the scanner was torn down mid-decision.
  Future<void> _invokeControllerSafely(Future<void> Function() action) async {
    try {
      await action();
    } on StateError {
      // Detached or disposed while the decision was in flight — expected.
    } catch (error, stackTrace) {
      _handleControllerError(error, stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scanWindow = _scanWindowForSize(
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            _buildPlatformView(context),
            if (_canRenderScannerUi && widget.config.scanWindow.enabled)
              IgnorePointer(
                child: CustomPaint(
                  painter: _ScannerOverlayPainter(
                    scanWindow: scanWindow,
                    overlayColor: widget.config.overlayColor,
                    cornerRadius:
                        widget.config.scanWindow.effectiveCornerRadius,
                    borderColor: _scanWindowBorderColor,
                  ),
                ),
              ),
            if (_canRenderScannerUi && widget.overlayBuilder != null)
              Positioned.fill(
                child: widget.overlayBuilder!(context, scanWindow, _controller),
              )
            else if (_canRenderScannerUi)
              _buildDefaultControls(context),
            if (_feedback != null && widget.overlayBuilder == null)
              Positioned.fill(
                child: _buildValidationFeedback(context, _feedback!),
              ),
            if (_isLoadingState)
              Positioned.fill(child: _buildLoading(context))
            else if (_lastError != null)
              Positioned.fill(child: _buildError(context, _lastError!)),
          ],
        );
      },
    );
  }

  Widget _buildPlatformView(BuildContext context) {
    if (widget.widgetConfig.autoRequestCameraPermission &&
        _supportsCameraPlatform) {
      if (_isRequestingPermission || _permissionStatus == null) {
        return const ColoredBox(
          color: Colors.black,
          child: Center(child: CircularProgressIndicator.adaptive()),
        );
      }
      final status = _permissionStatus;
      if (status != null && !status.isGranted) {
        return widget.permissionBuilder?.call(
              context,
              status,
              _retryPermission,
            ) ??
            _buildPermissionDenied(context, status);
      }
    }

    final creationParams = <String, Object?>{
      'config': widget.config.toPlatformMap(),
      'widgetConfig': widget.widgetConfig.toMap(),
      'autoStart': widget.autoStart,
      'autoPauseOnScan': widget.autoPauseOnScan,
    };

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidView(
          key: ValueKey<int>(_platformViewGeneration),
          viewType: 'flutter_barcode_scanner_sdk/scanner_view',
          onPlatformViewCreated: _onPlatformViewCreated,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        );
      case TargetPlatform.iOS:
        return UiKitView(
          key: ValueKey<int>(_platformViewGeneration),
          viewType: 'flutter_barcode_scanner_sdk/scanner_view',
          onPlatformViewCreated: _onPlatformViewCreated,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        );
      default:
        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: Text(
              'Barcode scanning is only available on Android and iOS.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        );
    }
  }

  Widget _buildDefaultControls(BuildContext context) {
    final direction = widget.config.textDirection ?? Directionality.of(context);
    final showFlash = widget.config.uiConfig.showFlashButton;
    final showSwitch = widget.config.uiConfig.showCameraSwitchButton;
    final showPause = widget.widgetConfig.showPauseResumeButton;
    return Directionality(
      textDirection: direction,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showFlash)
              _OverlayIconButton(
                tooltip: _torchEnabled
                    ? widget.config.strings.flashOff
                    : widget.config.strings.flashOn,
                icon: _torchEnabled ? Icons.flash_off : Icons.flash_on,
                onPressed: () async {
                  try {
                    final enabled = await _controller.toggleFlash();
                    if (mounted && enabled != null) {
                      setState(() {
                        _torchEnabled = enabled;
                      });
                    }
                  } catch (error, stackTrace) {
                    _handleControllerError(error, stackTrace);
                  }
                },
              ),
            if (showPause) ...[
              if (showFlash) const SizedBox(width: 10),
              _OverlayIconButton(
                tooltip: _isDetectionPaused
                    ? widget.widgetConfig.resumeTooltip
                    : widget.widgetConfig.pauseTooltip,
                icon: _isDetectionPaused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                onPressed: () {
                  if (_isDetectionPaused) {
                    unawaited(
                      _runControllerAction(_controller.resumeDetection),
                    );
                  } else {
                    unawaited(_runControllerAction(_controller.pauseDetection));
                  }
                },
              ),
            ],
            const Spacer(),
            if (showSwitch)
              _OverlayIconButton(
                tooltip: widget.config.strings.switchCamera,
                icon: Platform.isIOS
                    ? Icons.cameraswitch_outlined
                    : Icons.flip_camera_android_outlined,
                onPressed: () {
                  unawaited(_switchCamera());
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    if (widget.loadingBuilder != null) {
      return widget.loadingBuilder!(context, _state, _controller);
    }
    return const ColoredBox(
      color: Color(0x33000000),
      child: Center(child: CircularProgressIndicator.adaptive()),
    );
  }

  Widget _buildError(BuildContext context, PlatformException error) {
    if (widget.errorBuilder != null) {
      return widget.errorBuilder!(context, error, _controller);
    }
    return ColoredBox(
      color: const Color(0x66000000),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            error.message ?? widget.config.strings.cameraUnavailable,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  bool get _isLoadingState =>
      _state == FlutterBarcodeScannerViewState.initializing;

  /// The feedback to render, or `null` when no decision is being shown.
  FlutterBarcodeScanFeedback? get _feedback =>
      _validationPhase == _ValidationPhase.showingFeedback
      ? _controller.currentFeedback
      : null;

  /// Accepted and rejected are signalled on the scan-window border as well as
  /// the banner, so the outcome is legible without reading text.
  Color get _scanWindowBorderColor {
    final feedback = _feedback;
    if (feedback != null) {
      return feedback.decision.isAccepted ? _acceptedColor : _rejectedColor;
    }
    return _isDetectionPaused
        ? widget.widgetConfig.pausedScanWindowBorderColor
        : widget.widgetConfig.scanWindowBorderColor;
  }

  /// Default accepted/rejected treatment.
  ///
  /// Deliberately not exposed as configuration: overlay styling has a single
  /// extension point, [FlutterBarcodeScannerView.overlayBuilder], which
  /// replaces this entirely and can read
  /// [FlutterBarcodeScannerController.feedbackListenable].
  Widget _buildValidationFeedback(
    BuildContext context,
    FlutterBarcodeScanFeedback feedback,
  ) {
    final accepted = feedback.decision.isAccepted;
    final color = accepted ? _acceptedColor : _rejectedColor;
    final message = feedback.decision.message;
    return IgnorePointer(
      child: ColoredBox(
        color: color.withValues(alpha: 0.22),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    accepted ? Icons.check_circle : Icons.cancel,
                    color: Colors.white,
                    size: 28,
                  ),
                  if (message != null && message.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _isDetectionPaused =>
      _state == FlutterBarcodeScannerViewState.detectionPaused;

  bool get _canRenderScannerUi =>
      !widget.widgetConfig.autoRequestCameraPermission ||
      !_supportsCameraPlatform ||
      _permissionStatus?.isGranted == true;

  Rect? _scanWindowForSize(Size size) => widget.config.scanWindow.resolve(size);

  void _onPlatformViewCreated(int id) {
    _controller.attach(id);
  }

  void _setController(
    FlutterBarcodeScannerController? controller, {
    required bool ownsController,
  }) {
    _controller = controller ?? FlutterBarcodeScannerController();
    _ownsController = ownsController;
    // Read the controller's present state rather than waiting for the next
    // change: attaching to a controller that is already running used to leave
    // the view showing `idle` until something happened to it.
    _state = _controller.currentState;
    _controller.stateListenable.addListener(_handleControllerStateChanged);
    _resultSubscription = _controller.results.listen(_handleResult);
    _errorSubscription = _controller.errors.listen((error) {
      if (mounted) {
        setState(() {
          _state = FlutterBarcodeScannerViewState.error;
          _lastError = error;
        });
      }
    });
  }

  void _handleControllerStateChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _state = _controller.currentState;
      if (_state != FlutterBarcodeScannerViewState.error) {
        _lastError = null;
      }
    });
  }

  void _releaseController() {
    _controller.stateListenable.removeListener(_handleControllerStateChanged);
    unawaited(_resultSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    _resultSubscription = null;
    _errorSubscription = null;
    if (_ownsController) {
      unawaited(_controller.dispose());
    } else {
      final viewId = _controller.viewId;
      if (viewId != null) {
        _controller.detach(viewId);
      }
    }
  }

  Future<void> _runControllerAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      _handleControllerError(error, stackTrace);
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _controller.switchCamera();
      if (mounted) {
        setState(() {
          _torchEnabled = false;
        });
      }
    } catch (error, stackTrace) {
      _handleControllerError(error, stackTrace);
    }
  }

  void _handleControllerError(Object error, StackTrace stackTrace) {
    if (!mounted) {
      return;
    }
    final platformError = error is PlatformException
        ? error
        : PlatformException(
            code: 'CONTROLLER_UNAVAILABLE',
            message: error.toString(),
            details: stackTrace.toString(),
          );
    setState(() {
      _state = FlutterBarcodeScannerViewState.error;
      _lastError = platformError;
    });
  }

  Future<void> _ensureCameraPermission() async {
    if (!widget.widgetConfig.autoRequestCameraPermission ||
        !_supportsCameraPlatform ||
        _isRequestingPermission ||
        _permissionStatus?.isGranted == true) {
      return;
    }
    setState(() {
      _isRequestingPermission = true;
    });
    var status = FlutterBarcodePermissionStatus.denied;
    try {
      final current = await FlutterBarcodeScanner.checkCameraPermission();
      // Only prompt when the system would actually show one; asking again
      // after a permanent denial returns immediately and looks like a hang.
      status = current.canRequest
          ? await FlutterBarcodeScanner.requestCameraPermission()
          : current;
    } catch (_) {
      status = FlutterBarcodePermissionStatus.denied;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _permissionStatus = status;
      _isRequestingPermission = false;
      if (status.isGranted) {
        _lastError = null;
      }
    });
  }

  void _retryPermission() {
    unawaited(_ensureCameraPermission());
  }

  /// Re-reads permission without prompting.
  ///
  /// Called when the app returns to the foreground, which is how the scanner
  /// recovers after the user grants access in Settings — the previous version
  /// left the denied screen up until the widget was rebuilt.
  Future<void> _refreshPermissionOnResume() async {
    if (!widget.widgetConfig.autoRequestCameraPermission ||
        !_supportsCameraPlatform ||
        _permissionStatus?.isGranted == true) {
      return;
    }
    FlutterBarcodePermissionStatus status;
    try {
      status = await FlutterBarcodeScanner.checkCameraPermission();
    } catch (_) {
      return;
    }
    if (!mounted || status == _permissionStatus) {
      return;
    }
    setState(() {
      _permissionStatus = status;
      if (status.isGranted) {
        _lastError = null;
      }
    });
  }

  /// Default UI for a permission state that blocks scanning.
  ///
  /// Offers only the action that can actually help: a retry when the system
  /// will still prompt, Settings when it will not, and neither when a device
  /// policy forbids the camera outright.
  Widget _buildPermissionDenied(
    BuildContext context,
    FlutterBarcodePermissionStatus status,
  ) {
    final strings = widget.config.strings;
    final message = switch (status) {
      FlutterBarcodePermissionStatus.permanentlyDenied =>
        strings.cameraPermissionPermanentlyDenied,
      FlutterBarcodePermissionStatus.restricted =>
        strings.cameraPermissionRestricted,
      _ => strings.cameraPermissionRequired,
    };
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              if (status.canRequest) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _retryPermission,
                  child: Text(strings.permissionRetry),
                ),
              ],
              if (status ==
                  FlutterBarcodePermissionStatus.permanentlyDenied) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      unawaited(FlutterBarcodeScanner.openAppSettings()),
                  child: Text(strings.permissionOpenSettings),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool get _supportsCameraPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  const _ScannerOverlayPainter({
    required this.scanWindow,
    required this.overlayColor,
    required this.cornerRadius,
    required this.borderColor,
  });

  final Rect? scanWindow;
  final Color overlayColor;
  final double cornerRadius;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final window = scanWindow;
    if (window == null || window.isEmpty) {
      return;
    }
    final overlayPath = Path()..addRect(Offset.zero & size);
    final cutoutPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(window, Radius.circular(cornerRadius)),
      );
    canvas.drawPath(
      Path.combine(PathOperation.difference, overlayPath, cutoutPath),
      Paint()..color = overlayColor,
    );

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(window, Radius.circular(cornerRadius)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.scanWindow != scanWindow ||
        oldDelegate.overlayColor != overlayColor ||
        oldDelegate.cornerRadius != cornerRadius ||
        oldDelegate.borderColor != borderColor;
  }
}

/// Default accepted feedback colour.
const Color _acceptedColor = Color(0xFF2E7D32);

/// Default rejected feedback colour.
const Color _rejectedColor = Color(0xFFC62828);
