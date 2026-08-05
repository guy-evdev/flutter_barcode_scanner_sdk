import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_barcode_scanner_sdk/flutter_barcode_scanner_sdk.dart';

import '../demo_settings.dart';
import '../widgets/common.dart';

/// The scanner inside a Flutter layout, driven by a controller.
class EmbeddedPage extends StatefulWidget {
  const EmbeddedPage({super.key});

  @override
  State<EmbeddedPage> createState() => _EmbeddedPageState();
}

class _EmbeddedPageState extends State<EmbeddedPage> {
  final FlutterBarcodeScannerController _controller =
      FlutterBarcodeScannerController();
  final List<FlutterBarcodeScanResult> _history = <FlutterBarcodeScanResult>[];

  bool _customOverlay = false;
  bool _customLoading = false;
  bool _customError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _record(FlutterBarcodeScanResult result) {
    setState(() {
      _history.insert(0, result);
      if (_history.length > 8) {
        _history.removeLast();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = DemoSettingsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Embedded scanner')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 340,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: FlutterBarcodeScannerView(
                controller: _controller,
                config: settings.buildConfig(),
                widgetConfig: settings.buildWidgetConfig(),
                autoStart: settings.autoStart,
                autoPauseOnScan: settings.autoPauseOnScan,
                onScan: _record,
                overlayBuilder: _customOverlay ? _buildOverlay : null,
                loadingBuilder: _customLoading ? _buildLoading : null,
                errorBuilder: _customError ? _buildError : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<FlutterBarcodeScannerViewState>(
            valueListenable: _controller.stateListenable,
            builder: (context, state, _) => Row(
              children: [
                Chip(
                  avatar: const Icon(Icons.circle, size: 12),
                  label: Text('state: ${state.name}'),
                ),
                const SizedBox(width: 8),
                Text(
                  'currentState: ${_controller.currentState.name}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Controller',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _controller.startCamera,
                  icon: const Icon(Icons.videocam_outlined),
                  label: const Text('Start'),
                ),
                OutlinedButton.icon(
                  onPressed: _controller.stopCamera,
                  icon: const Icon(Icons.videocam_off_outlined),
                  label: const Text('Stop'),
                ),
                OutlinedButton.icon(
                  onPressed: _controller.pauseDetection,
                  icon: const Icon(Icons.pause_circle_outline),
                  label: const Text('Pause'),
                ),
                OutlinedButton.icon(
                  onPressed: _controller.resumeDetection,
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Resume'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _controller.toggleFlash(),
                  icon: const Icon(Icons.flashlight_on_outlined),
                  label: const Text('Torch'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _controller.switchCamera(),
                  icon: const Icon(Icons.flip_camera_android_outlined),
                  label: const Text('Switch'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Builders',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _customOverlay,
                  title: const Text('overlayBuilder'),
                  subtitle: const Text('Replaces the scan-window treatment'),
                  onChanged: (v) => setState(() => _customOverlay = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _customLoading,
                  title: const Text('loadingBuilder'),
                  subtitle: const Text('Shown while the camera is starting'),
                  onChanged: (v) => setState(() => _customLoading = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _customError,
                  title: const Text('errorBuilder'),
                  subtitle: const Text('Shown when the native side fails'),
                  onChanged: (v) => setState(() => _customError = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Results',
            child: _history.isEmpty
                ? const Text('No scans yet.')
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

  Widget _buildOverlay(
    BuildContext context,
    Rect? scanWindow,
    FlutterBarcodeScannerController controller,
  ) {
    if (scanWindow == null) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fromRect(
            rect: scanWindow,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.cyanAccent, width: 3),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Text(
              'custom overlayBuilder',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.cyanAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading(
    BuildContext context,
    FlutterBarcodeScannerViewState state,
    FlutterBarcodeScannerController controller,
  ) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Text(
          'starting… (${state.name})',
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }

  Widget _buildError(
    BuildContext context,
    PlatformException error,
    FlutterBarcodeScannerController controller,
  ) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error.code, style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: controller.startCamera,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
