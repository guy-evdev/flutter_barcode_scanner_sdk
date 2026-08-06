import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner_sdk/flutter_barcode_scanner_sdk.dart';

import '../widgets/common.dart';

/// Phases of a dense-sheet accuracy run.
enum SheetPhase {
  /// Collecting the distinct codes printed on the sheet.
  register,

  /// Aiming at a named target and scoring each decode.
  run,
}

/// Dense-sheet accuracy harness for the release gate.
///
/// Selecting the *nearest* code to the scan-window centre is only testable if
/// the app knows what you were aiming at. So the run has two phases: register
/// the sheet, then aim at a code the page names and let it score the decode.
///
/// Gate: 100 scans from a sheet of at least six codes on both devices, zero
/// wrong-code reads, no scan over two seconds.
class DenseSheetPage extends StatefulWidget {
  const DenseSheetPage({
    super.key,
    required this.config,
    required this.widgetConfig,
    this.autoStart = false,
  });

  /// Scanner configuration used for the run.
  final FlutterBarcodeScannerConfig config;

  /// Widget configuration used for the run.
  final FlutterBarcodeScannerWidgetConfig widgetConfig;

  /// Skips straight to registering, for `--dart-define=HARNESS_AUTORUN=dense-sheet`.
  ///
  /// The run phase still needs a person to aim, so this only removes the taps
  /// needed to reach the page in a working state.
  final bool autoStart;

  @override
  State<DenseSheetPage> createState() => _DenseSheetPageState();
}

class _DenseSheetPageState extends State<DenseSheetPage> {
  static const _minSheetCodes = 6;
  static const _slowScanThreshold = Duration(seconds: 2);
  static const _scanOptions = <int>[25, 100];

  final FlutterBarcodeScannerController _controller =
      FlutterBarcodeScannerController();
  final List<String> _sheet = <String>[];
  final List<int> _latenciesMs = <int>[];
  final Random _random = Random();

  SheetPhase _phase = SheetPhase.register;
  String? _target;
  int _hits = 0;
  int _wrongCodeReads = 0;
  int _unknowns = 0;
  int _targetScans = 100;
  DateTime? _aimedAt;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      debugPrint('dense-sheet: register every code on the sheet, then Start.');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onScan(FlutterBarcodeScanResult result) {
    if (!result.isBarcode || result.rawValue.isEmpty) {
      return;
    }
    if (_phase == SheetPhase.register) {
      if (!_sheet.contains(result.rawValue)) {
        setState(() => _sheet.add(result.rawValue));
      }
      return;
    }
    _score(result.rawValue);
  }

  void _score(String value) {
    final aimedAt = _aimedAt;
    if (aimedAt != null) {
      _latenciesMs.add(DateTime.now().difference(aimedAt).inMilliseconds);
    }
    setState(() {
      if (value == _target) {
        _hits += 1;
      } else if (_sheet.contains(value)) {
        _wrongCodeReads += 1;
      } else {
        _unknowns += 1;
      }
      _nextTarget();
    });
    if (_hits + _wrongCodeReads + _unknowns >= _targetScans) {
      _emitReport();
    }
  }

  void _nextTarget() {
    if (_sheet.isEmpty) {
      return;
    }
    String next;
    do {
      next = _sheet[_random.nextInt(_sheet.length)];
    } while (_sheet.length > 1 && next == _target);
    _target = next;
    _aimedAt = DateTime.now();
  }

  void _startRun() {
    setState(() {
      _phase = SheetPhase.run;
      _hits = 0;
      _wrongCodeReads = 0;
      _unknowns = 0;
      _latenciesMs.clear();
      _target = null;
      _nextTarget();
    });
  }

  void _emitReport() {
    debugPrint('===HARNESS-REPORT-BEGIN===');
    for (final line in _report.split('\n')) {
      debugPrint(line);
    }
    debugPrint('===HARNESS-REPORT-END===');
  }

  String get _report {
    final scans = _hits + _wrongCodeReads + _unknowns;
    final sorted = List<int>.from(_latenciesMs)..sort();
    final slow = sorted
        .where((ms) => ms > _slowScanThreshold.inMilliseconds)
        .length;
    final buffer = StringBuffer()
      ..writeln('dense-sheet')
      ..writeln('sheet codes      : ${_sheet.length}')
      ..writeln('scans            : $scans / $_targetScans')
      ..writeln('hits             : $_hits')
      ..writeln('wrong-code reads : $_wrongCodeReads')
      ..writeln('unknown values   : $_unknowns');
    if (sorted.isNotEmpty) {
      buffer
        ..writeln('latency median   : ${sorted[sorted.length ~/ 2]} ms')
        ..writeln('latency max      : ${sorted.last} ms')
        ..writeln('over ${_slowScanThreshold.inSeconds}s        : $slow');
    }
    final passed =
        scans >= _targetScans &&
        _sheet.length >= _minSheetCodes &&
        _wrongCodeReads == 0 &&
        slow == 0;
    buffer.writeln('gate             : ${passed ? 'PASS' : 'not met'}');
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final registering = _phase == SheetPhase.register;
    return Scaffold(
      appBar: AppBar(title: const Text('Dense sheet accuracy')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            registering
                ? 'Scan every code on the sheet once, so the run knows what is '
                      'printed on it. At least $_minSheetCodes codes.'
                : 'Aim the scan window at the named code. Every decode is '
                      'scored against it.',
          ),
          const SizedBox(height: 12),
          if (!registering)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('Aim at'),
                    const SizedBox(height: 4),
                    Text(
                      _target ?? '—',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            height: 300,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: FlutterBarcodeScannerView(
                controller: _controller,
                config: widget.config,
                widgetConfig: widget.widgetConfig,
                autoPauseOnScan: false,
                onScan: _onScan,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (registering) ...[
            Text('Registered ${_sheet.length} codes'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final code in _sheet)
                  Chip(
                    label: Text(code, overflow: TextOverflow.ellipsis),
                    onDeleted: () => setState(() => _sheet.remove(code)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final option in _scanOptions)
                  ChoiceChip(
                    label: Text('$option scans'),
                    selected: _targetScans == option,
                    onSelected: (_) => setState(() => _targetScans = option),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _sheet.length >= _minSheetCodes ? _startRun : null,
              icon: const Icon(Icons.play_arrow),
              label: Text(
                _sheet.length >= _minSheetCodes
                    ? 'Start run'
                    : 'Need $_minSheetCodes codes',
              ),
            ),
          ] else ...[
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() => _phase = SheetPhase.register),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to register'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => setState(_nextTarget),
                  icon: const Icon(Icons.skip_next),
                  label: const Text('Skip'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          ReportCard(report: _report),
        ],
      ),
    );
  }
}
