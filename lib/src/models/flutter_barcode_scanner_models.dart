import 'package:flutter/foundation.dart';
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

  /// The most common retail, logistics, and QR formats.
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

/// Camera permission state, as reported by the platform.
///
/// Android and iOS cannot report the same set of states, and the differences
/// are load-bearing rather than cosmetic:
///
/// - **[restricted] is iOS-only.** It means a policy such as Screen Time or MDM
///   forbids camera access, and the user cannot grant it themselves. Android
///   never reports it.
/// - **[denied] is effectively Android-only.** iOS shows its permission prompt
///   exactly once, so a denial there is already final and is reported as
///   [permanentlyDenied].
/// - **[notDetermined] on Android is inferred**, not read from the system.
///   Android cannot distinguish "never asked" from "denied permanently", so the
///   plugin records whether it has asked before. Clearing app data resets that
///   record, and a permission requested by other code in the same app is not
///   seen by it.
enum FlutterBarcodePermissionStatus {
  /// Camera access is available.
  granted,

  /// Access was refused, but asking again can still show the system prompt.
  ///
  /// Android only — see the notes on this enum.
  denied,

  /// Access was refused and the system will not prompt again.
  ///
  /// Only a change in Settings can grant it. Use
  /// [FlutterBarcodeScanner.openAppSettings].
  permanentlyDenied,

  /// A device policy forbids camera access and the user cannot change it.
  ///
  /// iOS only — see the notes on this enum.
  restricted,

  /// Access has not been requested yet.
  notDetermined;

  /// Whether the camera can be used.
  bool get isGranted => this == FlutterBarcodePermissionStatus.granted;

  /// Whether requesting again can still show the system prompt.
  ///
  /// `false` means asking again is a no-op and the user has to go to Settings.
  bool get canRequest =>
      this == FlutterBarcodePermissionStatus.notDetermined ||
      this == FlutterBarcodePermissionStatus.denied;

  /// Whether granting access now requires a trip to the system settings.
  bool get requiresSettings =>
      this == FlutterBarcodePermissionStatus.permanentlyDenied ||
      this == FlutterBarcodePermissionStatus.restricted;

  /// Parses a native status string.
  ///
  /// An unrecognized value maps to [denied] rather than [granted], so a native
  /// change this package version does not know about can never be mistaken for
  /// permission the user did not give.
  static FlutterBarcodePermissionStatus fromNativeValue(String? value) {
    return FlutterBarcodePermissionStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => FlutterBarcodePermissionStatus.denied,
    );
  }
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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is FlutterBarcodeScannerStatusBarStyle &&
        other.isTransparent == isTransparent &&
        other.backgroundColor == backgroundColor &&
        other.iconBrightness == iconBrightness;
  }

  @override
  int get hashCode =>
      Object.hash(isTransparent, backgroundColor, iconBrightness);
}

