# Migration Guide

Newest version first. Only versions that need a code or behaviour change appear here; releases
not listed are drop-in.

## Contents

- [0.2.1](#021)
- [0.2.0](#020)

## 0.2.1

Not a breaking release — nothing fails to compile. One option stopped doing anything, and the
behaviour it used to produce on Android is gone, so it is listed here rather than left for you
to discover at runtime.

### `freezePreviewWhenPaused` is a deprecated no-op

The preview now keeps showing live video while detection is paused, on both platforms. The
option never worked on iOS at all — the frozen frame was captured with `CALayer.render(in:)`,
which cannot draw `AVCaptureVideoPreviewLayer` content, so it produced a blank overlay. On
Android it allocated a full-resolution bitmap on every scan, which is untenable for sustained
scanning.

Remove the argument. The field is deleted in 0.3.0.

```dart
// Before
FlutterBarcodeScannerView(
  config: const FlutterBarcodeScannerConfig(),
  widgetConfig: const FlutterBarcodeScannerWidgetConfig(
    freezePreviewWhenPaused: true,
    pausedScanWindowBorderColor: Color(0xFFE53935),
  ),
);

// After
FlutterBarcodeScannerView(
  config: const FlutterBarcodeScannerConfig(),
  widgetConfig: const FlutterBarcodeScannerWidgetConfig(
    pausedScanWindowBorderColor: Color(0xFFE53935),
  ),
);
```

If you relied on the frozen frame to show that a scan landed, `pausedScanWindowBorderColor`
already recolours the scan-window border while detection is paused, identically on both
platforms.

### Cancelled and error results no longer report `qrCode`

Cancelling the full-screen scanner, or a scanner failure, used to return a result whose
`format` was `FlutterBarcodeScannerFormat.qrCode` — indistinguishable from a real QR scan if
you read `format` before checking `type`. Both now report `FlutterBarcodeScannerFormat.unknown`.

Check the result kind first, which was always the correct way round:

```dart
// Before — misleading for cancelled and error results
if (result.format == FlutterBarcodeScannerFormat.qrCode) { ... }

// After
if (result.isBarcode) {
  // result.format is now only meaningful here
}
```

### iOS format filtering is now honoured

If none of the formats you requested are available on the device, iOS previously fell back to
**every** metadata type the session offered — including non-barcode types such as faces on
modern iOS. It now reports `UNSUPPORTED_FORMATS` instead of scanning something you did not ask
for. See [RECIPES.md](RECIPES.md#handling-errors).

A related change affects retail barcodes: AVFoundation cannot distinguish UPC-A from EAN-13, so
results are now filtered against the formats you requested. **Requesting only one of the two on
iOS will now skip the other**, where it previously returned it under the wrong label. Request
both if you scan retail codes — see
[RECIPES.md](RECIPES.md#platform-differences).

## 0.2.0

### `FlutterBarcodeScannerFormat.unknown` was added

Native formats this package version does not recognize are preserved as `unknown` with the
original identifier in `nativeFormat`, rather than being reported as some other format. Adding
an enum value breaks exhaustive `switch` statements.

```dart
// Before
switch (result.format) {
  case FlutterBarcodeScannerFormat.qrCode:
    return 'QR';
  case FlutterBarcodeScannerFormat.code128:
    return 'Code 128';
  // ...every other format
}

// After — handle unknown, and use nativeFormat when you need the raw identifier
switch (result.format) {
  case FlutterBarcodeScannerFormat.unknown:
    return result.nativeFormat ?? 'Unknown';
  case FlutterBarcodeScannerFormat.qrCode:
    return 'QR';
  case FlutterBarcodeScannerFormat.code128:
    return 'Code 128';
  // ...every other format
}
```

`unknown` cannot be requested for detection — there is no native format to ask for. Including
it in `allowedFormats` throws an `ArgumentError` when the config is serialized for the platform
channel, which happens while the scanner is being built rather than when you construct the
config.
