import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner_sdk/flutter_barcode_scanner_sdk.dart';

import '../demo_settings.dart';
import '../widgets/common.dart';

/// How the simulated backend answers.
enum VerdictMode { accept, reject, alternate, fail }

/// Demonstrates `onScanValidate` — the scan → validate → accept/reject loop.
///
/// The verdict and the decision latency are both adjustable, because the point
/// of the feature is what happens when a check is slow or fails: the scanner
/// must not double-scan, and must not wedge.
class ValidateLoopPage extends StatefulWidget {
  const ValidateLoopPage({super.key});

  @override
  State<ValidateLoopPage> createState() => _ValidateLoopPageState();
}

class _ValidateLoopPageState extends State<ValidateLoopPage> {
  final FlutterBarcodeScannerController _controller =
      FlutterBarcodeScannerController();
  final List<String> _log = <String>[];

  VerdictMode _mode = VerdictMode.alternate;
  double _delaySeconds = 0.4;
  bool _customFeedback = false;
  int _decided = 0;
  bool _alternateNext = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<ScanDecision> _validate(FlutterBarcodeScanResult result) async {
    if (_delaySeconds > 0) {
      await Future<void>.delayed(
        Duration(milliseconds: (_delaySeconds * 1000).round()),
      );
    }
    if (_mode == VerdictMode.fail) {
      // Thrown on purpose: the scanner reports it, treats the scan as
      // rejected, and carries on rather than stalling.
      throw StateError('simulated backend failure');
    }
    final accept = switch (_mode) {
      VerdictMode.accept => true,
      VerdictMode.reject => false,
      VerdictMode.alternate => _alternateNext,
      VerdictMode.fail => false,
    };
    _alternateNext = !_alternateNext;
    _decided += 1;
    _append('${accept ? 'accept' : 'reject'}  ${result.rawValue}');
    return accept
        ? const ScanDecision.accept(message: 'Accepted')
        : const ScanDecision.reject(message: 'Rejected');
  }

  void _append(String line) {
    if (!mounted) {
      return;
    }
    setState(() {
      _log.insert(0, line);
      if (_log.length > 12) {
        _log.removeLast();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = DemoSettingsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Validate loop')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Return a decision and the scanner runs the loop: it holds detection '
            'while your check runs, shows the outcome, then resumes.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: FlutterBarcodeScannerView(
                controller: _controller,
                config: settings.buildConfig(),
                widgetConfig: settings.buildWidgetConfig(),
                autoStart: settings.autoStart,
                // The loop resumes itself once the decision is shown, which is
                // what continuous entry scanning wants.
                autoPauseOnScan: false,
                onScan: (result) {
                  if (result.isBarcode) {
                    _append('decoded  ${result.rawValue}');
                  }
                },
                onScanValidate: _validate,
                overlayBuilder: _customFeedback ? _buildCustomOverlay : null,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Simulated backend',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LabeledControl(
                  label: 'Verdict',
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final mode in VerdictMode.values)
                        ChoiceChip(
                          label: Text(_modeLabel(mode)),
                          selected: _mode == mode,
                          onSelected: (_) => setState(() => _mode = mode),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SliderField(
                  label: 'Decision delay',
                  value: _delaySeconds,
                  min: 0,
                  max: 3,
                  divisions: 12,
                  format: (v) => '${v.toStringAsFixed(1)} s',
                  onChanged: (v) => setState(() => _delaySeconds = v),
                ),
                if (_mode == VerdictMode.fail)
                  Text(
                    'The validator throws. Expect a rejection, an error in the '
                    'console, and a scanner that keeps working.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _customFeedback,
                  title: const Text('Custom feedback overlay'),
                  subtitle: const Text(
                    'Replaces the built-in banner, driven by '
                    'controller.feedbackListenable',
                  ),
                  onChanged: (v) => setState(() => _customFeedback = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Log  ·  $_decided decided',
            child: _log.isEmpty
                ? const Text('Point the camera at a barcode.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in _log)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            line,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Repeats of the same value inside '
                        '${settings.duplicateScanCooldown.inMilliseconds}ms never reach '
                        '"decoded" — that is duplicateScanCooldown.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomOverlay(
    BuildContext context,
    Rect? scanWindow,
    FlutterBarcodeScannerController controller,
  ) {
    return ValueListenableBuilder<FlutterBarcodeScanFeedback?>(
      valueListenable: controller.feedbackListenable,
      builder: (context, feedback, _) {
        if (feedback == null) {
          return const SizedBox.shrink();
        }
        final accepted = feedback.decision.isAccepted;
        return IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: accepted ? Colors.teal : Colors.deepOrange,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${accepted ? 'OK' : 'NO'} · ${feedback.result.rawValue}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _modeLabel(VerdictMode mode) {
    return switch (mode) {
      VerdictMode.accept => 'Always accept',
      VerdictMode.reject => 'Always reject',
      VerdictMode.alternate => 'Alternate',
      VerdictMode.fail => 'Throw',
    };
  }
}