/// Localizable strings shown by the scanner UI.
@immutable
class FlutterBarcodeScannerStrings {
  /// Creates UI strings for full-screen and embedded scanner controls.
  const FlutterBarcodeScannerStrings({
    this.title = 'Scan Barcode',
    this.close = 'Close',
    this.flashOn = 'Flash on',
    this.flashOff = 'Flash off',
    this.switchCamera = 'Switch camera',
    this.cameraPermissionRequired = 'Camera permission is required',
    this.cameraUnavailable = 'Camera unavailable',
    this.permissionRetry = 'Allow camera access',
    this.permissionOpenSettings = 'Open settings',
    this.cameraPermissionPermanentlyDenied =
        'Camera access is turned off for this app. Enable it in Settings.',
    this.cameraPermissionRestricted =
        'Camera access is not allowed on this device.',
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

  /// Label of the button that re-requests camera permission.
  ///
  /// Flutter-side only; the native full-screen scanner does not show it.
  final String permissionRetry;

  /// Label of the button that opens the system settings for this app.
  ///
  /// Flutter-side only; the native full-screen scanner does not show it.
  final String permissionOpenSettings;

  /// Shown when permission was refused and the system will not prompt again.
  ///
  /// Flutter-side only.
  final String cameraPermissionPermanentlyDenied;

  /// Shown when a device policy forbids camera access. iOS only in practice.
  ///
  /// Flutter-side only.
  final String cameraPermissionRestricted;

  /// Returns a copy with selected strings replaced.
  FlutterBarcodeScannerStrings copyWith({
    String? title,
    String? close,
    String? flashOn,
    String? flashOff,
    String? switchCamera,
    String? cameraPermissionRequired,
    String? cameraUnavailable,
    String? permissionRetry,
    String? permissionOpenSettings,
    String? cameraPermissionPermanentlyDenied,
    String? cameraPermissionRestricted,
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
      permissionRetry: permissionRetry ?? this.permissionRetry,
      permissionOpenSettings:
          permissionOpenSettings ?? this.permissionOpenSettings,
      cameraPermissionPermanentlyDenied:
          cameraPermissionPermanentlyDenied ??
          this.cameraPermissionPermanentlyDenied,
      cameraPermissionRestricted:
          cameraPermissionRestricted ?? this.cameraPermissionRestricted,
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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is FlutterBarcodeScannerStrings &&
        other.title == title &&
        other.close == close &&
        other.flashOn == flashOn &&
        other.flashOff == flashOff &&
        other.switchCamera == switchCamera &&
        other.cameraPermissionRequired == cameraPermissionRequired &&
        other.cameraUnavailable == cameraUnavailable &&
        other.permissionRetry == permissionRetry &&
        other.permissionOpenSettings == permissionOpenSettings &&
        other.cameraPermissionPermanentlyDenied ==
            cameraPermissionPermanentlyDenied &&
        other.cameraPermissionRestricted == cameraPermissionRestricted;
  }

  @override
  int get hashCode => Object.hash(
    title,
    close,
    flashOn,
    flashOff,
    switchCamera,
    cameraPermissionRequired,
    cameraUnavailable,
    permissionRetry,
    permissionOpenSettings,
    cameraPermissionPermanentlyDenied,
    cameraPermissionRestricted,
  );
}

/// How a decoded barcode has to line up with the scan window to be reported.
///
/// Both modes rank surviving candidates by distance from the window's centre
/// and report the nearest, so a frame containing several codes still resolves
/// to one answer. They differ in which codes get that far.
enum FlutterBarcodeScanAimMode {
  /// A barcode qualifies when its bounds overlap the scan window.
  ///
  /// Forgiving: anything visibly inside the frame counts, so the user holds a
  /// code roughly in the box rather than aiming precisely. Faster to acquire,
  /// and safe when **only one barcode is ever in frame**.
  ///
  /// Do not use it for sheets, shelves or labels printed side by side. The
  /// scanner can only rank the barcodes the platform decoded, and iOS decodes
  /// an unpredictable subset of what is visible — so the code you are aiming at
  /// may not be among them, and a neighbour that was decoded wins instead. That
  /// is a wrong result, not a slow one.
  window,

  /// A barcode qualifies only when its own bounds contain the window's centre.
  ///
  /// The default, because it is the only rule that cannot report a barcode the
  /// user was not pointing at. Aiming becomes a point rather than an area: a
  /// neighbouring code can sit well inside the window and still lose, because
  /// the centre is not on it. The built-in overlay draws a crosshair at that
  /// point on both platforms, so the target is visible.
  ///
  /// The cost is acquisition time — the user must put the crosshair on the code
  /// — and on iOS an extra wait while the platform gets round to decoding it.
  /// Choose [window] only when a single barcode is ever in frame.
  crosshair;

  /// The identifier sent to the platform channel.
  String get nativeValue => name;
}

/// Region-of-interest configuration for barcode detection.
///
/// The window is described as a fraction of the preview's **width** plus an
/// [aspectRatio], rather than as a fraction of both axes. A fraction on each
/// axis makes the window's shape depend on the shape of whatever it is drawn
/// in: the same `0.8 × 0.4` config rendered as a 2.2:1 band inside a short
/// embedded preview and as a 1:1 square in the full-screen scanner. Fixing the
/// aspect ratio makes the window the same shape everywhere and lets only its
/// scale follow the preview.
@immutable
class FlutterBarcodeScannerScanWindow {
  /// Creates a scan window sized from the preview width and an aspect ratio.
  ///
  /// The window is centred, [widthFraction] of the preview wide, and
  /// `width / aspectRatio` tall. It is shrunk to fit when that height would
  /// not fit the preview, keeping the aspect ratio.
  ///
  /// Pass [rect] to place the window explicitly instead, in normalized preview
  /// coordinates. That brings back the shape-follows-container behaviour
  /// described on this class, so use it when you want the window pinned to a
  /// region of the preview rather than centred.
  const FlutterBarcodeScannerScanWindow({
    this.enabled = true,
    this.widthFraction = defaultWidthFraction,
    this.aspectRatio = defaultAspectRatio,
    this.rect,
    this.cornerRadius = 18,
    this.aimMode = FlutterBarcodeScanAimMode.crosshair,
  });

  /// Creates a scan window from width and height factors.
  ///
  /// Kept so code written against the pre-0.3.0 API still compiles. The
  /// geometry is **not** identical: equal factors used to collapse the window
  /// to a square at `min(width, height)`, an undocumented rule that made the
  /// old `0.58 / 0.58` default a narrow box on a portrait phone rather than the
  /// wide band it read as. That rule is gone, so equal factors now produce a
  /// true rectangle. Pass [rect] directly to say exactly what you mean.
  @Deprecated(
    'Use the default constructor. Sizing is now widthFraction plus '
    'aspectRatio, so the window keeps its shape on every preview. This '
    'constructor is removed in 0.4.0.',
  )
  factory FlutterBarcodeScannerScanWindow.fromFactors({
    bool enabled = true,
    double widthFactor = 0.58,
    double heightFactor = 0.58,
    double cornerRadius = 18,
  }) {
    final width = _clampFraction(widthFactor, fallback: defaultWidthFraction);
    final height = _clampFraction(heightFactor, fallback: 0.4);
    return FlutterBarcodeScannerScanWindow(
      enabled: enabled,
      rect: Rect.fromLTWH((1 - width) / 2, (1 - height) / 2, width, height),
      cornerRadius: cornerRadius,
    );
  }

  /// The share of the preview width the window spans when none is given.
  static const double defaultWidthFraction = 0.8;

  /// The width-to-height ratio used when none is given: 3:2.
  ///
  /// Wide enough that a linear code spans it comfortably, tall enough that a
  /// QR code is not squeezed. A window near 1:1 is the shape that made a dense
  /// sheet ambiguous, because several codes fit inside it at once.
  static const double defaultAspectRatio = 3 / 2;

  /// The largest share of the preview height the window may occupy.
  ///
  /// Only reached on a preview short enough that [aspectRatio] cannot be
  /// honoured at the requested width; the window shrinks rather than losing its
  /// shape.
  static const double maxHeightFraction = 0.9;

  /// Whether detection is limited to the scan window.
  ///
  /// When `false`, the whole native preview is scanned and candidates are
  /// ranked from the centre of the preview instead.
  final bool enabled;

  /// The share of the preview width the window spans, in `0.05...1.0`.
  ///
  /// Ignored when [rect] is set.
  final double widthFraction;

  /// The window's width divided by its height, in `0.2...5.0`.
  ///
  /// Values above 1 are wider than tall. Ignored when [rect] is set.
  final double aspectRatio;

  /// An explicit window in normalized preview coordinates, or `null`.
  ///
  /// Overrides [widthFraction] and [aspectRatio] when set. Each side is a
  /// fraction of the preview, so the window's shape follows the preview's —
  /// which is the behaviour the aspect-ratio sizing exists to avoid. Set it
  /// only when the window has to sit somewhere other than the centre.
  final Rect? rect;

  /// Corner radius, in logical pixels, for the scan-window overlay.
  final double cornerRadius;

  /// How a barcode has to line up with the window to be reported.
  ///
  /// Defaults to [FlutterBarcodeScanAimMode.crosshair], which is the only mode
  /// that cannot return a barcode the user was not pointing at.
  final FlutterBarcodeScanAimMode aimMode;

  /// [widthFraction] clamped into a usable range.
  double get effectiveWidthFraction =>
      _clampFraction(widthFraction, fallback: defaultWidthFraction);

  /// [aspectRatio] clamped into a usable range.
  double get effectiveAspectRatio {
    if (!aspectRatio.isFinite || aspectRatio <= 0) {
      return defaultAspectRatio;
    }
    return aspectRatio.clamp(0.2, 5.0).toDouble();
  }

  /// [rect] clamped into the preview, or `null` when no explicit rect is set.
  ///
  /// Non-finite or inverted values fall back to a centred window of the default
  /// proportions rather than producing a window nothing can be detected inside.
  Rect? get effectiveRect {
    final value = rect;
    if (value == null) {
      return null;
    }
    if (!value.left.isFinite ||
        !value.top.isFinite ||
        !value.width.isFinite ||
        !value.height.isFinite) {
      return null;
    }
    final width = _clampFraction(value.width, fallback: defaultWidthFraction);
    final height = _clampFraction(value.height, fallback: 0.4);
    final left = value.left.clamp(0.0, 1.0 - width).toDouble();
    final top = value.top.clamp(0.0, 1.0 - height).toDouble();
    return Rect.fromLTWH(left, top, width, height);
  }

  /// Non-negative finite corner radius used by scanner overlays.
  double get effectiveCornerRadius {
    if (!cornerRadius.isFinite) {
      return 18;
    }
    return cornerRadius < 0 ? 0 : cornerRadius;
  }

  /// Resolves the window against a concrete preview size, in preview pixels.
  ///
  /// Returns `null` when the window is disabled or the size is degenerate.
  ///
  /// This is the one definition of the geometry. The Kotlin and Swift layers
  /// reimplement it against their own preview sizes — the preview is not
  /// measured until it is laid out natively, so the config cannot carry a
  /// resolved rect — and each has a unit test asserting the same numbers.
  Rect? resolve(Size size) {
    if (!enabled || size.width <= 0 || size.height <= 0) {
      return null;
    }
    final fraction = effectiveRect;
    if (fraction != null) {
      return Rect.fromLTWH(
        fraction.left * size.width,
        fraction.top * size.height,
        fraction.width * size.width,
        fraction.height * size.height,
      );
    }
    final ratio = effectiveAspectRatio;
    var width = effectiveWidthFraction * size.width;
    var height = width / ratio;
    final maxHeight = size.height * maxHeightFraction;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * ratio;
    }
    if (width > size.width) {
      width = size.width;
      height = width / ratio;
    }
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: width,
      height: height,
    );
  }

  /// Returns a copy with selected values replaced.
  ///
  /// Pass `clearRect: true` to drop an explicit [rect] and go back to
  /// [widthFraction] / [aspectRatio] sizing; passing `rect: null` cannot
  /// express that, because it is indistinguishable from omitting the argument.
  FlutterBarcodeScannerScanWindow copyWith({
    bool? enabled,
    double? widthFraction,
    double? aspectRatio,
    Rect? rect,
    bool clearRect = false,
    double? cornerRadius,
    FlutterBarcodeScanAimMode? aimMode,
  }) {
    return FlutterBarcodeScannerScanWindow(
      enabled: enabled ?? this.enabled,
      widthFraction: widthFraction ?? this.widthFraction,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      rect: clearRect ? null : rect ?? this.rect,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      aimMode: aimMode ?? this.aimMode,
    );
  }

  /// Converts the scan window into the method-channel payload map.
  ///
  /// Sends the clamped values, so no layer re-derives a bound the others do
  /// not share. `rect` is `null` unless an explicit one was set.
  Map<String, Object?> toMap() {
    final fraction = effectiveRect;
    return {
      'enabled': enabled,
      'widthFraction': effectiveWidthFraction,
      'aspectRatio': effectiveAspectRatio,
      'maxHeightFraction': maxHeightFraction,
      'cornerRadius': effectiveCornerRadius,
      'aimMode': aimMode.nativeValue,
      'rect': fraction == null
          ? null
          : {
              'left': fraction.left,
              'top': fraction.top,
              'width': fraction.width,
              'height': fraction.height,
            },
    };
  }

  /// Whether two scan windows carry the same values.
  ///
  /// Compares the values as written, not the clamped `effective*` values, so
  /// two windows whose out-of-range rects happen to clamp to the same result
  /// are **not** equal.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is FlutterBarcodeScannerScanWindow &&
        other.enabled == enabled &&
        other.widthFraction == widthFraction &&
        other.aspectRatio == aspectRatio &&
        other.rect == rect &&
        other.cornerRadius == cornerRadius &&
        other.aimMode == aimMode;
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    widthFraction,
    aspectRatio,
    rect,
    cornerRadius,
    aimMode,
  );

