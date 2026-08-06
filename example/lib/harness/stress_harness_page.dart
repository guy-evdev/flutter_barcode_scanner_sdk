import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_barcode_scanner_sdk/flutter_barcode_scanner_sdk.dart';

/// Sustained-scanning harness used as the release gate from 0.2.1 onwards.
///
/// Point the scanner at one printed barcode and let it run. The loop is the
/// continuous-entry-scanning workload: native auto-pauses on every result and
/// the harness immediately resumes, so nothing throttles throughput.
///
/// Reports scans completed, peak and steady memory, dropped frames, the decode
/// latency distribution, and the camera restart count.
class StressHarnessPage extends StatefulWidget {
  const StressHarnessPage({
    super.key,
    required this.config,
    this.autoStart = false,
  });

  /// Scanner configuration to soak, so the harness measures the real setup.
  final FlutterBarcodeScannerConfig config;

  /// Starts the soak without waiting for a tap, and prints the report to the
  /// console when it finishes.
  ///
  /// Set by `--dart-define=HARNESS_AUTORUN=soak`, which is how this runs on a
  /// physical iPhone: taps cannot be injected there, so the run has to drive
  /// itself and report over the log. A barcode still has to be held in frame.
  final bool autoStart;

  @override
  State<StressHarnessPage> createState() => _StressHarnessPageState();
}

class _StressHarnessPageState extends State<StressHarnessPage> {
  static const _targetOptions = <int>[50, 100, 500, 1000];
  static const _memorySampleInterval = Duration(milliseconds: 500);

  final FlutterBarcodeScannerController _controller =
      FlutterBarcodeScannerController();

  final List<int> _latenciesMs = <int>[];
  final List<int> _rssSamples = <int>[];
  final Map<String, int> _errorCounts = <String, int>{};

  StreamSubscription<FlutterBarcodeScannerViewState>? _stateSubscription;
  StreamSubscription<PlatformException>? _errorSubscription;
  Timer? _memoryTimer;

  int _targetScans = 1000;
  int _interScanDelayMs = 0;
  int _scansCompleted = 0;
  int _cameraRestarts = 0;
  int _totalFrames = 0;
  int _droppedFrames = 0;
  int _buildJankFrames = 0;
  int _rasterJankFrames = 0;
  double _frameBudgetMs = 1000 / 60;
  bool _isRunning = false;
  bool _hasReachedRunningOnce = false;
  DateTime? _startedAt;
  DateTime? _finishedAt;
  DateTime? _lastResumeAt;
  String? _lastRawValue;

