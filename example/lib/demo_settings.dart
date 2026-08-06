import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner_sdk/flutter_barcode_scanner_sdk.dart';

/// String presets used to show `textDirection` and localization together.
enum DemoLanguage { english, hebrew }

/// Format groupings offered on the configuration page.
enum FormatPreset { all, qrAndCode128, twoDimensionalOnly, oneDimensionalOnly }

/// Every knob the demo exposes, in one place.
///
/// The pages are thin: they render controls bound to this object and read
/// [buildConfig] / [buildWidgetConfig] back out, so a setting changed on the
/// configuration page is already in force everywhere else.
class DemoSettings extends ChangeNotifier {
  static const appBarColors = <Color>[
    Color(0xFF0A1C58),
    Color(0xFF0D3B2E),
    Color(0xFF4A1D1F),
    Color(0xFF263238),
  ];

  static const overlayOptions = <double>[0.30, 0.45, 0.60, 0.72];

  static const pausedBorderColors = <Color>[
    Color(0xFFE53935),
    Color(0xFFFFB300),
    Color(0xFF00C853),
    Color(0xFF40C4FF),
  ];

  // Scanning
  FormatPreset formatPreset = FormatPreset.qrAndCode128;
  bool autoStart = true;
  bool autoPauseOnScan = true;
  bool keepScreenOn = false;
  Duration duplicateScanCooldown = const Duration(milliseconds: 250);

  // Scan window
  bool scanWindowEnabled = true;
  double scanWindowWidthFraction =
      FlutterBarcodeScannerScanWindow.defaultWidthFraction;
  double scanWindowAspectRatio =
      FlutterBarcodeScannerScanWindow.defaultAspectRatio;
  double scanWindowCornerRadius = 18;
  FlutterBarcodeScanAimMode aimMode = FlutterBarcodeScanAimMode.window;
  int scanConfirmationFrames =
      FlutterBarcodeScannerConfig.defaultScanConfirmationFrames;

  // Feedback
  bool hapticFeedbackOnAccept = true;
  bool soundOnAccept = false;
  Duration validationFeedbackDuration = const Duration(milliseconds: 900);
  int pausedBorderColorIndex = 0;
  bool showPauseResumeButton = false;

  // Permissions
  bool autoRequestCameraPermission = true;

  // Native chrome
  bool showFlashButton = true;
  bool showCameraSwitchButton = true;
  bool initialTorchEnabled = false;
  BarcodeCameraLens initialCameraLens = BarcodeCameraLens.back;
  bool statusBarTransparent = false;
  bool appBarTransparent = false;
  FlutterBarcodeScannerStatusBarIconBrightness statusBarIconBrightness =
      FlutterBarcodeScannerStatusBarIconBrightness.light;
  int appBarColorIndex = 0;
  int overlayOpacityIndex = 2;

  // Strings and direction
  DemoLanguage language = DemoLanguage.english;
  TextDirection? scannerTextDirection = TextDirection.ltr;

  /// Applies [change] and notifies listeners.
  void update(VoidCallback change) {
    change();
    notifyListeners();
  }

  Set<FlutterBarcodeScannerFormat> get allowedFormats {
    return switch (formatPreset) {
      FormatPreset.all => FlutterBarcodeScannerFormats.all,
      FormatPreset.qrAndCode128 => const {
        FlutterBarcodeScannerFormat.qrCode,
        FlutterBarcodeScannerFormat.code128,
      },
      FormatPreset.twoDimensionalOnly =>
        FlutterBarcodeScannerFormats.twoDimensional,
      FormatPreset.oneDimensionalOnly =>
        FlutterBarcodeScannerFormats.oneDimensional,
    };
  }

