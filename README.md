# Flutter Barcode Scanner SDK

[![pub package](https://img.shields.io/pub/v/flutter_barcode_scanner_sdk.svg)](https://pub.dev/packages/flutter_barcode_scanner_sdk)
[![CI](https://github.com/guy-evdev/flutter_barcode_scanner_sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/guy-evdev/flutter_barcode_scanner_sdk/actions/workflows/ci.yml)

High-throughput barcode and QR scanner SDK for Flutter apps.

The package provides two native scanning modes:

- `FlutterBarcodeScanner.scan(config)` opens a full-screen scanner and returns one result.
- `FlutterBarcodeScannerView` embeds the native scanner in a Flutter layout and emits results through a controller-friendly widget API.

Android uses CameraX with ML Kit Barcode Scanning. iOS uses AVFoundation. The iOS plugin supports Swift Package Manager and CocoaPods.

## When to use this package

- **Decoding happens on-device.** No network call is made, and no barcode data leaves the phone.
- **No Google Play services requirement.** Android decoding uses the bundled ML Kit barcode model, so it works on devices without Play services.
- **Native decode paths on both platforms** — CameraX with ML Kit on Android, AVFoundation metadata output on iOS — rather than a single cross-platform decoder.
- **Both embedded and full-screen modes** ship from one package and share their configuration.
- **Built for sustained scanning**, where a shift means thousands of scans: detection pauses without rebinding the camera, and the example app ships a soak harness that reports memory, dropped frames, and decode latency.
- **Not a fit if** you need web or desktop support, or barcode generation. This package is Android and iOS, scanning only.

## Contents

- [Platform Support](#platform-support)
- [Installation](#installation)
- [Permissions](#permissions)
- [Full-Screen Scanner](#full-screen-scanner)
- [Embedded Scanner](#embedded-scanner)
- [Format Presets](#format-presets)
- [Example App](#example-app)
- [Recipes](#recipes)
- [API Reference](#api-reference)
- [Compatibility](#compatibility)
- [Migration](#migration)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Platform Support

| Platform | Minimum | Native engine |
| --- | --- | --- |
| Android | API 24 | CameraX + ML Kit Barcode Scanning |
| iOS | 15.0 | AVFoundation metadata scanning |
| Flutter | 3.44.0 | AGP 9 / Gradle 9 Android plugin build |
| Dart | 3.12.0 | Sound null safety |

## Installation

```yaml
dependencies:
  flutter_barcode_scanner_sdk: ^0.2.1
```

Then run:

```sh
flutter pub get
```

## Permissions

### Android

The plugin declares `android.permission.CAMERA`. If your app has a custom manifest merge setup, confirm that the merged app manifest includes:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

### iOS

Add a camera usage description to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app scans barcodes with the camera.</string>
```

## Full-Screen Scanner

```dart
final result = await FlutterBarcodeScanner.scan(
  const FlutterBarcodeScannerConfig(
    allowedFormats: FlutterBarcodeScannerFormats.common,
    strings: FlutterBarcodeScannerStrings(title: 'Scan ticket'),
  ),
);

if (result?.isBarcode == true) {
  debugPrint('Scanned ${result!.format.name}: ${result.rawValue}');
}
```

## Embedded Scanner

```dart
final controller = FlutterBarcodeScannerController();

FlutterBarcodeScannerView(
  controller: controller,
  config: const FlutterBarcodeScannerConfig(
    allowedFormats: FlutterBarcodeScannerFormats.qrOnly,
    scanWindow: FlutterBarcodeScannerScanWindow(
      enabled: true,
      widthFactor: 0.58,
      heightFactor: 0.58,
    ),
  ),
  widgetConfig: const FlutterBarcodeScannerWidgetConfig(
    autoRequestCameraPermission: true,
    showPauseResumeButton: true,
  ),
  autoStart: true,
  autoPauseOnScan: true,
  onScan: (result) {
    if (result.isBarcode) {
      // Process the result, then resume when ready for another scan.
      controller.resumeDetection();
    }
  },
);
```

Controller actions:

- `startCamera()` and `stopCamera()`
- `pauseDetection()` and `resumeDetection()`
- `toggleFlash([bool? enabled])`
- `switchCamera([BarcodeCameraLens? lens])`
- `updateConfig(config)`
- `dispose()`

## Format Presets

Use `FlutterBarcodeScannerFormats` for common format groups:

```dart
const FlutterBarcodeScannerConfig(
  allowedFormats: FlutterBarcodeScannerFormats.twoDimensional,
);
```

Available presets include `all`, `common`, `oneDimensional`, `twoDimensional`, and `qrOnly`.

## Example App

The bundled [example app](example) demonstrates:

- Full-screen and embedded scanner modes
- Scan-window and whole-preview detection
- RTL/LTR strings
- Flash and camera switching
- Auto-start, auto-pause, and pause/resume behavior
- App bar, status bar, overlay, and format preset options
- A stress harness for sustained-scanning runs, in the app bar

Run it with:

```sh
cd example
flutter run
```

## Recipes

See [RECIPES.md](RECIPES.md) for the continuous entry-scanning loop, custom overlays,
scan-window geometry, error codes, and the platform differences between the Android and iOS
engines.

## API Reference

See [API_REFERENCE.md](API_REFERENCE.md) for tables covering all public configuration fields, defaults, result fields, controller methods, and supported barcode formats.

Generated Dart API docs are available on pub.dev after publication.

## Compatibility

See [COMPATIBILITY.md](COMPATIBILITY.md) for supported Flutter, Android, iOS,
SwiftPM/CocoaPods, dependency-update, and API-compatibility policies.

## Migration

See [MIGRATION.md](MIGRATION.md) for the code changes each release needs, newest first.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Permission screen does not appear | Confirm camera permission is in the Android manifest or `NSCameraUsageDescription` is in `Info.plist`. |
| Embedded scanner stays black | Ensure the widget has non-zero size and the controller has not been disposed. |
| No barcode is detected | Try `scanWindow.enabled = false`, verify lighting/focus, and restrict `allowedFormats` only when the expected format is known. |
| iOS build integration issue | Use Flutter 3.44 or newer and keep Swift Package Manager enabled; CocoaPods remains supported through the podspec. |

## License

BSD 3. See [LICENSE](LICENSE).
