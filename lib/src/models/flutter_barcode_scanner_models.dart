import 'package:flutter/material.dart';

/// Barcode symbologies that can be detected by the scanner.
enum FlutterBarcodeScannerFormat {
  /// QR Code.
  qrCode('QR_CODE'),

  /// Code 128 linear barcode.
  code128('CODE_128'),

  /// Code 39 linear barcode.
  code39('CODE_39'),

  /// Code 93 linear barcode.
  code93('CODE_93'),

  /// EAN-13 retail barcode.
  ean13('EAN_13'),

  /// EAN-8 retail barcode.
  ean8('EAN_8'),

  /// UPC-A retail barcode.
  upcA('UPC_A'),

  /// UPC-E retail barcode.
  upcE('UPC_E'),

  /// Interleaved 2 of 5 linear barcode.
  itf('ITF'),

  /// PDF417 stacked linear barcode.
  pdf417('PDF_417'),

  /// Data Matrix two-dimensional barcode.
  dataMatrix('DATA_MATRIX'),

  /// Aztec two-dimensional barcode.
  aztec('AZTEC'),

  /// An unrecognized format reported by a native scanner implementation.
  ///
  /// Kept last so adding it does not change the indices of existing enum values.
  unknown('UNKNOWN');

  /// Creates a scanner format with the native platform representation.
  const FlutterBarcodeScannerFormat(this.nativeValue);

  /// The value sent to Android ML Kit and iOS AVFoundation mapping code.
  final String nativeValue;

  /// Parses a native platform format value.
  ///
  /// Unknown values map to [FlutterBarcodeScannerFormat.unknown] so callers do
  /// not accidentally treat an unsupported symbology as a QR code.
  static FlutterBarcodeScannerFormat fromNativeValue(String? value) {
    final normalized = value?.toUpperCase().replaceAll('-', '_');
    return FlutterBarcodeScannerFormat.values.firstWhere(
      (format) => format.nativeValue == normalized,
      orElse: () => FlutterBarcodeScannerFormat.unknown,
    );
  }
}

/// Common format groups for [FlutterBarcodeScannerConfig.allowedFormats].
abstract final class FlutterBarcodeScannerFormats {
  /// All formats supported by the package.
  static const Set<FlutterBarcodeScannerFormat> all = {
    FlutterBarcodeScannerFormat.qrCode,
    FlutterBarcodeScannerFormat.code128,
    FlutterBarcodeScannerFormat.code39,
    FlutterBarcodeScannerFormat.code93,
    FlutterBarcodeScannerFormat.ean13,
    FlutterBarcodeScannerFormat.ean8,
    FlutterBarcodeScannerFormat.upcA,
    FlutterBarcodeScannerFormat.upcE,
    FlutterBarcodeScannerFormat.itf,
    FlutterBarcodeScannerFormat.pdf417,
    FlutterBarcodeScannerFormat.dataMatrix,
    FlutterBarcodeScannerFormat.aztec,
  };

  /// The most common ticket, retail, and QR formats.
  static const Set<FlutterBarcodeScannerFormat> common = {
    FlutterBarcodeScannerFormat.qrCode,
    FlutterBarcodeScannerFormat.code128,
    FlutterBarcodeScannerFormat.ean13,
    FlutterBarcodeScannerFormat.ean8,
    FlutterBarcodeScannerFormat.upcA,
    FlutterBarcodeScannerFormat.upcE,
  };

  /// Linear one-dimensional barcode formats.
  static const Set<FlutterBarcodeScannerFormat> oneDimensional = {
    FlutterBarcodeScannerFormat.code128,
    FlutterBarcodeScannerFormat.code39,
    FlutterBarcodeScannerFormat.code93,
    FlutterBarcodeScannerFormat.ean13,
    FlutterBarcodeScannerFormat.ean8,
    FlutterBarcodeScannerFormat.upcA,
    FlutterBarcodeScannerFormat.upcE,
    FlutterBarcodeScannerFormat.itf,
  };

