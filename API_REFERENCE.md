# API Reference

This reference summarizes the public Dart API for `flutter_barcode_scanner_sdk`.

## Contents

- [Scanner Entry Points](#scanner-entry-points)
- [Scanner Configuration](#scanner-configuration)
- [Embedded Widget Configuration](#embedded-widget-configuration)
- [Controller](#controller)
- [Results](#results)
- [Formats](#formats)

## Scanner Entry Points

| API | Returns | Description |
| --- | --- | --- |
| `FlutterBarcodeScanner.requestCameraPermission()` | `Future<bool>` | Requests camera access and returns whether access is available. |
| `FlutterBarcodeScanner.scan(config)` | `Future<FlutterBarcodeScanResult?>` | Opens the full-screen native scanner and returns one result. |
| `FlutterBarcodeScannerView(...)` | `Widget` | Embeds the native scanner inside a Flutter layout. |

## Scanner Configuration

### `FlutterBarcodeScannerConfig`

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `allowedFormats` | `Set<FlutterBarcodeScannerFormat>` | `{}` | Formats to detect. Empty means all supported formats. |
| `strings` | `FlutterBarcodeScannerStrings` | `FlutterBarcodeScannerStrings()` | Text used by scanner UI. |
| `scanWindow` | `FlutterBarcodeScannerScanWindow` | `FlutterBarcodeScannerScanWindow()` | Region-of-interest and overlay shape. |
| `uiConfig` | `FlutterBarcodeScannerUiConfig` | `FlutterBarcodeScannerUiConfig()` | Native/default control visibility and initial camera settings. |
| `statusBarStyle` | `FlutterBarcodeScannerStatusBarStyle` | `FlutterBarcodeScannerStatusBarStyle()` | Full-screen scanner status bar style. |
| `textDirection` | `TextDirection?` | `null` | Forced scanner UI direction. `null` uses ambient/platform direction. |
| `appBarTransparent` | `bool` | `false` | Makes the full-screen scanner app bar transparent. |
| `appBarBackgroundColor` | `Color?` | `null` | Full-screen scanner app bar background. |
| `appBarForegroundColor` | `Color?` | `null` | Full-screen scanner app bar foreground. |
| `overlayColor` | `Color` | `Color(0x99000000)` | Mask color outside the scan window. |

Requesting `FlutterBarcodeScannerFormat.unknown` in `allowedFormats` fails an assert at
construction — it is the label reported for a symbology the package does not recognise, never a
format the scanner can be asked to detect.

Because that assert needs a runtime check, **this class has no `const` constructor**; the four
nested configuration models below do, so `const FlutterBarcodeScannerStrings(...)` and friends
still work as defaults.

### Equality

Every configuration model implements `==` and `hashCode` by value, so two configurations built
from the same values compare equal and can be used as map keys or compared in `didUpdateWidget`.
`allowedFormats` compares as an unordered set.

Scan windows compare the values **as written**, not the clamped `effective*` values: two windows
whose out-of-range factors happen to clamp to the same result are not equal.

### `FlutterBarcodeScannerStrings`

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `title` | `String` | `Scan Ticket` | Full-screen scanner title. |
| `close` | `String` | `Close` | Close button label. |
| `flashOn` | `String` | `Flash on` | Enable-flash label. |
| `flashOff` | `String` | `Flash off` | Disable-flash label. |
| `switchCamera` | `String` | `Switch camera` | Camera-switch label. |
| `cameraPermissionRequired` | `String` | `Camera permission is required` | Permission-denied message. |
| `cameraUnavailable` | `String` | `Camera unavailable` | Camera-open failure message. |

### `FlutterBarcodeScannerScanWindow`

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | `bool` | `true` | Limits detection to a centered scan window. `false` scans the whole preview. |
| `widthFactor` | `double` | `0.58` | Scan-window width as a fraction of preview width. |
| `heightFactor` | `double` | `0.58` | Scan-window height as a fraction of preview height. |
| `cornerRadius` | `double` | `18` | Scan-window overlay corner radius. |

Width and height factors are normalized to the cross-platform supported ranges
(`0.2...0.95` and `0.2...0.9` respectively). Non-finite values use defaults,
and negative corner radii become zero. The effective values are available from
`effectiveWidthFactor`, `effectiveHeightFactor`, and `effectiveCornerRadius`.

### `FlutterBarcodeScannerUiConfig`

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `showFlashButton` | `bool` | `true` | Shows the flash control when supported. |
| `showCameraSwitchButton` | `bool` | `true` | Shows the camera switch control when supported. |
| `initialCameraLens` | `BarcodeCameraLens` | `BarcodeCameraLens.back` | Initial camera lens. |
| `initialTorchEnabled` | `bool` | `false` | Attempts to start with torch enabled. |

### `FlutterBarcodeScannerStatusBarStyle`

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `isTransparent` | `bool` | `false` | Makes the full-screen scanner status bar transparent. |
| `backgroundColor` | `Color?` | `null` | Status bar fill color when not transparent. |
| `iconBrightness` | `FlutterBarcodeScannerStatusBarIconBrightness` | `light` | Status bar icon brightness. |

## Embedded Widget Configuration

### `FlutterBarcodeScannerView`

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `config` | `FlutterBarcodeScannerConfig` | required | Shared scanner configuration. |
| `widgetConfig` | `FlutterBarcodeScannerWidgetConfig` | `FlutterBarcodeScannerWidgetConfig()` | Flutter-side embedded scanner behavior. |
| `controller` | `FlutterBarcodeScannerController?` | `null` | Optional external controller. |
| `onScan` | `ValueChanged<FlutterBarcodeScanResult>?` | `null` | Receives embedded scan results. |
| `autoStart` | `bool` | `true` | Starts the camera automatically after platform-view creation. |
| `autoPauseOnScan` | `bool` | `true` | Pauses detection automatically after each result. |
| `overlayBuilder` | `FlutterBarcodeScannerOverlayBuilder?` | `null` | Replaces the default overlay controls. |
| `loadingBuilder` | `FlutterBarcodeScannerStateBuilder?` | `null` | Replaces the default loading overlay. |
| `errorBuilder` | `FlutterBarcodeScannerErrorBuilder?` | `null` | Replaces the default error overlay. |

### `FlutterBarcodeScannerWidgetConfig`

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `autoRequestCameraPermission` | `bool` | `true` | Requests camera permission before creating the platform view. |
| `freezePreviewWhenPaused` | `bool` | `false` | **Deprecated, no-op on both platforms.** The preview stays live while detection is paused; use `pausedScanWindowBorderColor` to signal the paused state. Removed in 0.3.0. |
| `showPauseResumeButton` | `bool` | `false` | Adds a default Flutter pause/resume overlay button. |
| `scanWindowBorderColor` | `Color` | `Colors.white` | Scan-window border while detection runs. |
| `pausedScanWindowBorderColor` | `Color` | `Color(0xFFE53935)` | Scan-window border while detection is paused. |
| `pauseTooltip` | `String` | `Pause scanner` | Pause button tooltip. |
| `resumeTooltip` | `String` | `Resume scanner` | Resume button tooltip. |

## Controller

### Streams and State

| API | Type | Description |
| --- | --- | --- |
| `currentState` | `FlutterBarcodeScannerViewState` | The state right now, readable synchronously at any time. Starts at `idle`; keeps its last value after `dispose()`. |
| `stateListenable` | `ValueListenable<FlutterBarcodeScannerViewState>` | The same value as a listenable, for `ValueListenableBuilder`. Notifies only when the state actually changes. |
| `results` | `Stream<FlutterBarcodeScanResult>` | Embedded scan results. |
| `state` | `Stream<FlutterBarcodeScannerViewState>` | Native scanner lifecycle states. Delivers every emission, including a repeat of the current state. |
| `errors` | `Stream<PlatformException>` | Native scanner errors. |
| `isAttached` | `bool` | Whether the controller is attached to a platform view. |
| `viewId` | `int?` | Current platform view id. |

Reach for `currentState` or `stateListenable` first. `state` is a broadcast stream, so it
delivers only what is emitted *after* you subscribe — a widget built partway through the
scanner's life sees nothing on it until the next change, while `currentState` is correct
immediately. The stream is retained for code already built around it.

```dart
ValueListenableBuilder<FlutterBarcodeScannerViewState>(
  valueListenable: controller.stateListenable,
  builder: (context, state, _) => Text(state.name),
)
```

### Methods

| Method | Description |
| --- | --- |
| `startCamera()` | Starts the native camera and detection. |
| `stopCamera()` | Stops the native camera and detection. |
| `pauseDetection()` | Pauses detection while keeping the view attached. |
| `resumeDetection()` | Resumes detection after pause. |
| `toggleFlash([enabled])` | Toggles or explicitly sets torch state; returns resulting state when available. |
| `switchCamera([lens])` | Switches to the requested lens or toggles when omitted. |
| `updateConfig(config, autoPauseOnScan, widgetConfig)` | Applies updated native and widget configuration. |
| `dispose()` | Releases native resources and closes streams. |

## Results

### `FlutterBarcodeScanResult`

| Field or Getter | Type | Description |
| --- | --- | --- |
| `type` | `FlutterBarcodeScannerResultType` | Result kind: barcode, cancelled, or error. |
| `rawValue` | `String` | Decoded barcode value, empty for cancelled/error results. |
| `format` | `FlutterBarcodeScannerFormat` | Detected barcode format. |
| `nativeFormat` | `String?` | Original native format identifier, including identifiers not recognized by this package version. |
| `errorCode` | `String?` | Optional native error code. |
| `errorMessage` | `String?` | Optional native error message. |
| `isCancelled` | `bool` | Whether this is a cancellation result. |
| `isBarcode` | `bool` | Whether this contains a decoded barcode. |
| `isError` | `bool` | Whether this is an error result. |
| `hasErrorDetails` | `bool` | Whether error code or message is present. |
| `valueOrNull` | `String?` | Decoded value only for barcode results. |

## Formats

### Format Presets

| Preset | Description |
| --- | --- |
| `FlutterBarcodeScannerFormats.all` | Every supported format. |
| `FlutterBarcodeScannerFormats.common` | QR Code, Code 128, EAN-13, EAN-8, UPC-A, and UPC-E. |
| `FlutterBarcodeScannerFormats.oneDimensional` | Code 128, Code 39, Code 93, EAN, UPC, and ITF. |
| `FlutterBarcodeScannerFormats.twoDimensional` | QR Code, PDF417, Data Matrix, and Aztec. |
| `FlutterBarcodeScannerFormats.qrOnly` | QR Code only. |

### Supported Formats

| Enum | Native value | Description |
| --- | --- | --- |
| `unknown` | `UNKNOWN` | Unknown or future native barcode format. Not included in format presets. |
| `qrCode` | `QR_CODE` | QR Code. |
| `code128` | `CODE_128` | Code 128. |
| `code39` | `CODE_39` | Code 39. |
| `code93` | `CODE_93` | Code 93. |
| `ean13` | `EAN_13` | EAN-13. |
| `ean8` | `EAN_8` | EAN-8. |
| `upcA` | `UPC_A` | UPC-A. |
| `upcE` | `UPC_E` | UPC-E. |
| `itf` | `ITF` | Interleaved 2 of 5. |
| `pdf417` | `PDF_417` | PDF417. |
| `dataMatrix` | `DATA_MATRIX` | Data Matrix. |
| `aztec` | `AZTEC` | Aztec. |
