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
    this.autoStart = true,
    this.autoPauseOnScan = true,
    this.overlayBuilder,
    this.loadingBuilder,
    this.errorBuilder,
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
  final ValueChanged<FlutterBarcodeScanResult>? onScan;

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

  @override
  State<FlutterBarcodeScannerView> createState() =>
      _FlutterBarcodeScannerViewState();
}

class _FlutterBarcodeScannerViewState extends State<FlutterBarcodeScannerView>
    with WidgetsBindingObserver {
  late FlutterBarcodeScannerController _controller;
  late bool _ownsController;
  StreamSubscription<FlutterBarcodeScanResult>? _resultSubscription;
  StreamSubscription<PlatformException>? _errorSubscription;
  FlutterBarcodeScannerViewState _state = FlutterBarcodeScannerViewState.idle;
  PlatformException? _lastError;
  bool? _hasCameraPermission;
  bool _isRequestingPermission = false;
  bool _restartCameraOnResume = false;
  bool _restorePausedDetectionOnResume = false;
  bool _torchEnabled = false;
  int _platformViewGeneration = 0;

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
      unawaited(_ensureCameraPermission());
    }
    if (!_controller.isAttached) {
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
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
    _releaseController();
    super.dispose();
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
                    borderColor: _isDetectionPaused
                        ? widget.widgetConfig.pausedScanWindowBorderColor
                        : widget.widgetConfig.scanWindowBorderColor,
                  ),
                ),
              ),
            if (_canRenderScannerUi && widget.overlayBuilder != null)
              Positioned.fill(
                child: widget.overlayBuilder!(context, scanWindow, _controller),
              )
            else if (_canRenderScannerUi)
              _buildDefaultControls(context),
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
      if (_isRequestingPermission || _hasCameraPermission == null) {
        return const ColoredBox(
          color: Colors.black,
          child: Center(child: CircularProgressIndicator.adaptive()),
        );
      }
      if (_hasCameraPermission == false) {
        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.config.strings.cameraPermissionRequired,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
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

  bool get _isDetectionPaused =>
      _state == FlutterBarcodeScannerViewState.detectionPaused;

  bool get _canRenderScannerUi =>
      !widget.widgetConfig.autoRequestCameraPermission ||
      !_supportsCameraPlatform ||
      _hasCameraPermission == true;

  Rect? _scanWindowForSize(Size size) {
    if (!widget.config.scanWindow.enabled ||
        size.width <= 0 ||
        size.height <= 0) {
      return null;
    }
    final scanWindow = widget.config.scanWindow;
    final requestedWidth = size.width * scanWindow.effectiveWidthFactor;
    final requestedHeight = size.height * scanWindow.effectiveHeightFactor;
    final useSquare =
        (scanWindow.effectiveWidthFactor - scanWindow.effectiveHeightFactor)
            .abs() <
        0.001;
    final width = useSquare
        ? requestedWidth.clamp(0, requestedHeight)
        : requestedWidth;
    final height = useSquare ? width.toDouble() : requestedHeight;
    return Rect.fromLTWH(
      (size.width - width) / 2,
      (size.height - height) / 2,
      width.toDouble(),
      height.toDouble(),
    );
  }

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
    _resultSubscription = _controller.results.listen((result) {
      widget.onScan?.call(result);
    });
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
        _hasCameraPermission == true) {
      return;
    }
    setState(() {
      _isRequestingPermission = true;
    });
    var granted = false;
    try {
      granted = await FlutterBarcodeScanner.requestCameraPermission();
    } catch (_) {
      granted = false;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _hasCameraPermission = granted;
      _isRequestingPermission = false;
      if (granted) {
        _lastError = null;
      }
    });
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