  /// Two-dimensional barcode formats.
  static const Set<FlutterBarcodeScannerFormat> twoDimensional = {
    FlutterBarcodeScannerFormat.qrCode,
    FlutterBarcodeScannerFormat.pdf417,
    FlutterBarcodeScannerFormat.dataMatrix,
    FlutterBarcodeScannerFormat.aztec,
  };

  /// QR Code only.
  static const Set<FlutterBarcodeScannerFormat> qrOnly = {
    FlutterBarcodeScannerFormat.qrCode,
  };
}

/// The type of a scanner result.
enum FlutterBarcodeScannerResultType {
  /// A barcode was detected successfully.
  barcode,

  /// The user closed or cancelled the scanner.
  cancelled,

  /// The scanner returned an error payload.
  error,
}

/// The camera lens to use for initial or requested camera selection.
enum BarcodeCameraLens {
  /// Rear-facing camera.
  back,

  /// Front-facing camera.
  front,
}

/// Status bar icon brightness for the full-screen native scanner.
enum FlutterBarcodeScannerStatusBarIconBrightness {
  /// Light status bar icons for dark backgrounds.
  light,

  /// Dark status bar icons for light backgrounds.
  dark,
}

/// Runtime state emitted by [FlutterBarcodeScannerController.state].
enum FlutterBarcodeScannerViewState {
  /// The embedded scanner is attached but idle.
  idle,

  /// The native camera pipeline is being initialized.
  initializing,

  /// The camera preview and barcode detection are running.
  running,

  /// The camera is active but barcode detection is paused.
  detectionPaused,

  /// The camera has been stopped.
  cameraStopped,

  /// The native scanner reported an error.
  error,

  /// The native scanner view has been disposed.
  disposed,
}

/// Status bar styling for the full-screen scanner.
@immutable
class FlutterBarcodeScannerStatusBarStyle {
  /// Creates status bar styling for the native full-screen scanner.
  const FlutterBarcodeScannerStatusBarStyle({
    this.isTransparent = false,
    this.backgroundColor,
    this.iconBrightness = FlutterBarcodeScannerStatusBarIconBrightness.light,
  });

  /// Whether the status bar background should be transparent.
  ///
  /// Defaults to `false`.
  final bool isTransparent;

  /// Optional ARGB background color used when [isTransparent] is `false`.
  final Color? backgroundColor;

  /// Brightness of the native status bar icons.
  ///
  /// Defaults to [FlutterBarcodeScannerStatusBarIconBrightness.light].
  final FlutterBarcodeScannerStatusBarIconBrightness iconBrightness;

  /// Returns a copy with selected values replaced.
  FlutterBarcodeScannerStatusBarStyle copyWith({
    bool? isTransparent,
    Color? backgroundColor,
    bool clearBackgroundColor = false,
    FlutterBarcodeScannerStatusBarIconBrightness? iconBrightness,
  }) {
    return FlutterBarcodeScannerStatusBarStyle(
      isTransparent: isTransparent ?? this.isTransparent,
      backgroundColor: clearBackgroundColor
          ? null
          : backgroundColor ?? this.backgroundColor,
      iconBrightness: iconBrightness ?? this.iconBrightness,
    );
  }

  /// Converts this style into the method-channel payload map.
  Map<String, Object?> toMap() => {
    'isTransparent': isTransparent,
    'backgroundColor': backgroundColor?.toARGB32(),
    'iconBrightness': iconBrightness.name,
  };
}

/// Localizable strings shown by the scanner UI.
@immutable
class FlutterBarcodeScannerStrings {
  /// Creates UI strings for full-screen and embedded scanner controls.
  const FlutterBarcodeScannerStrings({
    this.title = 'Scan Ticket',
    this.close = 'Close',
    this.flashOn = 'Flash on',
    this.flashOff = 'Flash off',
    this.switchCamera = 'Switch camera',
    this.cameraPermissionRequired = 'Camera permission is required',
    this.cameraUnavailable = 'Camera unavailable',
  });

  /// Full-screen scanner title.
  final String title;

  /// Close button label.
  final String close;

  /// Tooltip or accessibility label for enabling the torch.
  final String flashOn;

