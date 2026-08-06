import 'package:flutter/material.dart';

import 'configuration_page.dart';
import 'embedded_page.dart';
import 'full_screen_page.dart';
import 'permissions_page.dart';
import 'testing_page.dart';
import 'validate_loop_page.dart';

/// The hub. Every feature has one entry, described in a line.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Barcode Scanner SDK')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Destination(
            icon: Icons.fullscreen,
            title: 'Full-screen scanner',
            subtitle: 'Native scanner, returns one result',
            page: FullScreenPage(),
          ),
          const _Destination(
            icon: Icons.crop_free,
            title: 'Embedded scanner',
            subtitle: 'Preview inside a Flutter layout, driven by a controller',
            page: EmbeddedPage(),
          ),
          const _Destination(
            icon: Icons.fact_check_outlined,
            title: 'Validate loop',
            subtitle: 'Scan, check, accept or reject, resume',
            badge: 'new',
            page: ValidateLoopPage(),
          ),
          const _Destination(
            icon: Icons.lock_outline,
            title: 'Permissions',
            subtitle: 'Five states, retry, and the route to Settings',
            badge: 'new',
            page: PermissionsPage(),
          ),
          const Divider(height: 32),
          const _Destination(
            icon: Icons.tune,
            title: 'Configuration',
            subtitle: 'Formats, scan window, feedback, chrome, strings',
            page: ConfigurationPage(),
          ),
          const _Destination(
            icon: Icons.science_outlined,
            title: 'Testing & measurement',
            subtitle: 'Soaks and accuracy runs that gate a release',
            page: TestingPage(),
          ),
        ],
      ),
    );
  }
}

class _Destination extends StatelessWidget {
  const _Destination({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.page,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget page;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: scheme.secondaryContainer,
          child: Icon(icon, color: scheme.onSecondaryContainer),
        ),
        title: Row(
          children: [
            Flexible(child: Text(title)),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(color: scheme.onPrimary, fontSize: 11),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => page)),
      ),
    );
  }
}
