import 'package:flutter/material.dart';

import '../demo_settings.dart';
import '../harness/dense_sheet_page.dart';
import '../harness/mount_cycle_page.dart';
import '../harness/stress_harness_page.dart';
import '../harness/validate_soak_page.dart';

/// Index of the measurement harnesses behind the release gates.
class TestingPage extends StatelessWidget {
  const TestingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = DemoSettingsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Testing & measurement')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Each harness runs against the current configuration and produces a '
            'copyable report. Every one is also reachable unattended with '
            '--dart-define=HARNESS_AUTORUN.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _HarnessTile(
            icon: Icons.speed_outlined,
            title: 'Scan soak',
            subtitle: 'Sustained scanning: throughput, frame time, memory',
            autorun: 'soak',
            builder: () => StressHarnessPage(config: settings.buildConfig()),
          ),
          _HarnessTile(
            icon: Icons.repeat,
            title: 'Mount / unmount cycles',
            subtitle: 'Builds and tears down the platform view N times',
            autorun: 'cycles',
            builder: () => MountCyclePage(config: settings.buildConfig()),
          ),
          _HarnessTile(
            icon: Icons.fact_check_outlined,
            title: 'Validate soak',
            subtitle: 'N accept/reject cycles: stalls and leaked duplicates',
            autorun: 'validate-soak',
            builder: () => ValidateSoakPage(
              config: settings.buildConfig(),
              widgetConfig: settings.buildWidgetConfig(),
            ),
          ),
          _HarnessTile(
            icon: Icons.grid_on,
            title: 'Dense sheet accuracy',
            subtitle: 'Aim at a named code; scores wrong-code reads',
            autorun: 'dense-sheet',
            builder: () => DenseSheetPage(
              config: settings.buildConfig(),
              widgetConfig: settings.buildWidgetConfig(),
            ),
          ),
        ],
      ),
    );
  }
}

class _HarnessTile extends StatelessWidget {
  const _HarnessTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.autorun,
    required this.builder,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String autorun;
  final Widget Function() builder;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle),
            Text(
              'HARNESS_AUTORUN=$autorun',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => builder())),
      ),
    );
  }
}