  @override
  void initState() {
    super.initState();
    _stateSubscription = _controller.state.listen(_onStateChanged);
    _errorSubscription = _controller.errors.listen(_onError);
    if (widget.autoStart) {
      // Give the camera a moment to reach running before the first resume, so
      // the first latency sample is not dominated by session startup.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (mounted) {
          await _start();
        }
      });
    }
  }

  @override
  void dispose() {
    _memoryTimer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _stateSubscription?.cancel();
    _errorSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- metrics

  /// Counts frames whose build or raster phase overran the frame budget.
  ///
  /// Deliberately not `totalSpan`: that spans vsync to raster completion and
  /// includes time the frame spent waiting, so it reports almost every frame as
  /// dropped. Build and raster durations are the actual work, and separating
  /// them matters here — raster jank is what an embedded platform view causes.
  void _onFrameTimings(List<FrameTiming> timings) {
    if (!_isRunning) {
      return;
    }
    for (final timing in timings) {
      final buildMs = timing.buildDuration.inMicroseconds / 1000;
      final rasterMs = timing.rasterDuration.inMicroseconds / 1000;
      final buildOverran = buildMs > _frameBudgetMs;
      final rasterOverran = rasterMs > _frameBudgetMs;
      if (buildOverran) {
        _buildJankFrames += 1;
      }
      if (rasterOverran) {
        _rasterJankFrames += 1;
      }
      if (buildOverran || rasterOverran) {
        _droppedFrames += 1;
      }
    }
    _totalFrames += timings.length;
  }

  void _onStateChanged(FlutterBarcodeScannerViewState state) {
    if (state == FlutterBarcodeScannerViewState.running) {
      _hasReachedRunningOnce = true;
    }
    // A rebind after the scanner has already run once is a restart: it is the
    // signal that the camera was torn down and brought back mid-soak.
    if (state == FlutterBarcodeScannerViewState.initializing &&
        _hasReachedRunningOnce &&
        _isRunning) {
      _cameraRestarts += 1;
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _onError(PlatformException error) {
    _errorCounts.update(error.code, (count) => count + 1, ifAbsent: () => 1);
    if (mounted) {
      setState(() {});
    }
  }

  void _sampleMemory(Timer _) {
    _rssSamples.add(ProcessInfo.currentRss);
    if (mounted) {
      setState(() {});
    }
  }

  // ------------------------------------------------------------------- loop

  Future<void> _start() async {
    if (_isRunning) {
      return;
    }
    final refreshRate = WidgetsBinding
        .instance
        .platformDispatcher
        .views
        .first
        .display
        .refreshRate;
    setState(() {
      _latenciesMs.clear();
      _rssSamples.clear();
      _errorCounts.clear();
      _scansCompleted = 0;
      _cameraRestarts = 0;
      _totalFrames = 0;
      _droppedFrames = 0;
      _buildJankFrames = 0;
      _rasterJankFrames = 0;
      _frameBudgetMs = refreshRate.isFinite && refreshRate > 0
          ? 1000 / refreshRate
          : 1000 / 60;
      _hasReachedRunningOnce = false;
      _lastRawValue = null;
      _finishedAt = null;
      _startedAt = DateTime.now();
      _isRunning = true;
    });

    _rssSamples.add(ProcessInfo.currentRss);
    _memoryTimer = Timer.periodic(_memorySampleInterval, _sampleMemory);
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);

    await _resumeForNextScan();
  }

  void _stop() {
    if (!_isRunning) {
      return;
    }
    _memoryTimer?.cancel();
    _memoryTimer = null;
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    setState(() {
      _isRunning = false;
      _finishedAt = DateTime.now();
    });
    if (widget.autoStart) {
      debugPrint('===HARNESS-REPORT-BEGIN===');
      for (final line in _report.split('\n')) {
        debugPrint(line);
      }
      debugPrint('===HARNESS-REPORT-END===');
    }
  }

  Future<void> _resumeForNextScan() async {
    if (_interScanDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: _interScanDelayMs));
    }
    if (!_isRunning || !mounted) {
      return;
    }
    try {
      await _controller.resumeDetection();
    } on PlatformException catch (error) {
      _onError(error);
      return;
    } on StateError {
      // The view was detached while the soak was running.
      return;
    }
    _lastResumeAt = DateTime.now();
  }

  void _onScan(FlutterBarcodeScanResult result) {
    if (!_isRunning || !result.isBarcode) {
      return;
    }
    final resumedAt = _lastResumeAt;
    if (resumedAt != null) {
      _latenciesMs.add(DateTime.now().difference(resumedAt).inMilliseconds);
    }
    _scansCompleted += 1;
    _lastRawValue = result.rawValue;
    setState(() {});

    if (_scansCompleted >= _targetScans) {
      _stop();
      return;
    }
    unawaited(_resumeForNextScan());
  }

  // ---------------------------------------------------------------- report

  int get _peakRss => _rssSamples.isEmpty ? 0 : _rssSamples.reduce(max);

  int get _baselineRss => _rssSamples.isEmpty ? 0 : _rssSamples.first;

  /// Median of the final quarter of samples — the level memory settled at.
  ///
  /// A steady value close to the baseline is the flat curve the release gate
  /// asks for; a steady value tracking the peak means the soak leaked.
  int get _steadyRss {
    if (_rssSamples.isEmpty) {
      return 0;
    }
    final tailStart = (_rssSamples.length * 3) ~/ 4;
    final tail = _rssSamples.sublist(
      tailStart.clamp(0, _rssSamples.length - 1),
    );
    return _median(tail);
  }

  Duration get _elapsed {
    final startedAt = _startedAt;
    if (startedAt == null) {
      return Duration.zero;
    }
    return (_finishedAt ?? DateTime.now()).difference(startedAt);
  }

  double get _scansPerMinute {
    final seconds = _elapsed.inMilliseconds / 1000;
    if (seconds <= 0 || _scansCompleted == 0) {
      return 0;
    }
    return _scansCompleted / seconds * 60;
  }

  String get _report {
    final buffer = StringBuffer()
      ..writeln('flutter_barcode_scanner_sdk — stress harness')
      ..writeln(
        'platform: ${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion}',
      )
      ..writeln(
        'build mode: ${kDebugMode ? "DEBUG — NOT GATE-VALID" : (kProfileMode ? "profile" : "release")}',
      )
      ..writeln(
        'target: $_targetScans scans, '
        'inter-scan delay ${_interScanDelayMs}ms',
      )
      ..writeln('')
      ..writeln('scans completed: $_scansCompleted / $_targetScans')
      ..writeln(
        'elapsed: ${_formatDuration(_elapsed)} '
        '(${_scansPerMinute.toStringAsFixed(1)} scans/min)',
      )
      ..writeln('camera restarts: $_cameraRestarts')
      ..writeln('')
      ..writeln('memory (process RSS)')
      ..writeln('  baseline: ${_formatBytes(_baselineRss)}')
      ..writeln('  peak:     ${_formatBytes(_peakRss)}')
      ..writeln(
        '  steady:   ${_formatBytes(_steadyRss)} '
        '(${_formatSignedBytes(_steadyRss - _baselineRss)} vs baseline)',
      )
      ..writeln(
        '  samples:  ${_rssSamples.length} '
        '@ ${_memorySampleInterval.inMilliseconds}ms',
      )
      ..writeln('')
      ..writeln('frames')
      ..writeln('  budget:  ${_frameBudgetMs.toStringAsFixed(2)}ms')
      ..writeln('  total:   $_totalFrames')
      ..writeln('  dropped: $_droppedFrames (${_droppedPercent()})')
      ..writeln('    build overruns:  $_buildJankFrames')
      ..writeln('    raster overruns: $_rasterJankFrames')
      ..writeln('')
      ..writeln('decode latency (resume → result)');
    if (_latenciesMs.isEmpty) {
      buffer.writeln('  no samples');
    } else {
      buffer
        ..writeln('  min:  ${_percentile(0)}ms')
        ..writeln('  p50:  ${_percentile(50)}ms')
        ..writeln('  p90:  ${_percentile(90)}ms')
        ..writeln('  p99:  ${_percentile(99)}ms')
        ..writeln('  max:  ${_percentile(100)}ms')
        ..writeln('  mean: ${_mean().toStringAsFixed(1)}ms');
    }
    buffer.writeln('');
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

  int _percentile(int percentile) {
    if (_latenciesMs.isEmpty) {
      return 0;
    }
    final sorted = List<int>.from(_latenciesMs)..sort();
    final index = ((percentile / 100) * (sorted.length - 1)).round();
    return sorted[index.clamp(0, sorted.length - 1)];
  }

  double _mean() {
    if (_latenciesMs.isEmpty) {
      return 0;
    }
    return _latenciesMs.reduce((a, b) => a + b) / _latenciesMs.length;
  }

  String _droppedPercent() {
    if (_totalFrames == 0) {
      return '0.0%';
    }
    return '${(_droppedFrames / _totalFrames * 100).toStringAsFixed(1)}%';
  }

  static int _median(List<int> values) {
    if (values.isEmpty) {
      return 0;
    }
    final sorted = List<int>.from(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[middle];
    }
    return ((sorted[middle - 1] + sorted[middle]) / 2).round();
  }

  static int max(int a, int b) => a > b ? a : b;

  static String _formatBytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  static String _formatSignedBytes(int bytes) {
    final sign = bytes >= 0 ? '+' : '−';
    return '$sign${(bytes.abs() / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  Future<void> _copyReport() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _report));
    messenger.showSnackBar(
      const SnackBar(content: Text('Report copied to clipboard')),
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasRun = _startedAt != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Stress harness')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Point the scanner at one printed barcode and start. Native '
            'auto-pauses on each result and the harness resumes immediately, '
            'so throughput is only limited by the decode path.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 12),
            _buildDebugWarning(scheme),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 260,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: FlutterBarcodeScannerView(
                config: widget.config,
                controller: _controller,
                autoStart: true,
                autoPauseOnScan: true,
                onScan: _onScan,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildControls(context),
          const SizedBox(height: 16),
          if (hasRun) ...[
            _buildLiveStats(scheme),
            const SizedBox(height: 16),
            _buildMemoryCard(scheme),
            const SizedBox(height: 16),
            _buildLatencyCard(scheme),
            const SizedBox(height: 16),
            _buildReportCard(scheme),
          ],
        ],
      ),
    );
  }

  Widget _buildDebugWarning(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Debug build — these numbers do not gate a release. Frame and '
              'latency figures are dominated by the debug interpreter, and '
              'memory carries debug-only allocations. Run the gate with '
              '"flutter run --profile" on a physical device.',
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Target scans'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final option in _targetOptions)
                  ChoiceChip(
                    label: Text('$option'),
                    selected: _targetScans == option,
                    onSelected: _isRunning
                        ? null
                        : (_) => setState(() => _targetScans = option),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Inter-scan delay: ${_interScanDelayMs}ms'),
            Slider(
              value: _interScanDelayMs.toDouble(),
              max: 2000,
              divisions: 20,
              label: '${_interScanDelayMs}ms',
              onChanged: _isRunning
                  ? null
                  : (value) =>
                        setState(() => _interScanDelayMs = value.round()),
            ),
            const Text(
              'Zero is the worst case for memory and GC. Raise it to emulate '
              'an operator’s real cadence.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isRunning ? null : _start,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start soak'),
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
    );
  }

  Widget _buildLiveStats(ColorScheme scheme) {
    final progress = _targetScans == 0
        ? 0.0
        : (_scansCompleted / _targetScans).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _Metric(
                  label: 'Scans',
                  value: '$_scansCompleted / $_targetScans',
                ),
                _Metric(label: 'Elapsed', value: _formatDuration(_elapsed)),
                _Metric(
                  label: 'Rate',
                  value: '${_scansPerMinute.toStringAsFixed(1)}/min',
                ),
                _Metric(label: 'Restarts', value: '$_cameraRestarts'),
                _Metric(
                  label: 'Dropped frames',
                  value: '$_droppedFrames (${_droppedPercent()})',
                ),
                _Metric(
                  label: 'Errors',
                  value: _errorCounts.isEmpty
                      ? 'none'
                      : _errorCounts.entries
                            .map((entry) => '${entry.key}×${entry.value}')
                            .join(', '),
                ),
              ],
            ),
            if (_lastRawValue != null) ...[
              const SizedBox(height: 12),
              Text(
                'Last value: ${_lastRawValue!}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryCard(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Memory (process RSS)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _Metric(label: 'Baseline', value: _formatBytes(_baselineRss)),
                _Metric(label: 'Peak', value: _formatBytes(_peakRss)),
                _Metric(label: 'Steady', value: _formatBytes(_steadyRss)),
                _Metric(
                  label: 'Drift',
                  value: _formatSignedBytes(_steadyRss - _baselineRss),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              width: double.infinity,
              child: CustomPaint(
                painter: _SparklinePainter(
                  samples: _rssSamples,
                  color: scheme.primary,
                  gridColor: scheme.outlineVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'RSS is process-wide and includes native camera buffers, so it '
              'is a proxy rather than a heap measurement. The gate is a flat '
              'curve: steady close to baseline.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLatencyCard(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Decode latency (resume → result)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_latenciesMs.isEmpty)
              const Text('No samples yet.')
            else
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _Metric(label: 'min', value: '${_percentile(0)}ms'),
                  _Metric(label: 'p50', value: '${_percentile(50)}ms'),
                  _Metric(label: 'p90', value: '${_percentile(90)}ms'),
                  _Metric(label: 'p99', value: '${_percentile(99)}ms'),
                  _Metric(label: 'max', value: '${_percentile(100)}ms'),
                  _Metric(
                    label: 'mean',
                    value: '${_mean().toStringAsFixed(1)}ms',
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Text(
              'Measured from the resumeDetection() call to the next result, so '
              'it covers the full round trip, not just native decode.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard(ColorScheme scheme) {
    return Card(
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                _report,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.samples,
    required this.color,
    required this.gridColor,
  });

  final List<int> samples;
  final Color color;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      baseline,
    );

    if (samples.length < 2) {
      return;
    }

    var minValue = samples.first;
    var maxValue = samples.first;
    for (final sample in samples) {
      if (sample < minValue) minValue = sample;
      if (sample > maxValue) maxValue = sample;
    }
    // Keep a floor on the range so a genuinely flat curve renders flat rather
    // than as amplified noise.
    final range = (maxValue - minValue).clamp(1024 * 1024, 1 << 62);

    final path = Path();
    for (var index = 0; index < samples.length; index++) {
      final x = size.width * index / (samples.length - 1);
      final y = size.height - (samples[index] - minValue) / range * size.height;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.samples.length != samples.length ||
      oldDelegate.color != color;
}
