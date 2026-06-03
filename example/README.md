# flutter_barcode_scanner_sdk example

Demonstrates the full-screen and embedded scanner APIs from the local package.

## Run

```sh
cd example
/Users/guyzion/fvm/versions/3.44.1/bin/flutter run
```

The example app depends on the package through `path: ../`, so it always uses
the current checkout.

## Demonstrated Scenarios

- Full-screen scanner flow with one-shot and continuous-loop scanning.
- Embedded scanner widget with auto-start, manual controller actions, and
  auto-pause after scan.
- Camera permission handling before native platform-view creation.
- Scan-window detection and whole-preview detection.
- Format presets, including all, QR + Code 128, one-dimensional, and
  two-dimensional groups.
- Flash, camera switching, initial lens, and initial torch settings.
- Pause/resume controls and freeze-preview behavior.
- RTL/LTR strings, app bar styling, status bar styling, overlay opacity, and
  paused scan-window border colors.

## Platform Notes

Android requires a device or emulator with a camera. iOS requires
`NSCameraUsageDescription` in the app `Info.plist`; this example includes it.
