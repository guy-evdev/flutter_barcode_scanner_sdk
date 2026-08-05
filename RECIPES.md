# Recipes

Advanced usage, customization, and platform-specific behaviour. The [README](README.md) covers
the two common flows; everything here is the long tail.

## Contents

- [Continuous entry scanning](#continuous-entry-scanning)
  - [Duplicate filtering](#duplicate-filtering)
  - [Haptics and sound](#haptics-and-sound)
- [Reacting to scanner state](#reacting-to-scanner-state)
- [Handling errors](#handling-errors)
- [Camera permission](#camera-permission)
- [Custom overlays](#custom-overlays)
- [Scan-window geometry](#scan-window-geometry)
- [Choosing formats](#choosing-formats)
- [Platform differences](#platform-differences)
- [Measuring sustained scanning](#measuring-sustained-scanning)

## Continuous entry scanning

Scanning a queue of codes is a loop: detect, validate against your backend, resume.
`onScanValidate` runs that loop for you — return a decision and the scanner handles the
pausing, the feedback and the resume:

```dart
FlutterBarcodeScannerView(
  config: FlutterBarcodeScannerConfig(
    allowedFormats: FlutterBarcodeScannerFormats.common,
  ),
  widgetConfig: const FlutterBarcodeScannerWidgetConfig(
    validationFeedbackDuration: Duration(milliseconds: 900),
  ),
  onScanValidate: (result) async {
    final check = await api.validate(result.rawValue);
    return check.isValid
        ? const ScanDecision.accept(message: 'Admitted')
        : const ScanDecision.reject(message: 'Already used');
  },
);
```

What it guarantees, which is the reason to prefer it over hand-rolling:

- **Detection is held for the whole decision**, whatever `autoPauseOnScan` is set to. A slow
  backend cannot produce a second read of the same code.
- **Results arriving mid-decision, or while feedback is showing, are not validated again.**
  They still reach `onScan`.
- **A validator that throws is treated as a rejection** and reported through `FlutterError`,
  so a failing backend leaves the scanner usable instead of stuck.
- **A decision that resolves after the widget is gone is discarded**, rather than calling back
  into a disposed controller.

Do not call `resumeDetection()` yourself while using `onScanValidate` — the loop owns it.
Set `validationFeedbackDuration` to `Duration.zero` to resume the instant the decision arrives,
showing no feedback at all.

To render your own accepted/rejected treatment, supply an `overlayBuilder` and read
`controller.feedbackListenable`; the built-in banner is skipped whenever a custom overlay is
supplied.

### Duplicate filtering

A camera re-decodes the code in front of it many times a second, so one physical barcode
produces a burst of identical results. `duplicateScanCooldown` suppresses repeats of the **same
value** for 250 ms by default.

It is deliberately value-based rather than a plain time throttle: moving to a *different* code
is reported immediately, which is what makes scanning down a dense sheet work. Cancellations and
errors are never filtered.

```dart
const FlutterBarcodeScannerWidgetConfig(
  duplicateScanCooldown: Duration(milliseconds: 400), // more forgiving
  // duplicateScanCooldown: Duration.zero,            // report every decode
);
```

The filter runs before `onScan` and before `onScanValidate`, so a suppressed repeat reaches
neither. That is separate from the validate loop's own re-entry guard: the cooldown stops the
same code being reported twice, while the loop stops *any* code being validated while a decision
is pending.

### Haptics and sound

An accepted decision fires a short haptic by default, and can also play a sound:

```dart
const FlutterBarcodeScannerWidgetConfig(
  hapticFeedbackOnAccept: true,  // default
  soundOnAccept: true,           // off by default
);
```

Both fire only for accepted `onScanValidate` decisions — not for rejections, and not for plain
`onScan` results.

Two accessibility notes. The haptic is suppressed when the platform reports **Reduce Motion**.
The sound is the platform's own short system sound rather than a bundled asset, which is what
makes the **iOS silent switch** mute it — Flutter cannot query that switch, so honouring it
depends on using a system sound.

### Doing it by hand

Without `onScanValidate`, you own the pause/resume cycle. With `autoPauseOnScan: true` (the
default) the native scanner pauses itself the moment it decodes, so the loop never double-scans
while you are awaiting a server round trip.

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
    final accepted = await validateCode(result.rawValue);
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

## Camera permission

`checkCameraPermission()` never prompts, so use it to decide what to show; `requestCameraPermission()`
prompts only when the system still would.

```dart
final status = await FlutterBarcodeScanner.checkCameraPermission();
if (status.canRequest) {
  await FlutterBarcodeScanner.requestCameraPermission();
} else if (status.requiresSettings) {
  await FlutterBarcodeScanner.openAppSettings();
}
```

With `autoRequestCameraPermission: true` (the default) the embedded view does this for you and
renders a denied state offering only the action that can help — a retry where the system will
still prompt, Settings where it will not, and neither when a device policy forbids the camera.
It also re-checks when the app returns to the foreground, so granting access in Settings brings
the scanner back without a restart.

Replace that UI with `permissionBuilder`:

```dart
FlutterBarcodeScannerView(
  config: FlutterBarcodeScannerConfig(),
  permissionBuilder: (context, status, retry) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Camera unavailable: ${status.name}'),
        if (status.canRequest)
          TextButton(onPressed: retry, child: const Text('Try again')),
        if (status.requiresSettings)
          TextButton(
            onPressed: FlutterBarcodeScanner.openAppSettings,
            child: const Text('Settings'),
          ),
      ],
    ),
  ),
);
```

The status values differ by platform in two ways that matter — iOS never reports `denied`, and
Android's `notDetermined` is inferred rather than read from the system. See
[Platform differences](#platform-differences).

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

`scanWindow.rect` is a `Rect` in normalized preview coordinates — each side a fraction of the
preview, not logical pixels, because the preview size is not known when the config is built.

```dart
const FlutterBarcodeScannerScanWindow(
  rect: Rect.fromLTWH(0.05, 0.35, 0.9, 0.3), // wide band for long linear codes
);
```

The default is `Rect.fromLTWH(0.1, 0.3, 0.8, 0.4)` — a centered band, wider than tall, because
the formats that most need a window are the long linear ones.

Read the applied geometry back with `effectiveRect` (clamped into the preview, guaranteed to
have area) or `resolve(size)`, which maps it onto a concrete preview size and returns `null`
when the window is disabled.

**The old square rule is gone.** Before 0.3.0, equal width and height factors silently collapsed
the window to a square at `min(width, height)`, so the `0.58 / 0.58` default was a narrow box on
a portrait phone rather than the wide band it read as. `FlutterBarcodeScannerScanWindow.fromFactors`
still exists for one release so old code compiles, but it no longer applies that rule — equal
factors now give a true rectangle.

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
| Permission `denied` | Reported after a refusal that can be re-prompted | Never reported — a refusal is already final |
| Permission `restricted` | Never reported | Reported when a device policy forbids the camera |
| Permission `notDetermined` | Inferred from a recorded "have we asked" flag | Read directly from `AVAuthorizationStatus` |

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