  /// Clamps a fraction into a usable slice of the preview.
  ///
  /// The floor keeps a mistyped `0.0` from producing a window with no area.
  static double _clampFraction(double value, {required double fallback}) {
    if (!value.isFinite || value <= 0) {
      return fallback;
    }
    return value.clamp(0.05, 1.0).toDouble();
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
    this.keepScreenOn = false,
  });

  /// Whether the native or default Flutter overlay should show a flash button.
  final bool showFlashButton;

  /// Whether the native or default Flutter overlay should show a camera switch.
  final bool showCameraSwitchButton;

  /// Camera lens selected when the scanner starts.
  final BarcodeCameraLens initialCameraLens;

  /// Whether the scanner should try to enable the torch when it starts.
  final bool initialTorchEnabled;

  /// Whether the screen is kept awake while the camera is running.
  ///
  /// Off by default, so enabling the feature changes nothing for existing code.
  /// Turn it on for long scanning sessions, where the display timing out
  /// mid-shift is the usual complaint. The lock is released as soon as the
  /// camera stops, so it never outlives the scanner.
  final bool keepScreenOn;

  /// Returns a copy with selected values replaced.
  FlutterBarcodeScannerUiConfig copyWith({
    bool? showFlashButton,
    bool? showCameraSwitchButton,
    BarcodeCameraLens? initialCameraLens,
    bool? initialTorchEnabled,
    bool? keepScreenOn,
  }) {
    return FlutterBarcodeScannerUiConfig(
      showFlashButton: showFlashButton ?? this.showFlashButton,
      showCameraSwitchButton:
          showCameraSwitchButton ?? this.showCameraSwitchButton,
      initialCameraLens: initialCameraLens ?? this.initialCameraLens,
      initialTorchEnabled: initialTorchEnabled ?? this.initialTorchEnabled,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    );
  }

  /// Converts the UI configuration into the method-channel payload map.
  Map<String, Object?> toMap() => {
    'showFlashButton': showFlashButton,
    'showCameraSwitchButton': showCameraSwitchButton,
    'initialCameraLens': initialCameraLens.name,
    'initialTorchEnabled': initialTorchEnabled,
    'keepScreenOn': keepScreenOn,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is FlutterBarcodeScannerUiConfig &&
        other.showFlashButton == showFlashButton &&
        other.showCameraSwitchButton == showCameraSwitchButton &&
        other.initialCameraLens == initialCameraLens &&
        other.initialTorchEnabled == initialTorchEnabled &&
        other.keepScreenOn == keepScreenOn;
  }

  @override
  int get hashCode => Object.hash(
    showFlashButton,
    showCameraSwitchButton,
    initialCameraLens,
    initialTorchEnabled,
    keepScreenOn,
  );
}

