import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner_sdk/flutter_barcode_scanner_sdk.dart';

import '../widgets/common.dart';

/// Validate-loop soak for the release gate.
///
/// Holds one barcode in frame and lets the scan → validate → accept/reject loop
/// run for N cycles, alternating the verdict. It measures the two ways the loop
/// can go wrong over a long run: it can stop producing results (a stall), or it
/// can decide the same value twice inside the duplicate window (a leaked
/// duplicate).
///
/// Gate: 1000 cycles, zero stalls, zero cooldown violations.
class ValidateSoakPage extends StatefulWidget {
  const ValidateSoakPage({
    super.key,
    required this.config,
    required this.widgetConfig,
    this.autoStart = false,
  });

  /// Scanner configuration used for the run.
  final FlutterBarcodeScannerConfig config;

  /// Widget configuration, which carries the duplicate cooldown being measured.
  final FlutterBarcodeScannerWidgetConfig widgetConfig;

  /// Starts without waiting for a tap and prints the report to the console.
  ///
  /// Set by `--dart-define=HARNESS_AUTORUN=validate-soak`, which is how this
  /// runs on a physical iPhone where taps cannot be injected.
  final bool autoStart;

  @override
  State<ValidateSoakPage> createState() => _ValidateSoakPageState();
}

class _ValidateSoakPageState extends State<ValidateSoakPage> {
  static const _cycleOptions = <int>[50, 250, 1000];

  /// How long the loop may go without deciding anything before it counts as a
  /// stall. Generous: a hand holding a phone drifts.
  static const _stallTimeout = Duration(seconds: 6);

  final FlutterBarcodeScannerController _controller =
      FlutterBarcodeScannerController();
  final List<int> _intervalsMs = <int>[];
  final Map<String, DateTime> _lastDecidedAt = <String, DateTime>{};

  int _targetCycles = 1000;
  int _cycles = 0;
  int _accepted = 0;
  int _rejected = 0;
  int _stalls = 0;
  int _cooldownViolations = 0;
  bool _isRunning = false;
  bool _acceptNext = true;
  DateTime? _startedAt;
  DateTime? _finishedAt;
  DateTime? _lastDecisionAt;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    if (_isRunning) {
      return;
    }
    setState(() {
      _intervalsMs.clear();
      _lastDecidedAt.clear();
      _cycles = 0;
      _accepted = 0;
      _rejected = 0;
      _stalls = 0;
      _cooldownViolations = 0;
      _acceptNext = true;
      _isRunning = true;
      _startedAt = DateTime.now();
      _finishedAt = null;
      _lastDecisionAt = DateTime.now();
    });
    _armWatchdog();
  }

  void _stop() {
    if (!_isRunning) {
      return;
    }
    _watchdog?.cancel();
    setState(() {
      _isRunning = false;
      _finishedAt = DateTime.now();
    });
    _emitReport();
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(_stallTimeout, (_) {
      if (!_isRunning) {
        return;
      }
      final last = _lastDecisionAt;
      if (last != null &&
          DateTime.now().difference(last) >= _stallTimeout &&
          mounted) {
        setState(() {
          _stalls += 1;
          _lastDecisionAt = DateTime.now();
        });
      }
    });
  }

  Future<ScanDecision> _validate(FlutterBarcodeScanResult result) async {
    if (!_isRunning) {
      return const ScanDecision.reject(message: 'idle');
    }

    final now = DateTime.now();
    final previous = _lastDecidedAt[result.rawValue];
    final cooldown = widget.widgetConfig.duplicateScanCooldown;
    if (previous != null &&
        cooldown > Duration.zero &&
        now.difference(previous) < cooldown) {
      _cooldownViolations += 1;
    }
    _lastDecidedAt[result.rawValue] = now;

    final last = _lastDecisionAt;
    if (last != null) {
      _intervalsMs.add(now.difference(last).inMilliseconds);
    }
    _lastDecisionAt = now;

    final accept = _acceptNext;
    _acceptNext = !_acceptNext;
    _cycles += 1;
    if (accept) {
      _accepted += 1;
    } else {
      _rejected += 1;
    }

    if (_cycles >= _targetCycles) {
      // Finish after this decision so the last cycle is counted.
      scheduleMicrotask(_stop);
    } else if (mounted) {
      setState(() {});
    }

    return accept
        ? const ScanDecision.accept(message: 'accepted')
        : const ScanDecision.reject(message: 'rejected');
  }

  void _emitReport() {
    debugPrint('===HARNESS-REPORT-BEGIN===');
    for (final line in _report.split('\n')) {
      debugPrint(line);
    }
    debugPrint('===HARNESS-REPORT-END===');
  }

  String get _report {
    final sorted = List<int>.from(_intervalsMs)..sort();
    final elapsed = _startedAt == null
        ? Duration.zero
        : (_finishedAt ?? DateTime.now()).difference(_startedAt!);
    final buffer = StringBuffer()
      ..writeln('validate-soak')
      ..writeln('target cycles      : $_targetCycles')
      ..writeln('cycles completed   : $_cycles')
      ..writeln('accepted / rejected: $_accepted / $_rejected')
      ..writeln('stalls (> ${_stallTimeout.inSeconds}s idle): $_stalls')
      ..writeln('cooldown violations: $_cooldownViolations')
      ..writeln(
        'duplicate cooldown : '
        '${widget.widgetConfig.duplicateScanCooldown.inMilliseconds} ms',
      )
      ..writeln('elapsed            : ${elapsed.inSeconds}s');
    if (sorted.isNotEmpty) {
      buffer
        ..writeln('interval min       : ${sorted.first} ms')
        ..writeln('interval median    : ${sorted[sorted.length ~/ 2]} ms')
        ..writeln('interval max       : ${sorted.last} ms');
    }
    buffer.writeln(
      'gate               : '
      '${_cycles >= _targetCycles && _stalls == 0 && _cooldownViolations == 0 ? 'PASS' : 'not met'}',
    );
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Validate soak')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Hold one barcode steadily in frame. The loop alternates accept and '
            'reject on every decision.',
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 260,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: FlutterBarcodeScannerView(
                controller: _controller,
                config: widget.config,
                widgetConfig: widget.widgetConfig,
                autoPauseOnScan: false,
                onScanValidate: _validate,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final option in _cycleOptions)
                ChoiceChip(
                  label: Text('$option'),
                  selected: _targetCycles == option,
                  onSelected: _isRunning
                      ? null
                      : (_) => setState(() => _targetCycles = option),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _isRunning ? _stop : _start,
                icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
                label: Text(_isRunning ? 'Stop' : 'Start'),
              ),
              const SizedBox(width: 12),
              Text('$_cycles / $_targetCycles'),
            ],
          ),
          const SizedBox(height: 16),
          ReportCard(report: _report),
        ],
      ),
    );
  }
}
