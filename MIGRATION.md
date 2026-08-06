# Migration Guide

Newest version first. Only versions that need a code or behaviour change appear here; releases
not listed are drop-in.

## Contents

- [0.3.0](#030)
- [0.2.1](#021)
- [0.2.0](#020)

## 0.3.0

### iOS decodes with Vision instead of AVFoundation metadata output

No code change is needed. Behaviour improves, and one error case changes.

`AVCaptureMetadataOutput` returns only a **single** 1D barcode per frame — Apple's
[Technical Note TN2325](https://developer.apple.com/library/archive/technotes/tn2325/_index.html)
describes it as "the center-most decodable barcode in the `rectOfInterest`", with a limit of four
for 2D codes. The scanner therefore never received a list of candidates to choose from on iOS, and
a page of barcodes could return a neighbouring code however carefully the user aimed. iOS now
decodes with `VNDetectBarcodesRequest`, which reports every barcode in the frame — the same model
Android has always had.

What this means for you:

- **Multiple codes in frame now behave the same on both platforms.** The code under the aim point
  is the one reported.
- **`UNSUPPORTED_FORMATS` is now almost unreachable.** It previously fired when the capture device
  offered none of the requested metadata types; it now fires only if every requested format is one
  this package cannot detect. Keep handling it — it is still a documented error code.
- **Detection is throttled to 15 passes per second** on iOS. Decoding now happens on the CPU and
  Neural Engine rather than inside the capture pipeline, and unthrottled scanning would cost
  battery on a workload that runs for hours.
- **UPC-A and EAN-13 are still indistinguishable on iOS** — Vision reports both as the EAN-13
  symbology, exactly as AVFoundation did, so the label is still derived from the decoded value.
  Request both if you scan retail codes.

There is no new dependency: Vision ships with iOS.

### The scan window is sized by width and aspect ratio

`widthFactor` and `heightFactor` are replaced by `widthFraction` plus `aspectRatio`. A fraction on
each axis made the window's shape depend on the shape of whatever it was drawn in: one
`0.8 × 0.4` config rendered as a 2.2:1 band inside a short embedded preview and as a 1:1 square
in the full-screen scanner. Sizing one axis and fixing the ratio makes the window the same shape
everywhere.

```dart
// Before
const FlutterBarcodeScannerScanWindow(
  widthFactor: 0.9,
  heightFactor: 0.35,
);

// After — 90% of the preview width, a shallow band
const FlutterBarcodeScannerScanWindow(
  widthFraction: 0.9,
  aspectRatio: 4,
);
```

**Read this even if you never set the window.** Before 0.3.0, equal factors silently collapsed the
window to a square at `min(width, height)`. The old `0.58 / 0.58` default was therefore a square
at 58% of the *preview height* on a portrait phone — not the wide band it read as. The rule is
gone, and the default is now `widthFraction: 0.8` at `aspectRatio: 3 / 2`. **The framed region
changes size and shape on upgrade whether or not you touched the config.**

Pass `rect` when the window has to sit somewhere other than the centre. It is a `Rect` in
normalized preview coordinates and overrides both sizing fields — it also brings back the
shape-follows-container behaviour, so prefer the sizing fields unless off-centre placement is the
point:

```dart
const FlutterBarcodeScannerScanWindow(
  rect: Rect.fromLTWH(0.05, 0.1, 0.9, 0.3),
);
```

`FlutterBarcodeScannerScanWindow.fromFactors` keeps old call sites compiling for one release, but
it is source-compatible only — it produces a `rect` window and does **not** reproduce the square
rule, because that rule needed a preview size the config never had:

```dart
// Compiles, but 0.8/0.8 is now a true rectangle rather than a square
// ignore: deprecated_member_use
final window = FlutterBarcodeScannerScanWindow.fromFactors(
  widthFactor: 0.8,
  heightFactor: 0.8,
);
```

`effectiveWidthFactor` and `effectiveHeightFactor` are gone. `resolve(Size)` maps the window onto
a concrete preview size and is the way to read the applied geometry back.

### Aiming is strict by default, and it changes which barcode you get

`FlutterBarcodeScanAimMode.crosshair` is the default: a barcode is reported only when its own
bounds reach a small region at the centre of the scan window. Previously any barcode overlapping
the window could be reported.

**This is the fix for wrong-barcode results, and it is deliberately strict.** Under the old rule
any barcode overlapping the window could win, and with several codes in frame "nearest the centre"
is often a neighbour — your aim lands between two codes. Requiring the barcode to cover the aim
point makes reporting an unaimed code impossible.

No code change is needed, but **expect to aim more deliberately**: put the crosshair on the code.
The built-in overlay draws it, on both platforms.

If your scanner only ever sees one barcode at a time — a ticket held up, a label on a parcel — the
old behaviour is faster and still safe:

```dart
const FlutterBarcodeScannerScanWindow(
  aimMode: FlutterBarcodeScanAimMode.window,
);
```

See [RECIPES.md](RECIPES.md#scanning-a-sheet-of-barcodes) for the iOS limitation behind this.

### Confirmation observations are on by default

Two additions change *which* barcode gets reported when more than one is in frame. Neither needs
a code change, but the second changes timing.

`scanConfirmationFrames` defaults to `2`: the same value must stay the best candidate for two
consecutive observations before it is reported. A camera decodes many times a second, so the
first code to satisfy the scan window used to win even when the phone was still sweeping towards
the one the user meant. Expect roughly one extra frame of latency per observation. To restore the
old behaviour:

```dart
final config = FlutterBarcodeScannerConfig(scanConfirmationFrames: 1);
```

Observations do **not** have to be strictly back to back: a frame that decodes nothing leaves the
run intact, and progress is discarded only after about half a second of silence. Under `window`
aiming the requirement doubles while more than one barcode overlaps the scan window; under
`crosshair` it does not, because a neighbour is already unreportable.

See [RECIPES.md](RECIPES.md#picking-the-right-barcode) for detail, including what an "observation"
means on each platform.

### `requestCameraPermission()` returns a status, not a bool

Camera permission has five states, and collapsing them into `true`/`false` made the denied case
a dead end — there was no way to tell "ask again" from "only Settings can fix this".

```dart
// Before
if (await FlutterBarcodeScanner.requestCameraPermission()) {
  startScanning();
}

// After
final status = await FlutterBarcodeScanner.requestCameraPermission();
if (status.isGranted) {
  startScanning();
} else if (status.requiresSettings) {
  await FlutterBarcodeScanner.openAppSettings();
}
```

`checkCameraPermission()` reports the status without prompting. See
[RECIPES.md](RECIPES.md#camera-permission) for the platform differences — iOS never reports
`denied`, and Android's `notDetermined` is inferred.

### `freezePreviewWhenPaused` is removed

Deprecated as a no-op in 0.2.1, now deleted along with its method-channel key. Delete the
argument; there is no replacement, because the preview already stays live while detection is
paused.

```dart
// Before
widgetConfig: const FlutterBarcodeScannerWidgetConfig(
  freezePreviewWhenPaused: true,
  pausedScanWindowBorderColor: Color(0xFFE53935),
),

// After
widgetConfig: const FlutterBarcodeScannerWidgetConfig(
  pausedScanWindowBorderColor: Color(0xFFE53935),
),
```

### Repeated scans of the same code are suppressed by default

`duplicateScanCooldown` defaults to 250 ms. A camera re-decodes the code in front of it many
times a second, so one physical barcode used to produce a burst of identical results. Only
repeats of the **same value** are filtered — a different code is still reported immediately.

If you were de-duplicating in your own `onScan`, that code is now redundant. If you genuinely
want every decode, opt out:

```dart
const FlutterBarcodeScannerWidgetConfig(
  duplicateScanCooldown: Duration.zero,
);
```

### Multiple codes in frame: the nearest one wins

When several barcodes are visible, the scanner used to take the first one the platform happened
to report whose centre fell inside the window — an order unrelated to what the user was aiming
at, so a dense sheet could silently return the neighbouring code. Candidates are now ranked by
distance from the scan-window centre, and a code whose bounds merely *intersect* the window is
eligible rather than requiring its centre inside.

No code change is needed. Expect a different — and more often correct — result when more than
one code is in frame.

### The camera no longer stops on `AppLifecycleState.inactive`

Teardown keys on `paused`, `hidden` and `detached` only. On iOS, `inactive` fires for
notification banners, Control Center and the app switcher, and each one cost a full camera stop
and rebind. If you relied on the camera releasing during a banner, stop it explicitly:

```dart
controller.stopCamera();
```

### The default scanner title changed

`FlutterBarcodeScannerStrings.title` now defaults to `'Scan Barcode'` instead of `'Scan Ticket'`.
The package decodes barcodes and has no idea what they represent, so the default no longer
assumes. If you never set `title`, the heading in the native full-screen scanner changes text.
Set it explicitly to keep the old wording:

```dart
strings: const FlutterBarcodeScannerStrings(title: 'Scan Ticket'),
```

### `FlutterBarcodeScannerConfig` is no longer `const`-constructible

The configuration now rejects `FlutterBarcodeScannerFormat.unknown` at construction rather than
part-way through a build, so the mistake surfaces on the line that made it instead of as a red
screen from inside the package. That check is an assert, and Dart does not permit a runtime
check like `Set.contains` in the initializer list of a `const` constructor — so the constructor
gave up `const`.

Only `FlutterBarcodeScannerConfig` is affected. `FlutterBarcodeScannerStrings`,
`FlutterBarcodeScannerScanWindow`, `FlutterBarcodeScannerUiConfig`,
`FlutterBarcodeScannerStatusBarStyle` and `FlutterBarcodeScannerWidgetConfig` all keep their
`const` constructors, so nested defaults are unchanged.

Drop `const` where you construct the config, and from any enclosing `const` expression:

```dart
// Before
const config = FlutterBarcodeScannerConfig(
  allowedFormats: FlutterBarcodeScannerFormats.common,
);

// After
final config = FlutterBarcodeScannerConfig(
  allowedFormats: FlutterBarcodeScannerFormats.common,
);
```

```dart
// Before
const FlutterBarcodeScannerView(
  config: FlutterBarcodeScannerConfig(),
);

// After
FlutterBarcodeScannerView(
  config: FlutterBarcodeScannerConfig(),
);
```

The compiler catches every occurrence, so there is nothing to find by hand.

### Configuration models now compare by value

`==` and `hashCode` are implemented on every configuration model. If you were comparing
configurations by identity — or working around the lack of equality by serializing them — that
code can be simplified, and equality-based checks that used to be always-false now behave as
written.

### `controller.state` is joined by a synchronous current value

Nothing is removed. The `state` stream still works exactly as before. Two additions make the
present state readable without waiting for the next change:

```dart
// Before — a widget built after the scanner started saw nothing until the next state change
StreamBuilder<FlutterBarcodeScannerViewState>(
  stream: controller.state,
  builder: (context, snapshot) => Text(snapshot.data?.name ?? 'unknown'),
);

// After
ValueListenableBuilder<FlutterBarcodeScannerViewState>(
  valueListenable: controller.stateListenable,
  builder: (context, state, _) => Text(state.name),
);
```

`controller.currentState` reads the same value synchronously anywhere.

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

A related change affects retail barcodes: iOS cannot distinguish UPC-A from EAN-13, so
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