/// Whether a validated scan was accepted or rejected.
enum FlutterBarcodeScanDecisionOutcome {
  /// The scan was accepted.
  accepted,

  /// The scan was rejected.
  rejected,
}

/// The outcome returned from `FlutterBarcodeScannerView.onScanValidate`.
///
/// Returning a decision drives the scan → validate → accept/reject loop: the
/// scanner holds detection while the decision is awaited, shows accepted or
/// rejected feedback for
/// [FlutterBarcodeScannerWidgetConfig.validationFeedbackDuration], then resumes
/// on its own.
///
/// ```dart
/// onScanValidate: (result) async {
///   final check = await api.validate(result.rawValue);
///   return check.isValid
///       ? const ScanDecision.accept(message: 'Admitted')
///       : const ScanDecision.reject(message: 'Already used');
/// }
/// ```
@immutable
class ScanDecision {
  /// Accepts the scan, optionally showing [message] in the feedback overlay.
  const ScanDecision.accept({this.message})
    : outcome = FlutterBarcodeScanDecisionOutcome.accepted;

  /// Rejects the scan, optionally showing [message] in the feedback overlay.
  const ScanDecision.reject({this.message})
    : outcome = FlutterBarcodeScanDecisionOutcome.rejected;

  /// Whether the scan was accepted or rejected.
  final FlutterBarcodeScanDecisionOutcome outcome;

