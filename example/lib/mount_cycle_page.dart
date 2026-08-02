import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_barcode_scanner_sdk/flutter_barcode_scanner_sdk.dart';

/// Mount/unmount cycler for the embedded scanner.
///
/// The release gate asks for no leaked detectors across 50 mount/unmount
/// cycles. Each cycle builds a fresh platform view with a fresh controller and
/// tears it down, which is what exercises native scanner creation and disposal.
///
/// No barcode needs to be in frame: detectors are created when the camera
/// starts, regardless of whether anything is decoded.
class MountCyclePage extends StatefulWidget {
  const MountCyclePage({
    super.key,
    required this.config,
    this.autoStart = false,
  });

  /// Scanner configuration to mount each cycle.
  final FlutterBarcodeScannerConfig config;

  /// Starts the run without waiting for a tap, and prints the report to the
  /// console when it finishes.
  ///
  /// Set by `--dart-define=HARNESS_AUTORUN=cycles`, which is how this runs on a
  /// physical iPhone: taps cannot be injected there, so the run has to drive
  /// itself and report over the log.
  final bool autoStart;

  @override
  State<MountCyclePage> createState() => _MountCyclePageState();
}

/// How long each cycle keeps the scanner mounted.
enum CycleDwell {
  /// Unmount as soon as the native scanner reports `running`.
  untilRunning,

  /// Unmount after a fixed delay, which can land mid-initialization — the
  /// window most likely to leave a detector unclosed.
  fixedShort,
}

class _MountCyclePageState extends State<MountCyclePage> {
  static const _cycleOptions = <int>[10, 25, 50, 100];
  static const _fixedDwell = Duration(milliseconds: 250);
  static const _runningTimeout = Duration(seconds: 8);
  static const _settleAfterUnmount = Duration(milliseconds: 150);

  final List<int> _rssPerCycle = <int>[];
  final Map<String, int> _errorCounts = <String, int>{};
  final Set<String> _statesSeen = <String>{};

  FlutterBarcodeScannerController? _controller;
  StreamSubscription<FlutterBarcodeScannerViewState>? _stateSubscription;
  StreamSubscription<PlatformException>? _errorSubscription;
  Completer<void>? _runningCompleter;

