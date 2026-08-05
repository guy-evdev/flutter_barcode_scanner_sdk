import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_barcode_scanner_sdk/flutter_barcode_scanner_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('config exposes expected platform map', () {
    final config = FlutterBarcodeScannerConfig(
      strings: FlutterBarcodeScannerStrings(title: 'Barcode Scanner'),
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
    expect((map['strings'] as Map)['title'], 'Barcode Scanner');
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
    // B13: the guard fires at construction, on the line that wrote the bad
    // config, rather than from inside build() when toPlatformMap runs.
    expect(
      () => FlutterBarcodeScannerConfig(
        allowedFormats: {FlutterBarcodeScannerFormat.unknown},
      ),
      throwsAssertionError,
    );
  });

  test('a valid format set constructs without asserting', () {
    expect(
      () => FlutterBarcodeScannerConfig(
        allowedFormats: FlutterBarcodeScannerFormats.all,
      ),
      returnsNormally,
    );
  });

  test('copyWith cannot smuggle in the unknown format', () {
    final config = FlutterBarcodeScannerConfig(
      allowedFormats: FlutterBarcodeScannerFormats.qrOnly,
    );

    expect(
      () => config.copyWith(
        allowedFormats: {FlutterBarcodeScannerFormat.unknown},
      ),
      throwsAssertionError,
    );
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
              return 'granted';
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

      expect(
        await FlutterBarcodeScanner.requestCameraPermission(),
        FlutterBarcodePermissionStatus.granted,
      );
      final result = await FlutterBarcodeScanner.scan(
        FlutterBarcodeScannerConfig(
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
        FlutterBarcodeScannerConfig(),
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
    final original = FlutterBarcodeScannerConfig(
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
      MaterialApp(
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
            config: FlutterBarcodeScannerConfig(),
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

  // B11 — value equality on the config models.

  group('config model equality', () {
    test('identical values compare equal and share a hash code', () {
      final first = FlutterBarcodeScannerConfig(
        allowedFormats: FlutterBarcodeScannerFormats.common,
        strings: const FlutterBarcodeScannerStrings(title: 'Gate A'),
        scanWindow: const FlutterBarcodeScannerScanWindow(widthFactor: 0.7),
        uiConfig: const FlutterBarcodeScannerUiConfig(showFlashButton: false),
        statusBarStyle: const FlutterBarcodeScannerStatusBarStyle(
          isTransparent: true,
        ),
        textDirection: TextDirection.rtl,
        appBarTransparent: true,
        appBarBackgroundColor: const Color(0xFF112233),
        overlayColor: const Color(0x99000000),
      );
      final second = FlutterBarcodeScannerConfig(
        allowedFormats: FlutterBarcodeScannerFormats.common,
        strings: const FlutterBarcodeScannerStrings(title: 'Gate A'),
        scanWindow: const FlutterBarcodeScannerScanWindow(widthFactor: 0.7),
        uiConfig: const FlutterBarcodeScannerUiConfig(showFlashButton: false),
        statusBarStyle: const FlutterBarcodeScannerStatusBarStyle(
          isTransparent: true,
        ),
        textDirection: TextDirection.rtl,
        appBarTransparent: true,
        appBarBackgroundColor: const Color(0xFF112233),
        overlayColor: const Color(0x99000000),
      );

      expect(first, equals(second));
      expect(first.hashCode, equals(second.hashCode));
    });

    test('a difference in any nested model breaks equality', () {
      final base = FlutterBarcodeScannerConfig();

      expect(
        base.copyWith(
          strings: const FlutterBarcodeScannerStrings(title: 'Changed'),
        ),
        isNot(equals(base)),
      );
      expect(
        base.copyWith(
          scanWindow: const FlutterBarcodeScannerScanWindow(cornerRadius: 4),
        ),
        isNot(equals(base)),
      );
      expect(
        base.copyWith(
          uiConfig: const FlutterBarcodeScannerUiConfig(
            initialTorchEnabled: true,
          ),
        ),
        isNot(equals(base)),
      );
      expect(
        base.copyWith(
          statusBarStyle: const FlutterBarcodeScannerStatusBarStyle(
            iconBrightness: FlutterBarcodeScannerStatusBarIconBrightness.dark,
          ),
        ),
        isNot(equals(base)),
      );
      expect(
        base.copyWith(overlayColor: const Color(0xFF00FF00)),
        isNot(equals(base)),
      );
    });

    test('allowedFormats compares as an unordered set', () {
      final first = FlutterBarcodeScannerConfig(
        allowedFormats: const {
          FlutterBarcodeScannerFormat.qrCode,
          FlutterBarcodeScannerFormat.code128,
        },
      );
      final second = FlutterBarcodeScannerConfig(
        allowedFormats: const {
          FlutterBarcodeScannerFormat.code128,
          FlutterBarcodeScannerFormat.qrCode,
        },
      );

      expect(first, equals(second));
      expect(first.hashCode, equals(second.hashCode));
    });

    test('a different format set breaks equality', () {
      expect(
        FlutterBarcodeScannerConfig(
          allowedFormats: FlutterBarcodeScannerFormats.qrOnly,
        ),
        isNot(
          equals(
            FlutterBarcodeScannerConfig(
              allowedFormats: FlutterBarcodeScannerFormats.common,
            ),
          ),
        ),
      );
    });

    test('clearing a nullable field breaks equality', () {
      final withColor = FlutterBarcodeScannerConfig(
        appBarBackgroundColor: const Color(0xFF112233),
      );

      expect(
        withColor.copyWith(clearAppBarBackgroundColor: true),
        isNot(equals(withColor)),
      );
    });

    test('nested models compare by value', () {
      expect(
        const FlutterBarcodeScannerStrings(title: 'A'),
        equals(const FlutterBarcodeScannerStrings(title: 'A')),
      );
      expect(
        const FlutterBarcodeScannerStrings(title: 'A'),
        isNot(equals(const FlutterBarcodeScannerStrings(title: 'B'))),
      );
      expect(
        const FlutterBarcodeScannerScanWindow(widthFactor: 0.5),
        equals(const FlutterBarcodeScannerScanWindow(widthFactor: 0.5)),
      );
      expect(
        const FlutterBarcodeScannerUiConfig(showFlashButton: false),
        equals(const FlutterBarcodeScannerUiConfig(showFlashButton: false)),
      );
      expect(
        const FlutterBarcodeScannerStatusBarStyle(isTransparent: true),
        equals(const FlutterBarcodeScannerStatusBarStyle(isTransparent: true)),
      );
      expect(
        const FlutterBarcodeScannerWidgetConfig(showPauseResumeButton: true),
        equals(
          const FlutterBarcodeScannerWidgetConfig(showPauseResumeButton: true),
        ),
      );
      expect(
        const FlutterBarcodeScannerWidgetConfig(showPauseResumeButton: true),
        isNot(equals(const FlutterBarcodeScannerWidgetConfig())),
      );
    });

    test('scan windows compare declared values, not clamped ones', () {
      // 0.05 and 0.10 both clamp to the 0.2 minimum, but they are different
      // configurations and must not compare equal.
      const low = FlutterBarcodeScannerScanWindow(widthFactor: 0.05);
      const lower = FlutterBarcodeScannerScanWindow(widthFactor: 0.10);

      expect(low.effectiveWidthFactor, equals(lower.effectiveWidthFactor));
      expect(low, isNot(equals(lower)));
    });
  });

  // B12 — synchronous current state.

  group('controller state', () {
    test('starts idle and is readable before anything is attached', () {
      final controller = FlutterBarcodeScannerController();

      expect(controller.currentState, FlutterBarcodeScannerViewState.idle);
      expect(
        controller.stateListenable.value,
        FlutterBarcodeScannerViewState.idle,
      );
    });

    test(
      'currentState tracks native state with no listener attached',
      () async {
        final controller = FlutterBarcodeScannerController();
        controller.attach(41);

        await _emitState(41, FlutterBarcodeScannerViewState.running);

        // The defect B12 fixes: with only a broadcast stream, a value emitted
        // while nothing was listening was simply lost.
        expect(controller.currentState, FlutterBarcodeScannerViewState.running);

        await controller.dispose();
      },
    );

    test('the listenable notifies on change', () async {
      final controller = FlutterBarcodeScannerController();
      controller.attach(42);
      final observed = <FlutterBarcodeScannerViewState>[];
      controller.stateListenable.addListener(
        () => observed.add(controller.currentState),
      );

      await _emitState(42, FlutterBarcodeScannerViewState.initializing);
      await _emitState(42, FlutterBarcodeScannerViewState.running);

      expect(observed, [
        FlutterBarcodeScannerViewState.initializing,
        FlutterBarcodeScannerViewState.running,
      ]);

      await controller.dispose();
    });

    test('a repeated state does not notify again', () async {
      final controller = FlutterBarcodeScannerController();
      controller.attach(43);
      var notifications = 0;
      controller.stateListenable.addListener(() => notifications += 1);

      await _emitState(43, FlutterBarcodeScannerViewState.running);
      await _emitState(43, FlutterBarcodeScannerViewState.running);

      expect(notifications, 1);

      await controller.dispose();
    });

    test('the stream still delivers every emission', () async {
      final controller = FlutterBarcodeScannerController();
      controller.attach(44);
      final streamed = <FlutterBarcodeScannerViewState>[];
      final subscription = controller.state.listen(streamed.add);

      await _emitState(44, FlutterBarcodeScannerViewState.running);
      await _emitState(44, FlutterBarcodeScannerViewState.running);
      await Future<void>.delayed(Duration.zero);

      expect(streamed, [
        FlutterBarcodeScannerViewState.running,
        FlutterBarcodeScannerViewState.running,
      ]);

      await subscription.cancel();
      await controller.dispose();
    });

    test('currentState survives dispose', () async {
      final controller = FlutterBarcodeScannerController();
      controller.attach(45);
      await _emitState(45, FlutterBarcodeScannerViewState.running);

      await controller.dispose();

      expect(controller.currentState, FlutterBarcodeScannerViewState.running);
    });

    test('an unrecognised state name resolves to error', () async {
      final controller = FlutterBarcodeScannerController();
      controller.attach(46);

      await _emitRawState(46, 'somethingNative');

      expect(controller.currentState, FlutterBarcodeScannerViewState.error);

      await controller.dispose();
    });
  });

  group('validate loop', () {
    late List<MethodCall> calls;
    late MethodChannel channel;

    setUp(() {
      calls = <MethodCall>[];
      channel = const MethodChannel(
        'flutter_barcode_scanner_sdk/scanner_view/71',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    Future<void> emitBarcode(String rawValue) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('onResult', <String, Object?>{
                'type': 'barcode',
                'rawValue': rawValue,
                'format': 'CODE_128',
              }),
            ),
            (_) {},
          );
    }

    Future<FlutterBarcodeScannerController> pumpScanner(
      WidgetTester tester, {
      required Future<ScanDecision> Function(FlutterBarcodeScanResult) validate,
      Duration feedback = const Duration(milliseconds: 100),
      bool autoPauseOnScan = true,
      void Function(FlutterBarcodeScanResult)? onScan,
    }) async {
      final controller = FlutterBarcodeScannerController()..attach(71);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterBarcodeScannerView(
            controller: controller,
            config: FlutterBarcodeScannerConfig(),
            widgetConfig: FlutterBarcodeScannerWidgetConfig(
              autoRequestCameraPermission: false,
              validationFeedbackDuration: feedback,
              // Off, so these tests prove the phase guard blocks re-entry
              // rather than the duplicate filter silently doing it for them.
              duplicateScanCooldown: Duration.zero,
            ),
            autoPauseOnScan: autoPauseOnScan,
            onScan: onScan,
            onScanValidate: validate,
          ),
        ),
      );
      return controller;
    }

    testWidgets('accepted scan shows feedback then resumes', (tester) async {
      final controller = await pumpScanner(
        tester,
        validate: (_) async => const ScanDecision.accept(message: 'Admitted'),
      );

      await emitBarcode('CODE-1');
      await tester.pump();

      expect(controller.currentFeedback?.decision.isAccepted, isTrue);
      expect(controller.currentFeedback?.decision.message, 'Admitted');
      expect(find.text('Admitted'), findsOneWidget);
      expect(
        calls.map((call) => call.method),
        isNot(contains('resumeDetection')),
      );

      await tester.pump(const Duration(milliseconds: 150));

      expect(controller.currentFeedback, isNull);
      expect(calls.map((call) => call.method), contains('resumeDetection'));
    });

    testWidgets('rejected scan reports the rejection', (tester) async {
      final controller = await pumpScanner(
        tester,
        validate: (_) async =>
            const ScanDecision.reject(message: 'Already used'),
      );

      await emitBarcode('CODE-2');
      await tester.pump();

      expect(controller.currentFeedback?.decision.isRejected, isTrue);
      expect(find.text('Already used'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.currentFeedback, isNull);
    });

    testWidgets('a second scan during a slow decision is not validated twice', (
      tester,
    ) async {
      var validations = 0;
      final gate = Completer<ScanDecision>();
      await pumpScanner(
        tester,
        validate: (_) {
          validations += 1;
          return gate.future;
        },
      );

      await emitBarcode('CODE-3');
      await tester.pump();
      await emitBarcode('CODE-3');
      await emitBarcode('CODE-4');
      await tester.pump();

      expect(validations, 1);

      gate.complete(const ScanDecision.accept());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
    });

    testWidgets('a scan during feedback is not validated twice', (
      tester,
    ) async {
      var validations = 0;
      await pumpScanner(
        tester,
        validate: (_) async {
          validations += 1;
          return const ScanDecision.accept();
        },
      );

      await emitBarcode('CODE-5');
      await tester.pump();
      expect(validations, 1);

      await emitBarcode('CODE-6');
      await tester.pump();
      expect(validations, 1, reason: 'feedback is still showing');

      await tester.pump(const Duration(milliseconds: 150));
      await emitBarcode('CODE-7');
      await tester.pump();
      expect(validations, 2, reason: 'the loop is idle again');

      await tester.pump(const Duration(milliseconds: 150));
    });

    testWidgets('a throwing validator rejects and still resumes', (
      tester,
    ) async {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;

      final controller = await pumpScanner(
        tester,
        validate: (_) async => throw StateError('backend down'),
      );

      await emitBarcode('CODE-8');
      await tester.pump();
      final feedback = controller.currentFeedback;
      await tester.pump(const Duration(milliseconds: 150));
      // Restore before asserting: the binding checks that a test left
      // FlutterError.onError as it found it, and it checks before tearDown.
      FlutterError.onError = previous;

      expect(feedback?.decision.isRejected, isTrue);
      expect(errors, hasLength(1));
      expect(errors.single.exception, isStateError);
      expect(calls.map((call) => call.method), contains('resumeDetection'));
    });

    testWidgets('detection is held even when autoPauseOnScan is false', (
      tester,
    ) async {
      await pumpScanner(
        tester,
        autoPauseOnScan: false,
        validate: (_) async => const ScanDecision.accept(),
      );

      await emitBarcode('CODE-9');
      await tester.pump();

      expect(calls.map((call) => call.method), contains('pauseDetection'));

      await tester.pump(const Duration(milliseconds: 150));
    });

    testWidgets('a decision arriving after disposal is discarded', (
      tester,
    ) async {
      final gate = Completer<ScanDecision>();
      final controller = await pumpScanner(
        tester,
        validate: (_) => gate.future,
      );

      await emitBarcode('CODE-10');
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      calls.clear();

      gate.complete(const ScanDecision.accept(message: 'late'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(controller.currentFeedback, isNull);
      expect(calls, isEmpty);
    });

    testWidgets('zero feedback duration resumes immediately', (tester) async {
      final controller = await pumpScanner(
        tester,
        feedback: Duration.zero,
        validate: (_) async => const ScanDecision.accept(),
      );

      await emitBarcode('CODE-11');
      await tester.pump();
      await tester.pump();

      expect(controller.currentFeedback, isNull);
      expect(calls.map((call) => call.method), contains('resumeDetection'));
    });

    testWidgets('onScan still fires for every result', (tester) async {
      final seen = <String>[];
      await pumpScanner(
        tester,
        validate: (_) async => const ScanDecision.accept(),
        onScan: (result) => seen.add(result.rawValue),
      );

      await emitBarcode('CODE-12');
      await tester.pump();
      await emitBarcode('CODE-13');
      await tester.pump();

      expect(seen, ['CODE-12', 'CODE-13']);

      await tester.pump(const Duration(milliseconds: 150));
    });
  });

  group('duplicate filtering and accept feedback', () {
    late List<MethodCall> viewCalls;
    late List<MethodCall> platformCalls;
    late MethodChannel channel;

    setUp(() {
      viewCalls = <MethodCall>[];
      platformCalls = <MethodCall>[];
      channel = const MethodChannel(
        'flutter_barcode_scanner_sdk/scanner_view/93',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            viewCalls.add(call);
            return null;
          });
      // HapticFeedback and SystemSound both go through SystemChannels.platform.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            platformCalls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Future<void> emit(String rawValue, {String type = 'barcode'}) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('onResult', <String, Object?>{
                'type': type,
                'rawValue': rawValue,
                'format': 'CODE_128',
              }),
            ),
            (_) {},
          );
    }

    Future<List<String>> pumpScanner(
      WidgetTester tester, {
      FlutterBarcodeScannerWidgetConfig? widgetConfig,
      Future<ScanDecision> Function(FlutterBarcodeScanResult)? validate,
      bool reduceMotion = false,
    }) async {
      final seen = <String>[];
      final controller = FlutterBarcodeScannerController()..attach(93);
      addTearDown(controller.dispose);
      Widget scanner = FlutterBarcodeScannerView(
        controller: controller,
        config: FlutterBarcodeScannerConfig(),
        widgetConfig:
            widgetConfig ??
            const FlutterBarcodeScannerWidgetConfig(
              autoRequestCameraPermission: false,
            ),
        onScan: (result) => seen.add(result.rawValue),
        onScanValidate: validate,
      );
      if (reduceMotion) {
        scanner = MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: scanner,
        );
      }
      await tester.pumpWidget(MaterialApp(home: scanner));
      return seen;
    }

    testWidgets('an immediate repeat of the same value is dropped', (
      tester,
    ) async {
      final seen = await pumpScanner(tester);

      await emit('CODE-A');
      await emit('CODE-A');
      await emit('CODE-A');
      await tester.pump();

      expect(seen, ['CODE-A']);
    });

    testWidgets('a different value is never swallowed', (tester) async {
      final seen = await pumpScanner(tester);

      await emit('CODE-A');
      await emit('CODE-B');
      await emit('CODE-A');
      await tester.pump();

      expect(seen, ['CODE-A', 'CODE-B', 'CODE-A']);
    });

    testWidgets('the same value is reported again after the cooldown', (
      tester,
    ) async {
      final seen = await pumpScanner(
        tester,
        widgetConfig: const FlutterBarcodeScannerWidgetConfig(
          autoRequestCameraPermission: false,
          duplicateScanCooldown: Duration(milliseconds: 40),
        ),
      );

      await emit('CODE-A');
      await emit('CODE-A');
      await tester.pump(const Duration(milliseconds: 80));
      await emit('CODE-A');
      await tester.pump();

      expect(seen, ['CODE-A', 'CODE-A']);
    });

    testWidgets('a zero cooldown reports every decode', (tester) async {
      final seen = await pumpScanner(
        tester,
        widgetConfig: const FlutterBarcodeScannerWidgetConfig(
          autoRequestCameraPermission: false,
          duplicateScanCooldown: Duration.zero,
        ),
      );

      await emit('CODE-A');
      await emit('CODE-A');
      await tester.pump();

      expect(seen, ['CODE-A', 'CODE-A']);
    });

    testWidgets('cancelled results are never filtered', (tester) async {
      final seen = await pumpScanner(tester);

      await emit('', type: 'cancelled');
      await emit('', type: 'cancelled');
      await tester.pump();

      expect(seen, ['', '']);
    });

    testWidgets('an accepted scan fires a haptic', (tester) async {
      await pumpScanner(
        tester,
        validate: (_) async => const ScanDecision.accept(),
      );

      await emit('CODE-A');
      await tester.pump();

      expect(
        platformCalls.map((call) => call.method),
        contains('HapticFeedback.vibrate'),
      );
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a rejected scan does not', (tester) async {
      await pumpScanner(
        tester,
        validate: (_) async => const ScanDecision.reject(),
      );

      await emit('CODE-A');
      await tester.pump();

      expect(
        platformCalls.map((call) => call.method),
        isNot(contains('HapticFeedback.vibrate')),
      );
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('Reduce Motion suppresses the haptic', (tester) async {
      await pumpScanner(
        tester,
        reduceMotion: true,
        validate: (_) async => const ScanDecision.accept(),
      );

      await emit('CODE-A');
      await tester.pump();

      expect(
        platformCalls.map((call) => call.method),
        isNot(contains('HapticFeedback.vibrate')),
      );
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the sound is off by default', (tester) async {
      await pumpScanner(
        tester,
        validate: (_) async => const ScanDecision.accept(),
      );

      await emit('CODE-A');
      await tester.pump();

      expect(
        platformCalls.map((call) => call.method),
        isNot(contains('SystemSound.play')),
      );
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the sound can be opted into', (tester) async {
      await pumpScanner(
        tester,
        widgetConfig: const FlutterBarcodeScannerWidgetConfig(
          autoRequestCameraPermission: false,
          soundOnAccept: true,
        ),
        validate: (_) async => const ScanDecision.accept(),
      );

      await emit('CODE-A');
      await tester.pump();

      expect(
        platformCalls.map((call) => call.method),
        contains('SystemSound.play'),
      );
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('permission contract', () {
    test('status parses native values', () {
      expect(
        FlutterBarcodePermissionStatus.fromNativeValue('granted'),
        FlutterBarcodePermissionStatus.granted,
      );
      expect(
        FlutterBarcodePermissionStatus.fromNativeValue('permanentlyDenied'),
        FlutterBarcodePermissionStatus.permanentlyDenied,
      );
      expect(
        FlutterBarcodePermissionStatus.fromNativeValue('restricted'),
        FlutterBarcodePermissionStatus.restricted,
      );
      expect(
        FlutterBarcodePermissionStatus.fromNativeValue('notDetermined'),
        FlutterBarcodePermissionStatus.notDetermined,
      );
    });

    test('an unknown native value is never mistaken for granted', () {
      expect(
        FlutterBarcodePermissionStatus.fromNativeValue('somethingNew'),
        FlutterBarcodePermissionStatus.denied,
      );
      expect(
        FlutterBarcodePermissionStatus.fromNativeValue(null),
        FlutterBarcodePermissionStatus.denied,
      );
    });

    test('canRequest is true only where a prompt can still appear', () {
      expect(FlutterBarcodePermissionStatus.notDetermined.canRequest, isTrue);
      expect(FlutterBarcodePermissionStatus.denied.canRequest, isTrue);
      expect(
        FlutterBarcodePermissionStatus.permanentlyDenied.canRequest,
        isFalse,
      );
      expect(FlutterBarcodePermissionStatus.restricted.canRequest, isFalse);
      expect(FlutterBarcodePermissionStatus.granted.canRequest, isFalse);
    });

    test('requiresSettings marks the states the user cannot fix in-app', () {
      expect(
        FlutterBarcodePermissionStatus.permanentlyDenied.requiresSettings,
        isTrue,
      );
      expect(
        FlutterBarcodePermissionStatus.restricted.requiresSettings,
        isTrue,
      );
      expect(FlutterBarcodePermissionStatus.denied.requiresSettings, isFalse);
      expect(FlutterBarcodePermissionStatus.granted.isGranted, isTrue);
    });

    test('the static API speaks the status contract', () async {
      const channel = MethodChannel('flutter_barcode_scanner_sdk/methods');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'openAppSettings') {
              return true;
            }
            return 'permanentlyDenied';
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      expect(
        await FlutterBarcodeScanner.checkCameraPermission(),
        FlutterBarcodePermissionStatus.permanentlyDenied,
      );
      expect(
        await FlutterBarcodeScanner.requestCameraPermission(),
        FlutterBarcodePermissionStatus.permanentlyDenied,
      );
      expect(await FlutterBarcodeScanner.openAppSettings(), isTrue);
      expect(calls.map((call) => call.method), [
        'checkCameraPermission',
        'requestCameraPermission',
        'openAppSettings',
      ]);
    });
  });
}

/// Delivers an `onState` callback as the native side would.
Future<void> _emitState(int viewId, FlutterBarcodeScannerViewState state) =>
    _emitRawState(viewId, state.name);

Future<void> _emitRawState(int viewId, String name) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'flutter_barcode_scanner_sdk/scanner_view/$viewId',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onState', name),
        ),
        (_) {},
      );
}
