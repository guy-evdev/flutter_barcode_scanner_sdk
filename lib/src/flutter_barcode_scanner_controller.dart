import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models/flutter_barcode_scanner_models.dart';

/// Controller for an embedded [FlutterBarcodeScannerView].
///
/// Create one controller when the surrounding app needs to start/stop the
/// camera, pause/resume detection, switch cameras, toggle the torch, or listen
/// to scan results and native state changes.
class FlutterBarcodeScannerController {
  /// Creates a detached scanner controller.
  FlutterBarcodeScannerController();

  MethodChannel? _channel;
  int? _viewId;
  bool _disposed = false;

  final StreamController<FlutterBarcodeScanResult> _resultsController =
      StreamController<FlutterBarcodeScanResult>.broadcast();
  final StreamController<FlutterBarcodeScannerViewState> _stateController =
      StreamController<FlutterBarcodeScannerViewState>.broadcast();
  final StreamController<PlatformException> _errorController =
      StreamController<PlatformException>.broadcast();

  final ValueNotifier<FlutterBarcodeScannerViewState> _stateNotifier =
      ValueNotifier<FlutterBarcodeScannerViewState>(
        FlutterBarcodeScannerViewState.idle,
      );

  /// Stream of decoded scan results emitted by the native embedded scanner.
  Stream<FlutterBarcodeScanResult> get results => _resultsController.stream;

  /// Stream of native scanner lifecycle states.
  ///
  /// A broadcast stream delivers only states emitted *after* a listener
  /// subscribes, so a widget built partway through the scanner's lifecycle sees
  /// nothing until the next change. Prefer [stateListenable] or [currentState],
  /// which are readable immediately; this stream is retained for callers
  /// already built around it.
  Stream<FlutterBarcodeScannerViewState> get state => _stateController.stream;

  /// The scanner's current state, readable synchronously at any time.
  ///
  /// Starts at [FlutterBarcodeScannerViewState.idle] and tracks every state the
  /// native scanner reports, whether or not anything is listening. Retains its
  /// last value after [dispose].
  FlutterBarcodeScannerViewState get currentState => _stateNotifier.value;

  /// The scanner's current state as a listenable value.
  ///
  /// Drive a `ValueListenableBuilder` with this to rebuild on state changes
  /// without managing a stream subscription:
  ///
  /// ```dart
  /// ValueListenableBuilder<FlutterBarcodeScannerViewState>(
  ///   valueListenable: controller.stateListenable,
  ///   builder: (context, state, _) => Text(state.name),
  /// )
  /// ```
  ///
  /// Notifies only when the state actually changes; a repeated state is not
  /// re-delivered. The [state] stream, by contrast, delivers every emission.
  ValueListenable<FlutterBarcodeScannerViewState> get stateListenable =>
      _stateNotifier;

  final ValueNotifier<FlutterBarcodeScanFeedback?> _feedbackNotifier =
      ValueNotifier<FlutterBarcodeScanFeedback?>(null);

  /// The accept/reject feedback currently being shown, or `null` when none is.
  ///
  /// Only ever non-null while `FlutterBarcodeScannerView.onScanValidate` is in
  /// use and its feedback is on screen.
  FlutterBarcodeScanFeedback? get currentFeedback => _feedbackNotifier.value;

  /// The accept/reject feedback as a listenable value.
  ///
  /// A custom `overlayBuilder` receives this controller, so read this to render
  /// your own accepted/rejected treatment:
  ///
  /// ```dart
  /// ValueListenableBuilder<FlutterBarcodeScanFeedback?>(
  ///   valueListenable: controller.feedbackListenable,
  ///   builder: (context, feedback, _) => feedback == null
  ///       ? const SizedBox.shrink()
  ///       : Banner(message: feedback.decision.message),
  /// )
  /// ```
  ValueListenable<FlutterBarcodeScanFeedback?> get feedbackListenable =>
      _feedbackNotifier;

  /// Publishes accept/reject feedback to [feedbackListenable].
  ///
  /// Called by [FlutterBarcodeScannerView] as it drives the validate loop.
  /// Applications usually do not call it directly.
  void publishFeedback(FlutterBarcodeScanFeedback? feedback) {
    if (_disposed) {
      return;
    }
    _feedbackNotifier.value = feedback;
  }

  /// Stream of native scanner errors.
  Stream<PlatformException> get errors => _errorController.stream;

  /// Whether this controller is attached to a live platform view.
  bool get isAttached => _channel != null && !_disposed;

  /// Current platform view id, or `null` when detached.
  int? get viewId => _viewId;

  /// Starts the embedded native camera preview and barcode detection.
  Future<void> startCamera() => _invokeVoid('startCamera');

  /// Stops the embedded native camera preview and barcode detection.
  Future<void> stopCamera() => _invokeVoid('stopCamera');