  /// Optional text shown in the feedback overlay.
  ///
  /// `null` shows the outcome without a caption.
  final String? message;

  /// Whether this decision accepted the scan.
  bool get isAccepted => outcome == FlutterBarcodeScanDecisionOutcome.accepted;

  /// Whether this decision rejected the scan.
  bool get isRejected => outcome == FlutterBarcodeScanDecisionOutcome.rejected;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ScanDecision &&
        other.outcome == outcome &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(outcome, message);
}

/// A decision paired with the scan it was made about.
///
/// Published on [FlutterBarcodeScannerController.feedbackListenable] while the
/// feedback overlay is showing, and `null` at every other time. Read it to
/// render accepted/rejected state from a custom `overlayBuilder`.
@immutable
class FlutterBarcodeScanFeedback {
  /// Creates feedback for a validated scan.
  const FlutterBarcodeScanFeedback({
    required this.decision,
    required this.result,
  });

  /// The decision returned by the validator.
  final ScanDecision decision;

  /// The scan the decision was made about.
  final FlutterBarcodeScanResult result;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is FlutterBarcodeScanFeedback &&
        other.decision == decision &&
        other.result == result;
  }

  @override
  int get hashCode => Object.hash(decision, result);
}

/// Flutter-side configuration for [FlutterBarcodeScannerView].
@immutable
class FlutterBarcodeScannerWidgetConfig {
  /// Creates embedded scanner widget configuration.
  const FlutterBarcodeScannerWidgetConfig({
    this.autoRequestCameraPermission = true,
    this.showPauseResumeButton = false,
    this.scanWindowBorderColor = Colors.white,
    this.pausedScanWindowBorderColor = const Color(0xFFE53935),
    this.pauseTooltip = 'Pause scanner',
    this.resumeTooltip = 'Resume scanner',
    this.validationFeedbackDuration = const Duration(milliseconds: 900),
    this.duplicateScanCooldown = const Duration(milliseconds: 250),
    this.hapticFeedbackOnAccept = true,
    this.soundOnAccept = false,
  });

