## 0.2.0

### July 14, 2026

**Breaking changes:**

* `FlutterBarcodeScannerFormat.unknown` was added, so exhaustive `switch` statements over the
  format enum must handle it. See [MIGRATION.md](MIGRATION.md#020).

**New:**

* `nativeFormat` on `FlutterBarcodeScanResult` carries the original native identifier, so a
  format this package version does not recognize is no longer reported as a different one.

**Fixed:**

* Embedded controller replacement no longer loses the attached platform view.
* Runtime camera state is preserved across configuration updates.
* Scan-window validation is consistent across Android, iOS, and the Flutter overlay.
* UPC-A reporting is more accurate.
* Permission, lifecycle, torch, and camera-switch handling are hardened on both platforms.

**Compatibility:**

* CameraX upgraded to 1.6.1.
* Package compatibility metadata and the CocoaPods podspec corrected.

## 0.1.2

### July 14, 2026

**Fixed:**

* An iOS `AVCaptureSession` crash caused by metadata output configuration racing with camera
  startup.
* Embedded scanner metadata updates, layout updates, and disposal are serialized with capture
  session startup and shutdown.

## 0.1.1

### June 4, 2026

**Fixed:**

* Dense 1D barcode scanning in full-screen and embedded modes.
* iOS embedded scan-window filtering for long linear barcodes.

## 0.1.0

### June 3, 2026

Initial public release.

**New:**

* Full-screen native barcode scanning for Android and iOS.
* An embedded scanner widget with controller-driven camera, detection, flash, camera switching,
  and configuration updates.
* Support for QR Code, Code 128, Code 39, Code 93, EAN-13, EAN-8, UPC-A, UPC-E, ITF, PDF417,
  Data Matrix, and Aztec formats.
* Package documentation, API reference, example app coverage, and tests.