  /// Tooltip or accessibility label for disabling the torch.
  final String flashOff;

  /// Tooltip or accessibility label for switching cameras.
  final String switchCamera;

  /// Message shown when camera permission is denied or unavailable.
  final String cameraPermissionRequired;

  /// Message shown when a camera cannot be opened.
  final String cameraUnavailable;

  /// Returns a copy with selected strings replaced.
  FlutterBarcodeScannerStrings copyWith({
    String? title,
    String? close,
    String? flashOn,
    String? flashOff,
    String? switchCamera,
    String? cameraPermissionRequired,
    String? cameraUnavailable,
  }) {
    return FlutterBarcodeScannerStrings(
      title: title ?? this.title,
      close: close ?? this.close,
      flashOn: flashOn ?? this.flashOn,
      flashOff: flashOff ?? this.flashOff,
      switchCamera: switchCamera ?? this.switchCamera,
      cameraPermissionRequired:
          cameraPermissionRequired ?? this.cameraPermissionRequired,
      cameraUnavailable: cameraUnavailable ?? this.cameraUnavailable,
    );
  }

  /// Converts the strings into the method-channel payload map.
  Map<String, Object?> toMap() => {
    'title': title,
    'close': close,
    'flashOn': flashOn,
    'flashOff': flashOff,
    'switchCamera': switchCamera,
    'cameraPermissionRequired': cameraPermissionRequired,
    'cameraUnavailable': cameraUnavailable,
  };
}

/// Region-of-interest configuration for barcode detection.
@immutable
class FlutterBarcodeScannerScanWindow {
  /// Creates scan-window configuration.
  const FlutterBarcodeScannerScanWindow({
    this.enabled = true,
    this.widthFactor = 0.58,
    this.heightFactor = 0.58,
    this.cornerRadius = 18,
  });

  /// Whether detection is limited to the centered scan window.
  ///
  /// When `false`, the whole native preview is scanned.
  final bool enabled;

  /// Width of the centered scan window as a fraction of the preview width.
  final double widthFactor;

  /// Height of the centered scan window as a fraction of the preview height.
  final double heightFactor;

  /// Corner radius, in logical pixels, for the scan-window overlay.
  final double cornerRadius;

  /// Width factor after applying the native scanner's supported bounds.
  double get effectiveWidthFactor => _normalizedFactor(
    widthFactor,
    minimum: 0.2,
    maximum: 0.95,
    fallback: 0.58,
  );

  /// Height factor after applying the native scanner's supported bounds.
  double get effectiveHeightFactor => _normalizedFactor(
    heightFactor,
    minimum: 0.2,
    maximum: 0.9,
    fallback: 0.58,
  );

  /// Non-negative finite corner radius used by scanner overlays.
  double get effectiveCornerRadius {
    if (!cornerRadius.isFinite) {
      return 18;
    }
    return cornerRadius < 0 ? 0 : cornerRadius;
  }

  /// Returns a copy with selected values replaced.
  FlutterBarcodeScannerScanWindow copyWith({
    bool? enabled,
    double? widthFactor,
    double? heightFactor,
    double? cornerRadius,
  }) {
    return FlutterBarcodeScannerScanWindow(
      enabled: enabled ?? this.enabled,
      widthFactor: widthFactor ?? this.widthFactor,
      heightFactor: heightFactor ?? this.heightFactor,
      cornerRadius: cornerRadius ?? this.cornerRadius,
    );
  }

  /// Converts the scan window into the method-channel payload map.
  Map<String, Object?> toMap() => {
    'enabled': enabled,
    'widthFactor': effectiveWidthFactor,
    'heightFactor': effectiveHeightFactor,
    'cornerRadius': effectiveCornerRadius,
  };

  static double _normalizedFactor(
    double value, {
    required double minimum,
    required double maximum,
    required double fallback,
  }) {
    if (!value.isFinite) {
      return fallback;
    }
    return value.clamp(minimum, maximum).toDouble();
  }
}

