import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner_sdk/flutter_barcode_scanner_sdk.dart';

import '../demo_settings.dart';
import '../widgets/common.dart';

/// Shows the five-state camera-permission contract and the two ways out of a
/// refusal: ask again, or send the user to Settings.
class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  FlutterBarcodePermissionStatus? _status;
  bool _busy = false;
  bool _customBuilder = false;
  bool _showScanner = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    final status = await FlutterBarcodeScanner.checkCameraPermission();
    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
      _busy = false;
    });
  }

  Future<void> _request() async {
    setState(() => _busy = true);
    final status = await FlutterBarcodeScanner.requestCameraPermission();
    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = DemoSettingsScope.of(context);
    final status = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('Permissions')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: 'Current status',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _StatusChip(status: status),
                    const SizedBox(width: 12),
                    if (_busy)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (status != null) ...[
                  ConfigLine(label: 'isGranted', value: '${status.isGranted}'),
                  ConfigLine(
                    label: 'canRequest',
                    value: '${status.canRequest}',
                  ),
                  ConfigLine(
                    label: 'requiresSettings',
                    value: '${status.requiresSettings}',
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _check,
                      icon: const Icon(Icons.refresh),
                      label: const Text('checkCameraPermission'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _busy || status?.canRequest == false
                          ? null
                          : _request,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('requestCameraPermission'),
                    ),
                    OutlinedButton.icon(
                      onPressed: FlutterBarcodeScanner.openAppSettings,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('openAppSettings'),
                    ),
                  ],
                ),
                if (status?.canRequest == false)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Requesting again would not prompt — the button is '
                      'disabled rather than pretending to ask.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'The five states',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in _stateNotes.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.key.name,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        Text(
                          entry.value,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 24),
                Text(
                  'Platform differences',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'iOS never reports denied — a refusal there is already '
                  'permanent, so it comes back as permanentlyDenied. Android '
                  'has no API for "never asked", so notDetermined is inferred '
                  'from whether this app has requested before.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Running on ${Platform.isIOS ? 'iOS' : 'Android'}.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'How the scanner shows it',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The embedded view renders a permission screen itself. Deny '
                  'access, then reopen this page to see it.',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _showScanner,
                  title: const Text('Show embedded scanner'),
                  onChanged: (v) => setState(() => _showScanner = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _customBuilder,
                  title: const Text('Custom permissionBuilder'),
                  subtitle: const Text('Replaces the built-in screen'),
                  onChanged: (v) => setState(() => _customBuilder = v),
                ),
                if (_showScanner) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 280,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: FlutterBarcodeScannerView(
                        config: settings.buildConfig(),
                        widgetConfig: settings.buildWidgetConfig(),
                        autoStart: settings.autoStart,
                        autoPauseOnScan: settings.autoPauseOnScan,
                        permissionBuilder: _customBuilder
                            ? _buildPermissionScreen
                            : null,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionScreen(
    BuildContext context,
    FlutterBarcodePermissionStatus status,
    VoidCallback retry,
  ) {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white70,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                'Camera blocked (${status.name})',
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              if (status.canRequest)
                FilledButton(onPressed: retry, child: const Text('Ask again'))
              else
                FilledButton(
                  onPressed: FlutterBarcodeScanner.openAppSettings,
                  child: const Text('Open Settings'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

const Map<FlutterBarcodePermissionStatus, String> _stateNotes = {
  FlutterBarcodePermissionStatus.granted: 'The camera can be used.',
  FlutterBarcodePermissionStatus.denied:
      'Refused, but asking again still prompts. Android only.',
  FlutterBarcodePermissionStatus.permanentlyDenied:
      'Refused for good. Only Settings can grant it.',
  FlutterBarcodePermissionStatus.restricted:
      'A device policy forbids the camera. iOS only, and the user cannot '
      'change it.',
  FlutterBarcodePermissionStatus.notDetermined: 'Never asked.',
};

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final FlutterBarcodePermissionStatus? status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (status == null) {
      return const Chip(label: Text('checking…'));
    }
    final color = status!.isGranted
        ? Colors.green
        : status!.requiresSettings
        ? scheme.error
        : Colors.orange;
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: 6),
      label: Text(status!.name),
    );
  }
}