  String get formatSummary {
    return switch (formatPreset) {
      FormatPreset.all => 'All supported formats',
      FormatPreset.qrAndCode128 => 'QR Code + CODE_128',
      FormatPreset.twoDimensionalOnly => 'QR + PDF417 + Data Matrix + Aztec',
      FormatPreset.oneDimensionalOnly =>
        'CODE_128 + CODE_39 + CODE_93 + EAN/UPC + ITF',
    };
  }

  String formatPresetLabel(FormatPreset preset) {
    return switch (preset) {
      FormatPreset.all => 'All',
      FormatPreset.qrAndCode128 => 'QR + 128',
      FormatPreset.twoDimensionalOnly => '2D only',
      FormatPreset.oneDimensionalOnly => '1D only',
    };
  }

  FlutterBarcodeScannerStrings get strings {
    return switch (language) {
      DemoLanguage.english => const FlutterBarcodeScannerStrings(),
      DemoLanguage.hebrew => const FlutterBarcodeScannerStrings(
        title: 'סרוק ברקוד',
        close: 'סגור',
        flashOn: 'הפעל פלאש',
        flashOff: 'כבה פלאש',
        switchCamera: 'החלף מצלמה',
        cameraPermissionRequired: 'נדרשת הרשאת מצלמה',
        cameraUnavailable: 'המצלמה אינה זמינה',
        permissionRetry: 'אפשר גישה למצלמה',
        permissionOpenSettings: 'פתח הגדרות',
      ),
    };
  }

  /// The configuration handed to native code.
  FlutterBarcodeScannerConfig buildConfig() {
    final appBarColor = appBarColors[appBarColorIndex];
    return FlutterBarcodeScannerConfig(
      allowedFormats: allowedFormats,
      strings: strings,
      scanWindow: FlutterBarcodeScannerScanWindow(
        enabled: scanWindowEnabled,
        widthFraction: scanWindowWidthFraction,
        aspectRatio: scanWindowAspectRatio,
        cornerRadius: scanWindowCornerRadius,
        aimMode: aimMode,
      ),
      scanConfirmationFrames: scanConfirmationFrames,
      uiConfig: FlutterBarcodeScannerUiConfig(
        showFlashButton: showFlashButton,
        showCameraSwitchButton: showCameraSwitchButton,
        initialCameraLens: initialCameraLens,
        initialTorchEnabled: initialTorchEnabled,
        keepScreenOn: keepScreenOn,
      ),
      statusBarStyle: FlutterBarcodeScannerStatusBarStyle(
        isTransparent: statusBarTransparent,
        backgroundColor: statusBarTransparent ? null : appBarColor,
        iconBrightness: statusBarIconBrightness,
      ),
      textDirection: scannerTextDirection,
      appBarTransparent: appBarTransparent,
      appBarBackgroundColor: appBarColor,
      appBarForegroundColor: Colors.white,
      overlayColor: Colors.black.withValues(
        alpha: overlayOptions[overlayOpacityIndex],
      ),
    );
  }

  /// The Flutter-side configuration for the embedded view.
  FlutterBarcodeScannerWidgetConfig buildWidgetConfig() {
    return FlutterBarcodeScannerWidgetConfig(
      autoRequestCameraPermission: autoRequestCameraPermission,
      showPauseResumeButton: showPauseResumeButton,
      pausedScanWindowBorderColor: pausedBorderColors[pausedBorderColorIndex],
      validationFeedbackDuration: validationFeedbackDuration,
      duplicateScanCooldown: duplicateScanCooldown,
      hapticFeedbackOnAccept: hapticFeedbackOnAccept,
      soundOnAccept: soundOnAccept,
    );
  }
}

/// Makes the single [DemoSettings] instance available to every page.
class DemoSettingsScope extends InheritedNotifier<DemoSettings> {
  const DemoSettingsScope({
    required DemoSettings super.notifier,
    required super.child,
    super.key,
  });

  static DemoSettings of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DemoSettingsScope>();
    assert(scope?.notifier != null, 'No DemoSettingsScope above this widget');
    return scope!.notifier!;
  }
}