/// Native scanner control visibility and initial camera settings.
@immutable
class FlutterBarcodeScannerUiConfig {
  /// Creates scanner UI configuration.
  const FlutterBarcodeScannerUiConfig({
    this.showFlashButton = true,
    this.showCameraSwitchButton = true,
    this.initialCameraLens = BarcodeCameraLens.back,
    this.initialTorchEnabled = false,
  });

  /// Whether the native or default Flutter overlay should show a flash button.
  final bool showFlashButton;

  /// Whether the native or default Flutter overlay should show a camera switch.
  final bool showCameraSwitchButton;

  /// Camera lens selected when the scanner starts.
  final BarcodeCameraLens initialCameraLens;

  /// Whether the scanner should try to enable the torch when it starts.
  final bool initialTorchEnabled;

  /// Returns a copy with selected values replaced.
  FlutterBarcodeScannerUiConfig copyWith({
    bool? showFlashButton,
    bool? showCameraSwitchButton,
    BarcodeCameraLens? initialCameraLens,
    bool? initialTorchEnabled,
  }) {
    return FlutterBarcodeScannerUiConfig(
      showFlashButton: showFlashButton ?? this.showFlashButton,
      showCameraSwitchButton:
          showCameraSwitchButton ?? this.showCameraSwitchButton,
      initialCameraLens: initialCameraLens ?? this.initialCameraLens,
      initialTorchEnabled: initialTorchEnabled ?? this.initialTorchEnabled,
    );
  }

  /// Converts the UI configuration into the method-channel payload map.
  Map<String, Object?> toMap() => {
    'showFlashButton': showFlashButton,
    'showCameraSwitchButton': showCameraSwitchButton,
    'initialCameraLens': initialCameraLens.name,
    'initialTorchEnabled': initialTorchEnabled,
  };
}

/// Flutter-side configuration for [FlutterBarcodeScannerView].
@immutable
class FlutterBarcodeScannerWidgetConfig {
  /// Creates embedded scanner widget configuration.
  const FlutterBarcodeScannerWidgetConfig({
    this.autoRequestCameraPermission = true,
    this.freezePreviewWhenPaused = false,
    this.showPauseResumeButton = false,
    this.scanWindowBorderColor = Colors.white,
    this.pausedScanWindowBorderColor = const Color(0xFFE53935),
    this.pauseTooltip = 'Pause scanner',
    this.resumeTooltip = 'Resume scanner',
  });

  /// Whether the widget should request camera permission before creating the
  /// native platform view.
  final bool autoRequestCameraPermission;

  /// Whether the last camera frame should stay visible while detection is
  /// paused.
  final bool freezePreviewWhenPaused;

  /// Whether the default overlay should include a pause/resume button.
  final bool showPauseResumeButton;

  /// Scan-window border color while detection is running.
  final Color scanWindowBorderColor;

  /// Scan-window border color while detection is paused.
  final Color pausedScanWindowBorderColor;

  /// Tooltip for the default pause button.
  final String pauseTooltip;

  /// Tooltip for the default resume button.
  final String resumeTooltip;

  /// Returns a copy with selected values replaced.
  FlutterBarcodeScannerWidgetConfig copyWith({
    bool? autoRequestCameraPermission,
    bool? freezePreviewWhenPaused,
    bool? showPauseResumeButton,
    Color? scanWindowBorderColor,
    Color? pausedScanWindowBorderColor,
    String? pauseTooltip,
    String? resumeTooltip,
  }) {
    return FlutterBarcodeScannerWidgetConfig(
      autoRequestCameraPermission:
          autoRequestCameraPermission ?? this.autoRequestCameraPermission,
      freezePreviewWhenPaused:
          freezePreviewWhenPaused ?? this.freezePreviewWhenPaused,
      showPauseResumeButton:
          showPauseResumeButton ?? this.showPauseResumeButton,
      scanWindowBorderColor:
          scanWindowBorderColor ?? this.scanWindowBorderColor,
      pausedScanWindowBorderColor:
          pausedScanWindowBorderColor ?? this.pausedScanWindowBorderColor,
      pauseTooltip: pauseTooltip ?? this.pauseTooltip,
      resumeTooltip: resumeTooltip ?? this.resumeTooltip,
    );
  }

