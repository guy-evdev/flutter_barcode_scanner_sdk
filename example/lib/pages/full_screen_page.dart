import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner_sdk/flutter_barcode_scanner_sdk.dart';

import '../demo_settings.dart';
import '../widgets/common.dart';

/// The one-call flow: open the native scanner, get one result back.
class FullScreenPage extends StatefulWidget {
  const FullScreenPage({super.key});

  @override
  State<FullScreenPage> createState() => _FullScreenPageState();
}

class _FullScreenPageState extends State<FullScreenPage> {
  final List<FlutterBarcodeScanResult> _history = <FlutterBarcodeScanResult>[];

  bool _continuous = false;
  bool _launching = false;
  FlutterBarcodeScanResult? _last;

  Future<void> _start(DemoSettings settings) async {
    if (_launching) {
      return;
    }
    setState(() => _launching = true);
    try {
      while (mounted) {
        final result = await FlutterBarcodeScanner.scan(settings.buildConfig());
        if (!mounted) {
          return;
        }
        if (result != null) {
          _record(result);
        }
        if (!_continuous || result == null || result.isCancelled) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    } finally {
      if (mounted) {
        setState(() => _launching = false);
      }
    }
  }

  void _record(FlutterBarcodeScanResult result) {
    setState(() {
      _last = result;
      _history.insert(0, result);
      if (_history.length > 8) {
        _history.removeLast();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = DemoSettingsScope.of(context);
    final last = _last;
    return Scaffold(
      appBar: AppBar(title: const Text('Full-screen scanner')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'FlutterBarcodeScanner.scan(config) opens the native scanner and '
            'completes with one result, or null if the user backed out.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _launching ? null : () => _start(settings),
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(_launching ? 'Scanning…' : 'Start scanning'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _continuous,
            title: const Text('Continuous loop'),
            subtitle: const Text('Reopen after each result until cancelled'),
            onChanged: (v) => setState(() => _continuous = v),
          ),
          const SizedBox(height: 8),
          SectionCard(
            title: 'Last result',
            child: last == null
                ? const Text('Nothing scanned yet.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ConfigLine(label: 'Type', value: last.type.name),
                      ConfigLine(
                        label: 'Raw value',
                        value: last.rawValue.isEmpty ? '—' : last.rawValue,
                      ),
                      ConfigLine(
                        label: 'Format',
                        value: last.format.nativeValue,
                      ),
                      if (last.errorMessage != null)
                        ConfigLine(label: 'Error', value: last.errorMessage!),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Active configuration',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConfigLine(label: 'Formats', value: settings.formatSummary),
                ConfigLine(
                  label: 'Window',
                  value: settings.scanWindowEnabled
                      ? '${(settings.scanWindowWidthFraction * 100).round()}% wide '
                            'at ${settings.scanWindowAspectRatio.toStringAsFixed(2)}:1'
                      : 'Full preview',
                ),
                ConfigLine(label: 'Aim', value: settings.aimMode.name),
                ConfigLine(
                  label: 'Confirm',
                  value: '${settings.scanConfirmationFrames} observations',
                ),
                ConfigLine(
                  label: 'Language',
                  value: settings.language == DemoLanguage.hebrew
                      ? 'Hebrew'
                      : 'English',
                ),
                ConfigLine(label: 'Title', value: settings.strings.title),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'History',
            child: _history.isEmpty
                ? const Text('No scans in this session.')
                : Column(
                    children: [
                      for (final result in _history) ResultTile(result: result),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