  /// Whether the widget should request camera permission before creating the
  /// native platform view.
  final bool autoRequestCameraPermission;

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

  /// How long accepted/rejected feedback stays on screen before detection
  /// resumes.
  ///
  /// Only used when `FlutterBarcodeScannerView.onScanValidate` is supplied.
  /// [Duration.zero] resumes as soon as the decision arrives, showing no
  /// feedback at all.
  final Duration validationFeedbackDuration;

  /// How long the same decoded value is ignored after it is first reported.
  ///
  /// Continuous scanning re-decodes a code many times a second, so without this
  /// a single physical barcode produces a burst of identical results. Only
  /// repeats of the *same* value are suppressed — moving to a different code is
  /// reported immediately, which matters when scanning a dense sheet.
  ///
  /// Applies to barcode results only; cancellations and errors are never
  /// filtered. Set to [Duration.zero] to report every decode.
  final Duration duplicateScanCooldown;

  /// Whether an accepted scan fires a short haptic tap.
  ///
  /// Only fires for `FlutterBarcodeScannerView.onScanValidate` decisions that
  /// accept, so enabling it by default changes nothing for existing code.
  /// Suppressed automatically when the platform reports Reduce Motion.
  final bool hapticFeedbackOnAccept;

  /// Whether an accepted scan plays the platform's short system sound.
  ///
  /// Off by default because an audible scanner is a deliberate choice. Uses the
  /// system sound rather than a bundled asset, which is what makes it respect
  /// the iOS silent switch — Flutter cannot query that switch directly.
  final bool soundOnAccept;