  /// Converts the widget configuration into the method-channel payload map.
  Map<String, Object?> toMap() => {
    'autoRequestCameraPermission': autoRequestCameraPermission,
    'freezePreviewWhenPaused': freezePreviewWhenPaused,
    'showPauseResumeButton': showPauseResumeButton,
    'scanWindowBorderColor': scanWindowBorderColor.toARGB32(),
    'pausedScanWindowBorderColor': pausedScanWindowBorderColor.toARGB32(),
    'pauseTooltip': pauseTooltip,
    'resumeTooltip': resumeTooltip,
  };
}

/// Shared configuration for full-screen and embedded scanner modes.
@immutable
class FlutterBarcodeScannerConfig {
  /// Creates scanner configuration.
  const FlutterBarcodeScannerConfig({
    this.allowedFormats = const {},
    this.strings = const FlutterBarcodeScannerStrings(),
    this.scanWindow = const FlutterBarcodeScannerScanWindow(),
    this.uiConfig = const FlutterBarcodeScannerUiConfig(),
    this.statusBarStyle = const FlutterBarcodeScannerStatusBarStyle(),
    this.textDirection,
    this.appBarTransparent = false,
    this.appBarBackgroundColor,
    this.appBarForegroundColor,
    this.overlayColor = const Color(0x99000000),
  });

  /// Formats the scanner should detect.
  ///
  /// An empty set means all supported formats. Use
  /// [FlutterBarcodeScannerFormats] for common presets.
  final Set<FlutterBarcodeScannerFormat> allowedFormats;

  /// Strings shown by scanner UI.
  final FlutterBarcodeScannerStrings strings;

  /// Scan-window region-of-interest configuration.
  final FlutterBarcodeScannerScanWindow scanWindow;

  /// Native and default overlay control configuration.
  final FlutterBarcodeScannerUiConfig uiConfig;

  /// Full-screen scanner status bar styling.
  final FlutterBarcodeScannerStatusBarStyle statusBarStyle;

  /// Optional forced text direction for scanner UI.
  final TextDirection? textDirection;

  /// Whether the full-screen scanner app bar should be transparent.
  final bool appBarTransparent;

  /// Optional full-screen scanner app bar background color.
  final Color? appBarBackgroundColor;

  /// Optional full-screen scanner app bar foreground color.
  final Color? appBarForegroundColor;

  /// Overlay color outside the scan window.
  final Color overlayColor;

  /// Returns a copy with selected values replaced.
  FlutterBarcodeScannerConfig copyWith({
    Set<FlutterBarcodeScannerFormat>? allowedFormats,
    FlutterBarcodeScannerStrings? strings,
    FlutterBarcodeScannerScanWindow? scanWindow,
    FlutterBarcodeScannerUiConfig? uiConfig,
    FlutterBarcodeScannerStatusBarStyle? statusBarStyle,
    TextDirection? textDirection,
    bool clearTextDirection = false,
    bool? appBarTransparent,
    Color? appBarBackgroundColor,
    bool clearAppBarBackgroundColor = false,
    Color? appBarForegroundColor,
    bool clearAppBarForegroundColor = false,
    Color? overlayColor,
  }) {
    return FlutterBarcodeScannerConfig(
      allowedFormats: allowedFormats ?? this.allowedFormats,
      strings: strings ?? this.strings,
      scanWindow: scanWindow ?? this.scanWindow,
      uiConfig: uiConfig ?? this.uiConfig,
      statusBarStyle: statusBarStyle ?? this.statusBarStyle,
      textDirection: clearTextDirection
          ? null
          : textDirection ?? this.textDirection,
      appBarTransparent: appBarTransparent ?? this.appBarTransparent,
      appBarBackgroundColor: clearAppBarBackgroundColor
          ? null
          : appBarBackgroundColor ?? this.appBarBackgroundColor,
      appBarForegroundColor: clearAppBarForegroundColor
          ? null
          : appBarForegroundColor ?? this.appBarForegroundColor,
      overlayColor: overlayColor ?? this.overlayColor,
    );
  }

