import 'package:flutter/services.dart';

import 'models/flutter_barcode_scanner_models.dart';

/// Static entry points for full-screen scanner actions.
class FlutterBarcodeScanner {
  static const MethodChannel _methodChannel = MethodChannel(
    'flutter_barcode_scanner_sdk/methods',
  );

  /// Requests camera permission on the current platform.
  ///
  /// Returns `true` when camera access is already granted or was granted by the
  /// user. Returns `false` when permission is denied, unavailable, or the
  /// plugin is not attached to a native activity/view controller.
  static Future<bool> requestCameraPermission() async {
    final granted = await _methodChannel.invokeMethod<bool>(
      'requestCameraPermission',
    );
    return granted ?? false;
  }

  /// Opens the native full-screen scanner and waits for a single result.
  ///
  /// The scanner requests camera permission if needed. A successful scan
  /// returns a [FlutterBarcodeScanResult] with `type == barcode`; user
  /// cancellation returns a result with `type == cancelled`.
  static Future<FlutterBarcodeScanResult?> scan(
    FlutterBarcodeScannerConfig config,
  ) async {
    final result = await _methodChannel.invokeMethod<Map<Object?, Object?>>(
      'scan',
      config.toPlatformMap(),
    );
    if (result == null) {
      return null;
    }
    return FlutterBarcodeScanResult.fromMap(result);
  }
}