  /// Pauses barcode detection while keeping the platform view attached.
  Future<void> pauseDetection() => _invokeVoid('pauseDetection');

  /// Resumes barcode detection after [pauseDetection].
  Future<void> resumeDetection() => _invokeVoid('resumeDetection');

  /// Toggles or explicitly sets the torch state.
  ///
  /// When [enabled] is omitted, native code toggles the current state. The
  /// returned value is the resulting torch state when available.
  Future<bool?> toggleFlash([bool? enabled]) async {
    final arguments = <String, Object?>{};
    if (enabled != null) {
      arguments['enabled'] = enabled;
    }
    final result = await _invoke<bool>('toggleFlash', arguments);
    return result;
  }

  /// Switches to the requested camera lens or toggles between available lenses.
  Future<void> switchCamera([BarcodeCameraLens? lens]) {
    final arguments = <String, Object?>{};
    if (lens != null) {
      arguments['lens'] = lens.name;
    }
    return _invokeVoid('switchCamera', arguments);
  }

  /// Applies new scanner configuration to the attached native platform view.
  ///
  /// [autoPauseOnScan] and [widgetConfig] override the values originally passed
  /// to [FlutterBarcodeScannerView] when supplied.
  Future<void> updateConfig(
    FlutterBarcodeScannerConfig config, {
    bool? autoPauseOnScan,
    FlutterBarcodeScannerWidgetConfig? widgetConfig,
  }) {
    final arguments = config.toPlatformMap();
    if (autoPauseOnScan != null) {
      arguments['autoPauseOnScan'] = autoPauseOnScan;
    }
    if (widgetConfig != null) {
      arguments['widgetConfig'] = widgetConfig.toMap();
    }
    return _invokeVoid('updateConfig', arguments);
  }

  /// Disposes the controller, closes all streams, and releases
  /// [stateListenable].
  ///
  /// A disposed controller cannot be attached again. [currentState] keeps
  /// returning the last observed state so a widget tearing down alongside the
  /// controller can still read it.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    try {
      await _channel?.invokeMethod<void>('dispose');
    } catch (_) {
      // Native platform views may already be disposed by Flutter.
    }
    _channel?.setMethodCallHandler(null);
    _channel = null;
    _viewId = null;
    _stateNotifier.dispose();
    _feedbackNotifier.dispose();
    await Future.wait([
      _resultsController.close(),
      _stateController.close(),
      _errorController.close(),
    ]);
  }

  /// Attaches the controller to a native platform view id.
  ///
  /// This is called by [FlutterBarcodeScannerView] when its platform view is
  /// created. Applications usually do not call it directly.
  void attach(int viewId) {
    if (_disposed) {
      throw StateError('Cannot attach a disposed scanner controller.');
    }
    if (_viewId == viewId && _channel != null) {
      return;
    }
    _channel?.setMethodCallHandler(null);
    _viewId = viewId;
    _channel = MethodChannel('flutter_barcode_scanner_sdk/scanner_view/$viewId')
      ..setMethodCallHandler(_handleNativeCall);
  }

  /// Detaches the controller from [viewId] if it is the active platform view.
  ///
  /// This is called by [FlutterBarcodeScannerView] when the view is released.
  void detach(int viewId) {
    if (_viewId != viewId) {
      return;
    }
    _channel?.setMethodCallHandler(null);
    _channel = null;
    _viewId = null;
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) {
    final channel = _channel;
    if (_disposed) {
      return Future<T?>.error(StateError('Scanner controller is disposed.'));
    }
    if (channel == null) {
      return Future<T?>.error(
        StateError('Scanner controller is not attached.'),
      );
    }
    return channel.invokeMethod<T>(method, arguments);
  }

  Future<void> _invokeVoid(String method, [Object? arguments]) async {
    await _invoke<void>(method, arguments);
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onResult':
        final payload = call.arguments;
        if (payload is Map) {
          _resultsController.add(FlutterBarcodeScanResult.fromMap(payload));
        }
        return;
      case 'onState':
        final stateName = call.arguments as String?;
        final state = FlutterBarcodeScannerViewState.values.firstWhere(
          (value) => value.name == stateName,
          orElse: () => FlutterBarcodeScannerViewState.error,
        );
        // The notifier is updated first so a listener woken by the stream
        // already reads the new value from currentState.
        _stateNotifier.value = state;
        _stateController.add(state);
        return;
      case 'onError':
        final payload = call.arguments;
        if (payload is Map) {
          _errorController.add(
            PlatformException(
              code: payload['code'] as String? ?? 'SCANNER_ERROR',
              message: payload['message'] as String?,
              details: payload['details'],
            ),
          );
        }
        return;
      default:
        throw MissingPluginException(
          'Unknown scanner callback: ${call.method}',
        );
    }
  }
}
