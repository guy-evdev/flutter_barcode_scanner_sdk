import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_barcode_scanner_sdk/flutter_barcode_scanner_sdk.dart';

void main() {
  test('config exposes expected platform map', () {
    const config = FlutterBarcodeScannerConfig(
      strings: FlutterBarcodeScannerStrings(title: 'Ticket Scanner'),
      scanWindow: FlutterBarcodeScannerScanWindow(
        enabled: false,
        widthFactor: 0.7,
        heightFactor: 0.4,
        cornerRadius: 24,
      ),
      uiConfig: FlutterBarcodeScannerUiConfig(
        showFlashButton: false,
        showCameraSwitchButton: true,
        initialCameraLens: BarcodeCameraLens.front,
        initialTorchEnabled: true,
      ),
      textDirection: TextDirection.rtl,
      appBarTransparent: true,
    );

    final map = config.toPlatformMap();

    expect(map['textDirection'], 'rtl');
    expect(map['appBarTransparent'], isTrue);
    expect(map['allowedFormats'], isEmpty);
    expect((map['strings'] as Map)['title'], 'Ticket Scanner');
    expect((map['scanWindow'] as Map)['enabled'], isFalse);
    expect((map['scanWindow'] as Map)['widthFactor'], 0.7);
    expect((map['uiConfig'] as Map)['initialCameraLens'], 'front');
    expect((map['uiConfig'] as Map)['initialTorchEnabled'], isTrue);
  });

  test('scan result parses payload maps', () {
    final result = FlutterBarcodeScanResult.fromMap({
      'type': 'barcode',
      'rawValue': 'abc-123',
      'format': 'CODE_128',
      'errorCode': null,
      'errorMessage': null,
    });

    expect(result.isBarcode, isTrue);
    expect(result.isCancelled, isFalse);
    expect(result.rawValue, 'abc-123');
    expect(result.format, FlutterBarcodeScannerFormat.code128);
    expect(result.valueOrNull, 'abc-123');
    expect(result.isError, isFalse);
  });

  test('format presets expose expected groups', () {
    expect(
      FlutterBarcodeScannerFormats.all,
      containsAll(FlutterBarcodeScannerFormat.values),
    );
    expect(
      FlutterBarcodeScannerFormats.twoDimensional,
      containsAll({
        FlutterBarcodeScannerFormat.qrCode,
        FlutterBarcodeScannerFormat.pdf417,
        FlutterBarcodeScannerFormat.dataMatrix,
        FlutterBarcodeScannerFormat.aztec,
      }),
    );
    expect(
      FlutterBarcodeScannerFormats.oneDimensional,
      isNot(contains(FlutterBarcodeScannerFormat.qrCode)),
    );
    expect(
      FlutterBarcodeScannerFormat.fromNativeValue('code-128'),
      FlutterBarcodeScannerFormat.code128,
    );
  });

  test('config copyWith replaces and clears nullable values', () {
    const original = FlutterBarcodeScannerConfig(
      textDirection: TextDirection.rtl,
      appBarBackgroundColor: Colors.blue,
      appBarForegroundColor: Colors.white,
    );

    final updated = original.copyWith(
      allowedFormats: FlutterBarcodeScannerFormats.qrOnly,
      clearTextDirection: true,
      clearAppBarBackgroundColor: true,
      overlayColor: Colors.green,
    );

    expect(updated.allowedFormats, FlutterBarcodeScannerFormats.qrOnly);
    expect(updated.textDirection, isNull);
    expect(updated.appBarBackgroundColor, isNull);
    expect(updated.appBarForegroundColor, Colors.white);
    expect(updated.overlayColor, Colors.green);
  });

  test('scan result copyWith handles error fields', () {
    const result = FlutterBarcodeScanResult(
      type: FlutterBarcodeScannerResultType.error,
      rawValue: '',
      format: FlutterBarcodeScannerFormat.qrCode,
      errorCode: 'CAMERA_UNAVAILABLE',
      errorMessage: 'Camera unavailable',
    );

    final updated = result.copyWith(
      type: FlutterBarcodeScannerResultType.cancelled,
      clearErrorCode: true,
      clearErrorMessage: true,
    );

    expect(result.isError, isTrue);
    expect(result.hasErrorDetails, isTrue);
    expect(updated.isCancelled, isTrue);
    expect(updated.hasErrorDetails, isFalse);
  });

  test('widget config exposes expected platform map', () {
    const config = FlutterBarcodeScannerWidgetConfig(
      autoRequestCameraPermission: true,
      freezePreviewWhenPaused: true,
      showPauseResumeButton: true,
      scanWindowBorderColor: Colors.white,
      pausedScanWindowBorderColor: Colors.red,
      pauseTooltip: 'Pause',
      resumeTooltip: 'Resume',
    );

    final map = config.toMap();

    expect(map['autoRequestCameraPermission'], isTrue);
    expect(map['freezePreviewWhenPaused'], isTrue);
    expect(map['showPauseResumeButton'], isTrue);
    expect(map['pausedScanWindowBorderColor'], Colors.red.toARGB32());
    expect(map['pauseTooltip'], 'Pause');
    expect(map['resumeTooltip'], 'Resume');
  });

  test('embedded scanner state enum exposes stable native names', () {
    expect(FlutterBarcodeScannerViewState.running.name, 'running');
    expect(
      FlutterBarcodeScannerViewState.detectionPaused.name,
      'detectionPaused',
    );
  });

  testWidgets('embedded scanner renders unsupported platform fallback', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 240,
          height: 180,
          child: FlutterBarcodeScannerView(
            config: FlutterBarcodeScannerConfig(),
          ),
        ),
      ),
    );

    expect(
      find.text('Barcode scanning is only available on Android and iOS.'),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
