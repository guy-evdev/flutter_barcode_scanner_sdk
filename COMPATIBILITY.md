# Compatibility Policy

`flutter_barcode_scanner_sdk` follows the compatibility policy below for the
`0.x` release line.

## Supported Toolchains

| Component | Supported baseline |
| --- | --- |
| Flutter | 3.44.0 or newer stable 3.44.x |
| Dart | 3.12.0 or newer compatible 3.x |
| Android | API 24 or newer; compile/target SDK 36 |
| Java | 17 |
| iOS | 15.0 or newer |
| Xcode | The current Xcode supported by Flutter 3.44 |
| iOS dependencies | Swift Package Manager primary; CocoaPods compatibility |

CI analyzes and tests Dart code, runs Android plugin unit tests, builds the
Android example, runs iOS native tests, and builds the iOS example through both
Swift Package Manager and CocoaPods.

## Dependency Updates

- Patch updates for CameraX, ML Kit, AndroidX, Kotlin, Gradle, and build tooling
  may ship in a patch release when they fix compatibility or security issues.
- Minor/major native dependency updates require Android and iOS build checks and
  scanner smoke tests on real hardware before release.
- The bundled ML Kit barcode model remains the default so first-run scanning
  works offline. Any future Play-services model is opt-in and must document its
  download behavior.
- The package tests the minimum declared Flutter version and the latest stable
  patch before a release when both are available.

## Public API and Channel Compatibility

- Existing Dart APIs, method-channel names, and payload keys remain compatible
  within the `0.x` line unless preserving them would retain incorrect or unsafe
  behavior.
- New payload fields are additive. Native implementations must tolerate missing
  fields and Dart must tolerate unknown native values.
- Unsupported camera operations fail explicitly or return actual hardware state;
  they must not silently report success.
- Initial camera configuration applies to the first camera start. Runtime lens,
  torch, and detection state are preserved across unrelated config updates.

## Platform Differences

Android uses CameraX with bundled ML Kit Barcode Scanning. iOS uses
AVFoundation. A capability API planned for an upcoming release will expose
hardware and platform differences directly. Until then, applications should
handle `PlatformException` for unavailable lenses, cameras, or controls.

## Pre-release Hardware Checklist

Every release that changes camera, lifecycle, or decoding code must be checked
on at least one physical Android device and one physical iPhone. A release that
changes the supported platform range must additionally cover the oldest and
newest supported OS versions, using simulators for non-camera build/lifecycle
coverage when physical devices are unavailable.

- Complete one full-screen scan and repeated embedded
  start/stop/pause/resume/dispose cycles.
- Deny camera permission, retry, grant it, and confirm that every pending call
  completes exactly once.
- Exercise torch on supported hardware and confirm that unsupported hardware
  reports its real state without showing a misleading control.
- Switch between front and back cameras when both exist, and request an
  unavailable lens when only one exists.
- Rotate through supported orientations and verify scan-window alignment.
- Scan a dense 1D code, a small QR code, EAN-13, and UPC-A where supported.
- Background and foreground the host during camera startup and active scanning,
  then remove the embedded view and confirm that the camera is released.

## Deprecations

Deprecated APIs remain available for at least one minor release when practical.
Every deprecation includes a replacement and migration note in the changelog.
Correctness fixes such as representing unknown barcode formats accurately may
add enum values; applications should include fallback branches when switching
over package enums.
