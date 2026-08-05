import 'package:flutter/services.dart';

import 'models/flutter_barcode_scanner_models.dart';

/// Static entry points for full-screen scanner actions.
class FlutterBarcodeScanner {
  static const MethodChannel _methodChannel = MethodChannel(
    'flutter_barcode_scanner_sdk/methods',
  );

  /// Reports camera permission without prompting the user.
  ///
  /// Safe to call at any time — it never shows a system dialog, so use it to
  /// decide what to render before asking.
  static Future<FlutterBarcodePermissionStatus> checkCameraPermission() async {
    final status = await _methodChannel.invokeMethod<String>(
      'checkCameraPermission',
    );
    return FlutterBarcodePermissionStatus.fromNativeValue(status);
  }

  /// Requests camera permission, showing the system prompt when possible.
  ///
  /// Returns the resulting status. Calling this when the status is already
  /// [FlutterBarcodePermissionStatus.permanentlyDenied] or
  /// [FlutterBarcodePermissionStatus.restricted] shows no prompt and returns
  /// that same status — check
  /// [FlutterBarcodePermissionStatus.canRequest] first if you need to know
  /// whether asking will do anything.
  ///
  /// Returns [FlutterBarcodePermissionStatus.denied] when the plugin is not
  /// attached to a native activity or view controller.
  static Future<FlutterBarcodePermissionStatus>
  requestCameraPermission() async {
    final status = await _methodChannel.invokeMethod<String>(
      'requestCameraPermission',
    );
    return FlutterBarcodePermissionStatus.fromNativeValue(status);
  }

  /// Opens this app's page in the system settings.
  ///
  /// The only route back from
  /// [FlutterBarcodePermissionStatus.permanentlyDenied]. Returns whether the
  /// settings screen was opened; it does not report what the user did there,
  /// so re-check with [checkCameraPermission] when the app resumes.
  static Future<bool> openAppSettings() async {
    final opened = await _methodChannel.invokeMethod<bool>('openAppSettings');
    return opened ?? false;
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
