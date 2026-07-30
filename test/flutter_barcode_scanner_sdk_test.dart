import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_barcode_scanner_sdk/flutter_barcode_scanner_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      containsAll(
        FlutterBarcodeScannerFormat.values.where(
          (format) => format != FlutterBarcodeScannerFormat.unknown,
        ),
      ),
    );
    expect(
      FlutterBarcodeScannerFormats.all,
      isNot(contains(FlutterBarcodeScannerFormat.unknown)),
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

  test('unknown native formats are preserved without becoming QR codes', () {
    final result = FlutterBarcodeScanResult.fromMap({
      'type': 'barcode',
      'rawValue': 'value',
      'format': 'FUTURE_FORMAT',
    });

    expect(result.format, FlutterBarcodeScannerFormat.unknown);
    expect(result.nativeFormat, 'FUTURE_FORMAT');
  });

  test('unknown format cannot be requested for detection', () {
    const config = FlutterBarcodeScannerConfig(
      allowedFormats: {FlutterBarcodeScannerFormat.unknown},
    );

    expect(config.toPlatformMap, throwsArgumentError);
  });

  test('scan window normalizes invalid platform values', () {
    const config = FlutterBarcodeScannerScanWindow(
      widthFactor: double.infinity,
      heightFactor: 0.01,
      cornerRadius: -5,
    );

    expect(config.effectiveWidthFactor, 0.58);
    expect(config.effectiveHeightFactor, 0.2);
    expect(config.effectiveCornerRadius, 0);
    expect(config.toMap()['widthFactor'], 0.58);
    expect(config.toMap()['heightFactor'], 0.2);
    expect(config.toMap()['cornerRadius'], 0);
  });

  test(
    'static scanner methods use the stable method-channel contract',
    () async {
      const channel = MethodChannel('flutter_barcode_scanner_sdk/methods');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'requestCameraPermission') {
              return true;
            }
            return <String, Object?>{
              'type': 'barcode',
              'rawValue': 'abc',
              'format': 'QR_CODE',
            };
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      expect(await FlutterBarcodeScanner.requestCameraPermission(), isTrue);
      final result = await FlutterBarcodeScanner.scan(
        const FlutterBarcodeScannerConfig(
          allowedFormats: FlutterBarcodeScannerFormats.qrOnly,
        ),
      );

      expect(result?.rawValue, 'abc');
      expect(calls.map((call) => call.method), [
        'requestCameraPermission',
        'scan',
      ]);
      expect((calls.last.arguments as Map)['allowedFormats'], ['QR_CODE']);
    },
  );

  test(
    'controller serializes commands and refuses use after disposal',
    () async {
      const channel = MethodChannel(
        'flutter_barcode_scanner_sdk/scanner_view/7',
      );
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'toggleFlash') {
              return true;
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final controller = FlutterBarcodeScannerController()..attach(7);
      expect(controller.isAttached, isTrue);
      expect(await controller.toggleFlash(true), isTrue);
      await controller.switchCamera(BarcodeCameraLens.front);
      await controller.updateConfig(
        const FlutterBarcodeScannerConfig(),
        autoPauseOnScan: false,
        widgetConfig: const FlutterBarcodeScannerWidgetConfig(
          // ignore: deprecated_member_use_from_same_package
          freezePreviewWhenPaused: true,
        ),
      );
      await controller.dispose();

      expect(calls.map((call) => call.method), [
        'toggleFlash',
        'switchCamera',
        'updateConfig',
        'dispose',
      ]);
      expect((calls[0].arguments as Map)['enabled'], isTrue);
      expect((calls[1].arguments as Map)['lens'], 'front');
      await expectLater(controller.startCamera(), throwsStateError);
    },
  );

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
      // Deprecated and ignored by both platforms since 0.2.1. It stays on the
      // wire until 0.3.0 removes the field, so the key is asserted on purpose.
      // ignore: deprecated_member_use_from_same_package
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

  testWidgets(
    'embedded lifecycle stop and paused-state restore are race safe',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });
      const channel = MethodChannel(
        'flutter_barcode_scanner_sdk/scanner_view/19',
      );
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final controller = FlutterBarcodeScannerController()..attach(19);
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterBarcodeScannerView(
            controller: controller,
            config: const FlutterBarcodeScannerConfig(),
            widgetConfig: const FlutterBarcodeScannerWidgetConfig(
              autoRequestCameraPermission: false,
            ),
          ),
        ),
      );

      Future<void> emitState(FlutterBarcodeScannerViewState state) async {
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              channel.name,
              const StandardMethodCodec().encodeMethodCall(
                MethodCall('onState', state.name),
              ),
              (_) {},
            );
        await tester.pump();
      }

      await emitState(FlutterBarcodeScannerViewState.running);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(calls.where((call) => call.method == 'stopCamera'), hasLength(1));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls.where((call) => call.method == 'startCamera'), hasLength(1));

      await emitState(FlutterBarcodeScannerViewState.detectionPaused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(calls.where((call) => call.method == 'stopCamera'), hasLength(2));
      expect(calls.where((call) => call.method == 'startCamera'), hasLength(2));
      expect(
        calls.where((call) => call.method == 'pauseDetection'),
        hasLength(1),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await controller.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