  /// Converts this configuration into the method-channel payload map.
  Map<String, Object?> toPlatformMap() {
    if (allowedFormats.contains(FlutterBarcodeScannerFormat.unknown)) {
      throw ArgumentError.value(
        allowedFormats,
        'allowedFormats',
        'FlutterBarcodeScannerFormat.unknown cannot be requested.',
      );
    }
    return {
      'allowedFormats': allowedFormats
          .map((format) => format.nativeValue)
          .toList(),
      'strings': strings.toMap(),
      'scanWindow': scanWindow.toMap(),
      'uiConfig': uiConfig.toMap(),
      'statusBarStyle': statusBarStyle.toMap(),
      'textDirection': textDirection?.name,
      'appBarTransparent': appBarTransparent,
      'appBarBackgroundColor': appBarBackgroundColor?.toARGB32(),
      'appBarForegroundColor': appBarForegroundColor?.toARGB32(),
      'overlayColor': overlayColor.toARGB32(),
    };
  }
}

/// Result returned by full-screen scans and emitted by embedded scans.
@immutable
class FlutterBarcodeScanResult {
  /// Creates a scan result.
  const FlutterBarcodeScanResult({
    required this.type,
    required this.rawValue,
    required this.format,
    this.nativeFormat,
    this.errorCode,
    this.errorMessage,
  });

  /// Result kind.
  final FlutterBarcodeScannerResultType type;

  /// Raw decoded barcode value.
  ///
  /// This is empty for cancelled and error results.
  final String rawValue;

  /// Detected barcode format.
  final FlutterBarcodeScannerFormat format;

  /// Original format identifier received from the native implementation.
  ///
  /// This remains available when [format] is
  /// [FlutterBarcodeScannerFormat.unknown].
  final String? nativeFormat;

  /// Optional platform error code.
  final String? errorCode;

  /// Optional platform error message.
  final String? errorMessage;

  /// Whether this result represents a user cancellation.
  bool get isCancelled => type == FlutterBarcodeScannerResultType.cancelled;

  /// Whether this result contains a decoded barcode.
  bool get isBarcode => type == FlutterBarcodeScannerResultType.barcode;

  /// Whether this result represents a scanner error.
  bool get isError => type == FlutterBarcodeScannerResultType.error;

  /// Whether this result contains platform error details.
  bool get hasErrorDetails => errorCode != null || errorMessage != null;

  /// The decoded value when [isBarcode] is `true`; otherwise `null`.
  String? get valueOrNull => isBarcode ? rawValue : null;

  /// Returns a copy with selected values replaced.
  FlutterBarcodeScanResult copyWith({
    FlutterBarcodeScannerResultType? type,
    String? rawValue,
    FlutterBarcodeScannerFormat? format,
    String? nativeFormat,
    bool clearNativeFormat = false,
    String? errorCode,
    bool clearErrorCode = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return FlutterBarcodeScanResult(
      type: type ?? this.type,
      rawValue: rawValue ?? this.rawValue,
      format: format ?? this.format,
      nativeFormat: clearNativeFormat
          ? null
          : nativeFormat ?? this.nativeFormat,
      errorCode: clearErrorCode ? null : errorCode ?? this.errorCode,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }

  /// Parses a result payload received from native platform code.
  static FlutterBarcodeScanResult fromMap(Map<Object?, Object?> map) {
    final nativeFormat = map['format'] as String?;
    return FlutterBarcodeScanResult(
      type: FlutterBarcodeScannerResultType.values.firstWhere(
        (value) => value.name == map['type'],
        orElse: () => FlutterBarcodeScannerResultType.error,
      ),
      rawValue: (map['rawValue'] as String?) ?? '',
      format: FlutterBarcodeScannerFormat.fromNativeValue(nativeFormat),
      nativeFormat: nativeFormat,
      errorCode: map['errorCode'] as String?,
      errorMessage: map['errorMessage'] as String?,
    );
  }
}
