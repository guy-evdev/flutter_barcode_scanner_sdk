## 0.2.0

- Upgraded CameraX to 1.6.1 and hardened permission, lifecycle, torch, and
  camera-switch handling on Android and iOS.
- Fixed embedded controller replacement and preserved runtime camera state across
  configuration updates.
- Standardized scan-window validation and improved UPC-A and unknown-format
  reporting. Exhaustive format switches must now handle `unknown`.
- Expanded native/Flutter tests and CI, and corrected package compatibility and
  CocoaPods metadata.

## 0.1.2

- Fixed an iOS `AVCaptureSession` crash caused by metadata output configuration
  racing with camera startup.
- Serialized embedded scanner metadata updates, layout updates, and disposal with
  capture session startup and shutdown.

## 0.1.1

- Improved dense 1D barcode scanning in full-screen and embedded modes.
- Fixed iOS embedded scan-window filtering for long linear barcodes.

## 0.1.0

Initial public release.

- Added full-screen native barcode scanning for Android and iOS.
- Added an embedded scanner widget with controller-driven camera, detection,
  flash, camera switching, and configuration updates.
- Support for QR Code, Code 128, Code 39, Code 93, EAN-13, EAN-8, UPC-A, UPC-E,
  ITF, PDF417, Data Matrix, and Aztec formats.
- Added package documentation, API reference, example app coverage, and tests.
