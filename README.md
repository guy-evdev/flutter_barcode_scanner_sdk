# Flutter Barcode Scanner SDK

[![pub package](https://img.shields.io/pub/v/flutter_barcode_scanner_sdk.svg)](https://pub.dev/packages/flutter_barcode_scanner_sdk)
[![CI](https://github.com/guy-evdev/flutter_barcode_scanner_sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/guy-evdev/flutter_barcode_scanner_sdk/actions/workflows/ci.yml)

High-throughput barcode and QR scanner SDK for Flutter apps.

The package provides two native scanning modes:

- `FlutterBarcodeScanner.scan(config)` opens a full-screen scanner and returns one result.
- `FlutterBarcodeScannerView` embeds the native scanner in a Flutter layout and emits results through a controller-friendly widget API.

Android uses CameraX with ML Kit Barcode Scanning. iOS uses AVFoundation capture with Apple's Vision framework for decoding. The iOS plugin supports Swift Package Manager and CocoaPods.

## When to use this package

- **Decoding happens on-device.** No network call is made, and no barcode data leaves the phone.
- **No Google Play services requirement.** Android decoding uses the bundled ML Kit barcode model, so it works on devices without Play services.
- **Native decode paths on both platforms** — CameraX with ML Kit on Android, Vision on iOS — rather than a single cross-platform decoder. Both report every barcode in a frame, so the scanner picks the one you aimed at rather than the first one the platform happened to return.
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
| iOS | 15.0 | AVFoundation capture, Vision decoding |
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
  FlutterBarcodeScannerConfig(
    allowedFormats: FlutterBarcodeScannerFormats.common,
    strings: FlutterBarcodeScannerStrings(title: 'Scan barcode'),
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
  config: FlutterBarcodeScannerConfig(
    allowedFormats: FlutterBarcodeScannerFormats.qrOnly,
  ),
  onScan: (result) {
    if (result.isBarcode) {
      debugPrint(result.rawValue);
    }
  },
);
```

### Validate each scan

Scanning one code after another is a loop: detect, check it, move on. Return a decision and
the scanner runs that loop for you — holding detection while your check runs, showing accepted
or rejected feedback, then resuming:

```dart
FlutterBarcodeScannerView(
  config: FlutterBarcodeScannerConfig(),
  onScanValidate: (result) async {
    final check = await api.validate(result.rawValue);
    return check.isValid
        ? const ScanDecision.accept(message: 'Accepted')
        : const ScanDecision.reject(message: 'Rejected');
  },
);
```

A slow or failing check cannot double-scan or wedge the scanner. See
[RECIPES.md](RECIPES.md#continuous-entry-scanning) for the guarantees, and for driving
pause/resume yourself instead.

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
FlutterBarcodeScannerConfig(
  allowedFormats: FlutterBarcodeScannerFormats.twoDimensional,
);
```

Available presets include `all`, `common`, `oneDimensional`, `twoDimensional`, and `qrOnly`.

## Example App

The bundled [example app](example) demonstrates:

- Full-screen and embedded scanner modes
- The scan → validate → accept/reject loop, with an adjustable decision delay
- The camera-permission states and the route to Settings
- Scan-window shape, aim mode, and confirmation observations
- RTL/LTR strings, flash, camera switching, and the chrome options
- Four measurement harnesses, including a dense-sheet accuracy run

Run it with:

```sh
cd example
flutter run
```

## Recipes

See [RECIPES.md](RECIPES.md) for the continuous entry-scanning loop, custom overlays,
scan-window geometry, picking the right barcode when several are in frame, error codes, and the
platform differences between the Android and iOS engines.

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
| The wrong barcode is scanned from a sheet | Set `aimMode: FlutterBarcodeScanAimMode.crosshair`, shrink the window with `widthFraction`, or raise `scanConfirmationFrames`. See [RECIPES.md](RECIPES.md#picking-the-right-barcode). |
| iOS build integration issue | Use Flutter 3.44 or newer and keep Swift Package Manager enabled; CocoaPods remains supported through the podspec. |

## License

BSD 3. See [LICENSE](LICENSE).