  int _targetCycles = 50;
  int _passNumber = 0;
  int _cyclesCompleted = 0;
  int _timedOutCycles = 0;
  int _baselineRss = 0;
  CycleDwell _dwell = CycleDwell.untilRunning;
  bool _isRunning = false;
  bool _isScannerMounted = false;
  bool _stopRequested = false;
  DateTime? _startedAt;
  DateTime? _finishedAt;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runAutoPasses());
    }
  }

  /// Runs the cycle set twice and reports each pass separately.
  ///
  /// The second pass starts from an already-warm camera stack, so comparing the
  /// two separates one-time warm-up from genuine per-cycle retention. A single
  /// pass cannot tell those apart.
  Future<void> _runAutoPasses() async {
    await _start();
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted) {
      await _start();
    }
  }

  @override
  void dispose() {
    _stopRequested = true;
    _stateSubscription?.cancel();
    _errorSubscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_isRunning) {
      return;
    }
    setState(() {
      _rssPerCycle.clear();
      _errorCounts.clear();
      _statesSeen.clear();
      _cyclesCompleted = 0;
      _timedOutCycles = 0;
      _stopRequested = false;
      _isRunning = true;
      _finishedAt = null;
      _startedAt = DateTime.now();
      _baselineRss = ProcessInfo.currentRss;
      _passNumber += 1;
    });

    for (var cycle = 0; cycle < _targetCycles; cycle++) {
      if (_stopRequested || !mounted) {
        break;
      }
      await _runOneCycle(cycle);
      _rssPerCycle.add(ProcessInfo.currentRss);
      _cyclesCompleted += 1;
      if (mounted) {
        setState(() {});
      }
    }

    if (mounted) {
      setState(() {
        _isRunning = false;
        _finishedAt = DateTime.now();
      });
    }
    if (widget.autoStart) {
      debugPrint('===HARNESS-REPORT-BEGIN===');
      for (final line in _report.split('\n')) {
        debugPrint(line);
      }
      debugPrint('===HARNESS-REPORT-END===');
    }
  }

  Future<void> _runOneCycle(int cycle) async {
    final controller = FlutterBarcodeScannerController();
    _controller = controller;
    _runningCompleter = Completer<void>();

    _stateSubscription = controller.state.listen((state) {
      _statesSeen.add(state.name);
      if (state == FlutterBarcodeScannerViewState.running &&
          _runningCompleter?.isCompleted == false) {
        _runningCompleter?.complete();
      }
    });
    _errorSubscription = controller.errors.listen((error) {
      _errorCounts.update(error.code, (count) => count + 1, ifAbsent: () => 1);
    });

    setState(() => _isScannerMounted = true);

    switch (_dwell) {
      case CycleDwell.untilRunning:
        try {
          await _runningCompleter!.future.timeout(_runningTimeout);
        } on TimeoutException {
          _timedOutCycles += 1;
        }
      case CycleDwell.fixedShort:
        await Future<void>.delayed(_fixedDwell);
    }

    if (!mounted) {
      return;
    }
    setState(() => _isScannerMounted = false);
    // Let Flutter tear the platform view down before releasing the controller,
    // so dispose runs against a detached view rather than a live one.
    await Future<void>.delayed(_settleAfterUnmount);

    await _stateSubscription?.cancel();
    await _errorSubscription?.cancel();
    _stateSubscription = null;
    _errorSubscription = null;
    await controller.dispose();
    _controller = null;
  }

  void _stop() => setState(() => _stopRequested = true);

  int get _lastRss => _rssPerCycle.isEmpty ? 0 : _rssPerCycle.last;

  int get _peakRss =>
      _rssPerCycle.isEmpty ? 0 : _rssPerCycle.reduce((a, b) => a > b ? a : b);

  /// Mean RSS growth per cycle — the number that separates a leak from noise.
  double get _driftPerCycle {
    if (_rssPerCycle.length < 2) {
      return 0;
    }
    return (_lastRss - _baselineRss) / _rssPerCycle.length;
  }

  Duration get _elapsed {
    final startedAt = _startedAt;
    if (startedAt == null) {
      return Duration.zero;
    }
    return (_finishedAt ?? DateTime.now()).difference(startedAt);
  }

  String get _report {
    final buffer = StringBuffer()
      ..writeln('flutter_barcode_scanner_sdk — mount/unmount cycles')
      ..writeln('platform: ${Platform.operatingSystem} '
          '${Platform.operatingSystemVersion}')
      ..writeln('pass: $_passNumber${_passNumber > 1 ? " (warm start)" : ""}')
      ..writeln('dwell: ${_dwell == CycleDwell.untilRunning ? "until running" : "fixed ${_fixedDwell.inMilliseconds}ms"}')
      ..writeln('')
      ..writeln('cycles completed: $_cyclesCompleted / $_targetCycles')
      ..writeln('elapsed: ${_elapsed.inSeconds}s')
      ..writeln('cycles that never reached running: $_timedOutCycles')
      ..writeln('states seen: ${_statesSeen.join(", ")}')
      ..writeln('')
      ..writeln('memory (process RSS)')
      ..writeln('  baseline: ${_formatBytes(_baselineRss)}')
      ..writeln('  final:    ${_formatBytes(_lastRss)}')
      ..writeln('  peak:     ${_formatBytes(_peakRss)}')
      ..writeln('  drift:    ${_formatBytes(_lastRss - _baselineRss)} total, '
          '${(_driftPerCycle / 1024).toStringAsFixed(1)} KB/cycle')
      ..writeln('');
    if (_errorCounts.isEmpty) {
      buffer.writeln('errors: none');
    } else {
      buffer.writeln('errors');
      for (final entry in _errorCounts.entries) {
        buffer.writeln('  ${entry.key}: ${entry.value}');
      }
    }
    return buffer.toString();
  }

  static String _formatBytes(int bytes) {
    final sign = bytes < 0 ? '−' : '';
    return '$sign${(bytes.abs() / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _copyReport() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _report));
    messenger.showSnackBar(
      const SnackBar(content: Text('Report copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Mount / unmount cycles')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Mounts and unmounts the embedded scanner repeatedly to check that '
            'native detectors are closed. No barcode needs to be in frame.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: _isScannerMounted
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: FlutterBarcodeScannerView(
                      key: ValueKey<int>(_cyclesCompleted),
                      config: widget.config,
                      controller: _controller,
                      autoStart: true,
                      autoPauseOnScan: false,
                    ),
                  )
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Center(child: Text('unmounted')),
                  ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Cycles'),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 16),
                  const Text('Dwell'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Until running'),
                        selected: _dwell == CycleDwell.untilRunning,
                        onSelected: _isRunning
                            ? null
                            : (_) => setState(
                                () => _dwell = CycleDwell.untilRunning,
                              ),
                      ),
                      ChoiceChip(
                        label: const Text('Fixed 250ms'),
                        selected: _dwell == CycleDwell.fixedShort,
                        onSelected: _isRunning
                            ? null
                            : (_) =>
                                  setState(() => _dwell = CycleDwell.fixedShort),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isRunning ? null : _start,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start cycles'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isRunning ? _stop : null,
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_startedAt != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Report',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _copyReport,
                          icon: const Icon(Icons.copy_all_outlined),
                          label: const Text('Copy'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _report,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
