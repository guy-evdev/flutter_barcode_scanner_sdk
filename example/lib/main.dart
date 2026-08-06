import 'package:flutter/material.dart';

import 'demo_settings.dart';
import 'harness/dense_sheet_page.dart';
import 'harness/mount_cycle_page.dart';
import 'harness/stress_harness_page.dart';
import 'harness/validate_soak_page.dart';
import 'pages/home_page.dart';

/// Selects a harness to run unattended, set with
/// `--dart-define=HARNESS_AUTORUN=cycles`.
///
/// Accepts `cycles`, `soak`, `validate-soak` and `dense-sheet`. Physical
/// iPhones cannot be driven by injected taps the way an Android device can, so
/// the harness has to start itself and report over the log.
const String kHarnessAutorun = String.fromEnvironment('HARNESS_AUTORUN');

void main() {
  runApp(ScannerShowcaseApp(settings: DemoSettings()));
}

/// The example app shell.
class ScannerShowcaseApp extends StatelessWidget {
  const ScannerShowcaseApp({required this.settings, super.key});

  /// The shared configuration every page reads and writes.
  final DemoSettings settings;

  @override
  Widget build(BuildContext context) {
    return DemoSettingsScope(
      notifier: settings,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0A1C58)),
          useMaterial3: true,
        ),
        home: Builder(builder: _buildHome),
      ),
    );
  }

  Widget _buildHome(BuildContext context) {
    // Read through the scope so the harnesses see configuration changes too.
    final settings = DemoSettingsScope.of(context);
    return switch (kHarnessAutorun) {
      'cycles' => MountCyclePage(
        config: settings.buildConfig(),
        autoStart: true,
      ),
      'soak' => StressHarnessPage(
        config: settings.buildConfig(),
        autoStart: true,
      ),
      'validate-soak' => ValidateSoakPage(
        config: settings.buildConfig(),
        widgetConfig: settings.buildWidgetConfig(),
        autoStart: true,
      ),
      'dense-sheet' => DenseSheetPage(
        config: settings.buildConfig(),
        widgetConfig: settings.buildWidgetConfig(),
        autoStart: true,
      ),
      _ => const HomePage(),
    };
  }
}