  /// Returns a copy with selected values replaced.
  FlutterBarcodeScannerWidgetConfig copyWith({
    bool? autoRequestCameraPermission,
    bool? showPauseResumeButton,
    Color? scanWindowBorderColor,
    Color? pausedScanWindowBorderColor,
    String? pauseTooltip,
    String? resumeTooltip,
    Duration? validationFeedbackDuration,
    Duration? duplicateScanCooldown,
    bool? hapticFeedbackOnAccept,
    bool? soundOnAccept,
  }) {
    return FlutterBarcodeScannerWidgetConfig(
      autoRequestCameraPermission:
          autoRequestCameraPermission ?? this.autoRequestCameraPermission,
      showPauseResumeButton:
          showPauseResumeButton ?? this.showPauseResumeButton,
      scanWindowBorderColor:
          scanWindowBorderColor ?? this.scanWindowBorderColor,
      pausedScanWindowBorderColor:
          pausedScanWindowBorderColor ?? this.pausedScanWindowBorderColor,
      pauseTooltip: pauseTooltip ?? this.pauseTooltip,
      resumeTooltip: resumeTooltip ?? this.resumeTooltip,
      validationFeedbackDuration:
          validationFeedbackDuration ?? this.validationFeedbackDuration,
      duplicateScanCooldown:
          duplicateScanCooldown ?? this.duplicateScanCooldown,
      hapticFeedbackOnAccept:
          hapticFeedbackOnAccept ?? this.hapticFeedbackOnAccept,
      soundOnAccept: soundOnAccept ?? this.soundOnAccept,
    );
  }

  /// Converts the widget configuration into the method-channel payload map.
  Map<String, Object?> toMap() => {
    'autoRequestCameraPermission': autoRequestCameraPermission,
    'showPauseResumeButton': showPauseResumeButton,
    'scanWindowBorderColor': scanWindowBorderColor.toARGB32(),
    'pausedScanWindowBorderColor': pausedScanWindowBorderColor.toARGB32(),
    'pauseTooltip': pauseTooltip,
    'resumeTooltip': resumeTooltip,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is FlutterBarcodeScannerWidgetConfig &&
        other.autoRequestCameraPermission == autoRequestCameraPermission &&
        other.showPauseResumeButton == showPauseResumeButton &&
        other.scanWindowBorderColor == scanWindowBorderColor &&
        other.pausedScanWindowBorderColor == pausedScanWindowBorderColor &&
        other.pauseTooltip == pauseTooltip &&
        other.resumeTooltip == resumeTooltip &&
        other.validationFeedbackDuration == validationFeedbackDuration &&
        other.duplicateScanCooldown == duplicateScanCooldown &&
        other.hapticFeedbackOnAccept == hapticFeedbackOnAccept &&
        other.soundOnAccept == soundOnAccept;
  }

  @override
  int get hashCode => Object.hash(
    autoRequestCameraPermission,
    showPauseResumeButton,
    scanWindowBorderColor,
    pausedScanWindowBorderColor,
    pauseTooltip,
    resumeTooltip,
    validationFeedbackDuration,
    duplicateScanCooldown,
    hapticFeedbackOnAccept,
    soundOnAccept,
  );
}

