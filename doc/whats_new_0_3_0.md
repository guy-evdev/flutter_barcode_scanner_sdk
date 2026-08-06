# What's new in 0.3.0

The release that makes the scanner report **the barcode you aimed at**, on both platforms.

Upgrading needs source changes — see [MIGRATION.md](../MIGRATION.md#030) for before/after on each
one. This page covers what changed and why.

## iOS decodes with Vision

Scanning one code from a page where several are visible used to return a neighbouring code on
iOS, however carefully the user aimed. Measured on a printed 16-code sheet: Android was correct
87 times out of 87, iOS was not.

The cause is documented by Apple. `AVCaptureMetadataOutput` — the API this package used through
0.2.x — returns only a **single** 1D barcode per frame, which
[Technical Note TN2325](https://developer.apple.com/library/archive/technotes/tn2325/_index.html)
describes as "the center-most decodable barcode in the `rectOfInterest`" (four for 2D codes). The
scanner therefore never received a list of candidates to choose from on iOS, and the one code it
did receive was chosen against the whole camera frame rather than against the user's aim.

iOS now decodes with `VNDetectBarcodesRequest`, which reports every barcode in the frame — the
same model ML Kit has always given Android. There is no new dependency: Vision ships with iOS.

Two consequences worth knowing:

- **`UNSUPPORTED_FORMATS` is now almost unreachable.** It used to fire when the capture device
  offered none of the requested metadata types. It now fires only if every requested format is one
  this package cannot detect. Keep handling it; it is still a documented error code.
- **Detection is throttled to 15 passes per second** on iOS. Decoding happens on the CPU and
  Neural Engine rather than inside the capture pipeline, and unthrottled scanning would cost
  battery on a workload that runs for hours.

UPC-A and EAN-13 remain indistinguishable on iOS — Vision reports both as the EAN-13 symbology,
exactly as AVFoundation did — so the label is still derived from the decoded value. Request both
if you scan retail codes.

## Aiming is a point, not an area

```dart
const FlutterBarcodeScannerScanWindow(
  aimMode: FlutterBarcodeScanAimMode.window, // looser than the default
);
```

`FlutterBarcodeScanAimMode.crosshair` is the default: a barcode is reported only when its own
bounds cover a small region at the centre of the scan window. The built-in overlay draws a
crosshair there, on both platforms.

Under the old rule any barcode overlapping the window could win, and with several codes in frame
"nearest the centre" is often a neighbour — the aim point lands in the gap between two codes.
Requiring the barcode to cover the aim point makes reporting an unaimed code impossible.

The target is a small **region** rather than a single pixel. Detectors report partial and
wobbling bounds, so a code sitting visibly under the crosshair whose reported bounds happened to
miss the exact centre point would otherwise be unscannable however carefully the user aimed —
which is a real failure that showed up in device testing. The region is still far smaller than the
gap between stacked codes.

Choose `window` when a single barcode is ever in frame — a ticket held up, a label on a parcel. It
acquires faster and forgives sloppy aim.

## The scan window keeps its shape

```dart
const FlutterBarcodeScannerScanWindow(
  widthFraction: 0.9,
  aspectRatio: 4, // a wide, shallow band for long linear codes
);
```

The window is a share of the preview **width** at a fixed aspect ratio, defaulting to `0.8` at
`3:2`. A fraction on each axis made the window's shape depend on the shape of whatever it was
drawn in: one `0.8 × 0.4` config rendered as a 2.2:1 band inside a short embedded preview and as a
1:1 square in the full-screen scanner. The same configuration, two different windows.

Pass `rect` when the window has to sit somewhere other than the centre. It overrides both sizing
fields and brings back the shape-follows-container behaviour, so reach for it only when centring
is genuinely wrong.

**The framed region changes size and shape on upgrade whether or not you touched the config.**

## The scan → validate → accept/reject loop

```dart
FlutterBarcodeScannerView(
  config: FlutterBarcodeScannerConfig(),
  onScanValidate: (result) async {
    final accepted = await api.validate(result.rawValue);
    return accepted
        ? const ScanDecision.accept(message: 'Welcome')
        : const ScanDecision.reject(message: 'Already used');
  },
);
```

Return a decision and the scanner runs the loop: it holds detection for the whole check, shows the
outcome, then resumes. No manual pause/resume, and no guessing at a delay long enough for the
server to answer.

A validator that throws is treated as a rejection and reported — the scanner carries on rather
than wedging. Accepted scans can play a haptic and a sound through
`FlutterBarcodeScannerWidgetConfig`, and `controller.feedbackListenable` drives a custom overlay
if the built-in banner is not what you want.

## Repeated and hasty scans are filtered

- **`duplicateScanCooldown`** defaults to 250 ms. A camera re-decodes the code in front of it many
  times a second, so one physical barcode used to produce a burst of identical results. Only
  repeats of the *same* value are filtered.
- **`scanConfirmationFrames`** defaults to 2: the same value must stay the best candidate for two
  observations before it is reported, which discards a code caught while sweeping towards the one
  the user meant. A frame that decodes nothing does not break the run — progress is discarded only
  after about half a second of silence. Under `window` aiming the requirement doubles while more
  than one barcode shares the scan window.

## A real camera-permission contract

```dart
final status = await FlutterBarcodeScanner.requestCameraPermission();
if (status.isGranted) {
  startScanning();
} else if (status.requiresSettings) {
  await FlutterBarcodeScanner.openAppSettings();
}
```

`requestCameraPermission()` returns a `FlutterBarcodePermissionStatus` rather than a bool.
Collapsing five states into `true`/`false` made the denied case a dead end — there was no way to
tell "ask again" from "only Settings can fix this". `checkCameraPermission()` reports the status
without prompting, and `permissionBuilder` replaces the built-in screen.

The states differ by platform, and the differences are load-bearing: iOS never reports `denied`
(its prompt appears once, so a refusal is already permanent), and Android's `notDetermined` is
inferred rather than read from the system. See
[RECIPES.md](../RECIPES.md#camera-permission).

## Smaller things

- **`controller.stateListenable` and `controller.currentState`** read the scanner's state
  synchronously. The `state` stream still works exactly as before.
- **`keepScreenOn`** keeps the display awake while the scanner runs — worth setting for sustained
  entry scanning.
- **The camera no longer stops on `AppLifecycleState.inactive`.** On iOS that fires for
  notification banners, Control Center and the app switcher, and each one cost a full camera stop
  and rebind.
- **Configuration models compare by value**, so `==` and `hashCode` behave as written.
- **`freezePreviewWhenPaused` is removed.** Deprecated as a no-op in 0.2.1; it never worked on iOS
  at all, and on Android it allocated a full-resolution bitmap on every scan.
- **The default scanner title is `'Scan Barcode'`**, not `'Scan Ticket'`. The package decodes
  barcodes and has no idea what they represent.

## Known limitation

Battery and thermal cost of the iOS Vision path over a multi-hour scanning session has not been
measured. Detection is throttled, but if you run continuous scanning for a full shift, watch for
it and please report what you see.
