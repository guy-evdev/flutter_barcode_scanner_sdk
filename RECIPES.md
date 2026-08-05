# Recipes

Advanced usage, customization, and platform-specific behaviour. The [README](README.md) covers
the two common flows; everything here is the long tail.

## Contents

- [Continuous entry scanning](#continuous-entry-scanning)
- [Reacting to scanner state](#reacting-to-scanner-state)
- [Handling errors](#handling-errors)
- [Custom overlays](#custom-overlays)
- [Scan-window geometry](#scan-window-geometry)
- [Choosing formats](#choosing-formats)
- [Platform differences](#platform-differences)
- [Measuring sustained scanning](#measuring-sustained-scanning)

## Continuous entry scanning

Scanning a queue of tickets is a loop: detect, validate against your backend, resume. With
`autoPauseOnScan: true` (the default) the native scanner pauses itself the moment it decodes,
so the loop never double-scans while you are awaiting a server round trip.

```dart
final controller = FlutterBarcodeScannerController();

FlutterBarcodeScannerView(
  controller: controller,
  config: FlutterBarcodeScannerConfig(
    allowedFormats: FlutterBarcodeScannerFormats.common,
  ),
  autoPauseOnScan: true,
  onScan: (result) async {
    if (!result.isBarcode) {
      return;
    }
    final accepted = await validateTicket(result.rawValue);
    showBanner(accepted ? 'Admitted' : 'Rejected');
    await controller.resumeDetection();
  },
);
```

The camera keeps running while detection is paused — only decoding stops. That is deliberate:
rebinding the camera per scan costs hundreds of milliseconds, which is dead time across a shift.

To signal the paused state, set `pausedScanWindowBorderColor`; the scan-window border switches
to it automatically while detection is paused.

## Reacting to scanner state

`controller.state` is a broadcast stream of `FlutterBarcodeScannerViewState`:

| State | Meaning |
| --- | --- |
| `idle` | Attached but not started, after `autoStart: false`. |
| `initializing` | The native camera pipeline is being brought up. |
| `running` | Preview and detection are both live. |
| `detectionPaused` | Camera is live, decoding is stopped. |
| `cameraStopped` | The camera was stopped. |
| `error` | The native scanner reported a failure. |
| `disposed` | The native view was released. |

The stream is broadcast and carries no current value, so a widget that subscribes late sees
nothing until the next change. Cache the last value yourself if you need it during `build`:

```dart
FlutterBarcodeScannerViewState? lastState;
controller.state.listen((state) => setState(() => lastState = state));
```

## Handling errors

`controller.errors` emits `PlatformException`s. Codes you can receive:

| Code | Platform | Meaning |
| --- | --- | --- |
| `PERMISSION_DENIED` | both | Camera permission is not granted. |
| `CAMERA_UNAVAILABLE` | both | The camera could not be opened or bound. |
| `TORCH_UNAVAILABLE` | both | The torch could not be switched. |
| `NO_LIFECYCLE_OWNER` | Android | The host activity is not a `LifecycleOwner`. |
| `PREVIEW_UNAVAILABLE` | Android | The preview was never given a size by its parent. |
| `UNSUPPORTED_FORMATS` | iOS | None of the requested formats are available on this device. |
| `SESSION_INTERRUPTED` | iOS | The system took the camera — a call, another app, screen sharing. |
| `SESSION_RUNTIME_ERROR` | iOS | A capture-session runtime error the scanner could not recover from. |
| `CONTROLLER_UNAVAILABLE` | both | A widget action ran without an attached controller. |

`PREVIEW_UNAVAILABLE` almost always means the widget was laid out with zero height — an
unbounded `Column` child, or a collapsed parent. The Android scanner retries for about two
seconds, then reports this and picks the start back up if the parent later gains a size.

`SESSION_INTERRUPTED` is informational: the scanner resumes by itself when the interruption
ends and emits `running` again. Treat it as a reason to show a "camera unavailable" hint, not
as a reason to tear the scanner down.

## Custom overlays

Three builders replace the default Flutter-side chrome. The native preview is untouched.

```dart
FlutterBarcodeScannerView(
  config: FlutterBarcodeScannerConfig(),
  overlayBuilder: (context, scanWindow, controller) {
    // scanWindow is in widget coordinates, or null when the window is disabled.
    return Stack(
      children: [
        if (scanWindow != null)
          Positioned.fromRect(
            rect: scanWindow,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.amber, width: 3),
              ),
            ),
          ),
      ],
    );
  },
  loadingBuilder: (context, state, controller) =>
      const Center(child: CircularProgressIndicator()),
  errorBuilder: (context, error, controller) => Center(
    child: TextButton(
      onPressed: controller.startCamera,
      child: Text('Retry — ${error.code}'),
    ),
  ),
);
```

Supplying `overlayBuilder` replaces the default overlay entirely, including the pause/resume
button that `showPauseResumeButton` adds. Drive `controller.pauseDetection()` and
`controller.resumeDetection()` from your own controls instead.

## Scan-window geometry

`scanWindow.widthFactor` and `heightFactor` are fractions of the preview, clamped to
`0.2...0.95` and `0.2...0.9`. Read the applied values back through `effectiveWidthFactor` and
`effectiveHeightFactor`.

One rule is easy to trip over: **when the two factors are equal, the window is forced square at
`min(width, height)`**, on both platforms and in the Flutter overlay. So the `0.58 / 0.58`
default is a square at 58% of the *preview height* on a portrait phone, not a rectangle 58%
wide. For a long Code 128 ticket, ask for an explicitly non-square window:

```dart
const FlutterBarcodeScannerScanWindow(
  widthFactor: 0.9,
  heightFactor: 0.35,
);
```

Detection is not clipped to the window on either platform. The full frame is decoded and the
result is then rejected unless the barcode's centre falls inside the window, because
pre-clipping made long 1D codes fail to decode at the edges.

To scan the whole preview, set `enabled: false`.

## Choosing formats

An empty `allowedFormats` means every supported format. Narrowing the set is worth doing when
you know what you are scanning — it reduces false positives on dense sheets.

```dart
FlutterBarcodeScannerConfig(
  allowedFormats: {
    FlutterBarcodeScannerFormat.code128,
    FlutterBarcodeScannerFormat.qrCode,
  },
);
```

`FlutterBarcodeScannerFormat.unknown` cannot be requested — it exists so a native format this
package version does not recognize survives to your code with `nativeFormat` intact instead of
being reported as some other format. Passing it throws.

## Platform differences

These are real asymmetries, not implementation details you can ignore.

| Area | Android | iOS |
| --- | --- | --- |
| Engine | CameraX + ML Kit | AVFoundation metadata output |
| UPC-A vs EAN-13 | ML Kit filters them separately | AVFoundation reports both as `.ean13`; the plugin post-filters on the decoded value |
| Unsupported format set | ML Kit accepts every supported format | Reports `UNSUPPORTED_FORMATS` when the device offers none of them |
| Session interruption | Not observable | `SESSION_INTERRUPTED` / auto-recovery, see [Handling errors](#handling-errors) |
| Zero-size preview | Retries, then `PREVIEW_UNAVAILABLE` | No equivalent report |

**UPC-A and EAN-13 need care on iOS.** AVFoundation cannot distinguish them, so the plugin
decides from the decoded value: a 13-digit value with a leading zero is reported as `UPC_A`,
anything else as `EAN_13`. Results are then filtered against what you asked for. The practical
consequence is that **requesting one without the other on iOS will skip codes** — if you scan
retail barcodes, request both:

```dart
FlutterBarcodeScannerConfig(
  allowedFormats: {
    FlutterBarcodeScannerFormat.upcA,
    FlutterBarcodeScannerFormat.ean13,
  },
);
```

Every built-in preset that contains one contains the other, so this only bites hand-built sets.

## Measuring sustained scanning

The example app ships a stress harness — the speedometer icon in its app bar. It runs the
continuous loop above against a single printed barcode and reports scans completed, peak and
steady process memory, dropped frames split into build and raster overruns, decode-latency
percentiles, camera restarts, and error counts, then copies a plain-text report.

Run it in profile mode on a physical device:

```sh
cd example
flutter run --profile
```

Debug builds are labelled `NOT GATE-VALID` in the report: debug frame and latency numbers are
dominated by the interpreter and mean nothing.