/// Shared configuration for full-screen and embedded scanner modes.
///
/// Unlike the other configuration models this class has **no `const`
/// constructor**. It validates [allowedFormats] in an assert, and Dart forbids
/// a non-constant expression such as `Set.contains` in the initializer list of
/// a `const` constructor. The nested models — [FlutterBarcodeScannerStrings],
/// [FlutterBarcodeScannerScanWindow], [FlutterBarcodeScannerUiConfig] and
/// [FlutterBarcodeScannerStatusBarStyle] — are all still `const`-constructible.
@immutable
class FlutterBarcodeScannerConfig {
  /// Creates scanner configuration.
  ///
  /// Asserts that [allowedFormats] does not contain
  /// [FlutterBarcodeScannerFormat.unknown], which is the label reported for a
  /// symbology the package does not recognise and is never something the
  /// scanner can be asked to detect. The check runs at construction, so an
  /// invalid set fails on the line that wrote it rather than from inside
  /// `build()`.
  FlutterBarcodeScannerConfig({
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
    this.scanConfirmationFrames = defaultScanConfirmationFrames,
  }) : assert(
         !allowedFormats.contains(FlutterBarcodeScannerFormat.unknown),
         'FlutterBarcodeScannerFormat.unknown cannot be requested. It is the '
         'label reported when a native scanner returns a symbology this '
         'package does not recognise, not a format the scanner can detect. '
         'Remove it from allowedFormats.',
       );

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

  /// How many consecutive observations must agree before a scan is reported.
  ///
  /// A camera decodes many times a second, so the first code to touch the scan
  /// window wins — even when the phone is still sweeping towards the one the
  /// user meant. Requiring the same value to stay the best candidate for a few
  /// observations in a row discards those, because a code caught in passing
  /// does not stay selected. This is the detector-side recommendation for
  /// video: act on a consecutive series of the same value, not a single frame.
  ///
  /// `1` reports the first observation, which is the pre-0.3.0 behaviour.
  /// Clamped to `1...10`. Each extra observation costs roughly one frame of
  /// latency.
  ///
  /// **What an observation is differs by platform.** On Android it is an
  /// analyzer frame, delivered continuously whether or not anything decodes.
  /// On iOS it is an `AVCaptureMetadataOutput` callback, which only fires when
  /// something *is* decoded. Both discard progress once nothing has been seen
  /// for a moment, so a code re-entering the frame is never confirmed by
  /// observations made before the user looked away.
  final int scanConfirmationFrames;

  /// The confirmation count used when none is given.
  static const int defaultScanConfirmationFrames = 2;

  /// [scanConfirmationFrames] clamped into the supported range.
  int get effectiveScanConfirmationFrames =>
      scanConfirmationFrames.clamp(1, 10);

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
    int? scanConfirmationFrames,
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
      scanConfirmationFrames:
          scanConfirmationFrames ?? this.scanConfirmationFrames,
    );
  }

  /// Converts this configuration into the method-channel payload map.
  ///
  /// Throws [ArgumentError] if [allowedFormats] contains
  /// [FlutterBarcodeScannerFormat.unknown]. The constructor already asserts
  /// this, which is what catches the mistake during development; this throw is
  /// the release-mode backstop, because asserts are stripped from release
  /// builds and an unrecognised format must never reach native code.
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
      'scanConfirmationFrames': effectiveScanConfirmationFrames,
    };
  }

  /// Whether two configurations carry the same values.
  ///
  /// [allowedFormats] is compared as an unordered set, so two configurations
  /// listing the same formats in a different order are equal.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is FlutterBarcodeScannerConfig &&
        setEquals(other.allowedFormats, allowedFormats) &&
        other.strings == strings &&
        other.scanWindow == scanWindow &&
        other.uiConfig == uiConfig &&
        other.statusBarStyle == statusBarStyle &&
        other.textDirection == textDirection &&
        other.appBarTransparent == appBarTransparent &&
        other.appBarBackgroundColor == appBarBackgroundColor &&
        other.appBarForegroundColor == appBarForegroundColor &&
        other.overlayColor == overlayColor &&
        other.scanConfirmationFrames == scanConfirmationFrames;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(allowedFormats),
    strings,
    scanWindow,
    uiConfig,
    statusBarStyle,
    textDirection,
    appBarTransparent,
    appBarBackgroundColor,
    appBarForegroundColor,
    overlayColor,
    scanConfirmationFrames,
  );
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
