import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner_sdk/flutter_barcode_scanner_sdk.dart';

import '../demo_settings.dart';
import '../widgets/common.dart';

/// Every knob, grouped, one group open at a time.
///
/// Changes here apply to every other page, because they all read the same
/// [DemoSettings].
class ConfigurationPage extends StatefulWidget {
  const ConfigurationPage({super.key});

  @override
  State<ConfigurationPage> createState() => _ConfigurationPageState();
}

class _ConfigurationPageState extends State<ConfigurationPage> {
  int _openIndex = 0;

  @override
  Widget build(BuildContext context) {
    final settings = DemoSettingsScope.of(context);
    final groups = <String, Widget>{
      'Formats': _formats(settings),
      'Scanning': _scanning(settings),
      'Scan window': _scanWindow(settings),
      'Aiming': _aiming(settings),
      'Feedback': _feedback(settings),
      'Native chrome': _chrome(settings),
      'Strings & direction': _strings(settings),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Configuration')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (var i = 0; i < groups.length; i++)
            ExpansionTile(
              key: PageStorageKey<int>(i),
              title: Text(groups.keys.elementAt(i)),
              initiallyExpanded: i == _openIndex,
              onExpansionChanged: (open) {
                if (open) {
                  setState(() => _openIndex = i);
                }
              },
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [groups.values.elementAt(i)],
            ),
        ],
      ),
    );
  }

  Widget _formats(DemoSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in FormatPreset.values)
              ChoiceChip(
                label: Text(settings.formatPresetLabel(preset)),
                selected: settings.formatPreset == preset,
                onSelected: (_) =>
                    settings.update(() => settings.formatPreset = preset),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(settings.formatSummary),
      ],
    );
  }

  Widget _scanning(DemoSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.autoStart,
          title: const Text('Auto-start the camera'),
          onChanged: (v) => settings.update(() => settings.autoStart = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.autoPauseOnScan,
          title: const Text('Auto-pause after a result'),
          onChanged: (v) => settings.update(() => settings.autoPauseOnScan = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.keepScreenOn,
          title: const Text('Keep the screen on'),
          subtitle: const Text('While the scanner is running'),
          onChanged: (v) => settings.update(() => settings.keepScreenOn = v),
        ),
        const SizedBox(height: 8),
        SliderField(
          label: 'Duplicate cooldown',
          value: settings.duplicateScanCooldown.inMilliseconds.toDouble(),
          min: 0,
          max: 2000,
          divisions: 20,
          format: (v) => v == 0 ? 'off' : '${v.round()} ms',
          onChanged: (v) => settings.update(
            () => settings.duplicateScanCooldown = Duration(
              milliseconds: v.round(),
            ),
          ),
        ),
        Text(
          'Repeats of the same value inside this window are dropped. A '
          'different code is always reported immediately.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _scanWindow(DemoSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.scanWindowEnabled,
          title: const Text('Enable the scan window'),
          subtitle: const Text('Off scans the whole preview, with no framing'),
          onChanged: (v) =>
              settings.update(() => settings.scanWindowEnabled = v),
        ),
        const SizedBox(height: 8),
        _ShapePreview(
          widthFraction: settings.scanWindowWidthFraction,
          aspectRatio: settings.scanWindowAspectRatio,
          radius: settings.scanWindowCornerRadius,
        ),
        const SizedBox(height: 12),
        SliderField(
          label: 'Width',
          value: settings.scanWindowWidthFraction,
          min: 0.3,
          max: 1,
          divisions: 14,
          format: (v) => '${(v * 100).round()}% of the preview',
          onChanged: (v) =>
              settings.update(() => settings.scanWindowWidthFraction = v),
        ),
        SliderField(
          label: 'Aspect ratio',
          value: settings.scanWindowAspectRatio,
          min: 0.5,
          max: 3,
          divisions: 25,
          format: (v) => '${v.toStringAsFixed(2)} : 1',
          onChanged: (v) =>
              settings.update(() => settings.scanWindowAspectRatio = v),
        ),
        SliderField(
          label: 'Corner radius',
          value: settings.scanWindowCornerRadius,
          min: 0,
          max: 36,
          divisions: 18,
          format: (v) => v.toStringAsFixed(0),
          onChanged: (v) =>
              settings.update(() => settings.scanWindowCornerRadius = v),
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => settings.update(() {
                settings.scanWindowWidthFraction =
                    FlutterBarcodeScannerScanWindow.defaultWidthFraction;
                settings.scanWindowAspectRatio =
                    FlutterBarcodeScannerScanWindow.defaultAspectRatio;
              }),
              child: const Text('Default 3:2'),
            ),
            OutlinedButton(
              onPressed: () => settings.update(() {
                settings.scanWindowWidthFraction = 0.9;
                settings.scanWindowAspectRatio = 4;
              }),
              child: const Text('Wide 1D strip'),
            ),
            OutlinedButton(
              onPressed: () => settings.update(() {
                settings.scanWindowWidthFraction = 0.6;
                settings.scanWindowAspectRatio = 1;
              }),
              child: const Text('Square'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'The window is a share of the preview width at a fixed aspect ratio, '
          'so it is the same shape embedded and full-screen. Fractions on both '
          'axes made it follow whatever it was drawn in.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _aiming(DemoSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LabeledControl(
          label: 'Aim mode',
          child: SegmentedButton<FlutterBarcodeScanAimMode>(
            segments: const [
              ButtonSegment(
                value: FlutterBarcodeScanAimMode.window,
                label: Text('Window'),
              ),
              ButtonSegment(
                value: FlutterBarcodeScanAimMode.crosshair,
                label: Text('Crosshair'),
              ),
            ],
            selected: <FlutterBarcodeScanAimMode>{settings.aimMode},
            onSelectionChanged: (s) =>
                settings.update(() => settings.aimMode = s.first),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          settings.aimMode == FlutterBarcodeScanAimMode.window
              ? 'Any code overlapping the window can be reported; the one '
                    'nearest the centre wins.'
              : 'Only the code under the centre point is reported. Aiming is a '
                    'point, which is what makes a dense sheet selectable.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        SliderField(
          label: 'Confirmation observations',
          value: settings.scanConfirmationFrames.toDouble(),
          min: 1,
          max: 6,
          divisions: 5,
          format: (v) => v == 1 ? '1 (report immediately)' : '${v.round()}',
          onChanged: (v) => settings.update(
            () => settings.scanConfirmationFrames = v.round(),
          ),
        ),
        Text(
          'How many times in a row the same value must be the best candidate '
          'before it is reported. Raising it discards codes caught while '
          'sweeping towards the one you meant, at roughly a frame each.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _feedback(DemoSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.hapticFeedbackOnAccept,
          title: const Text('Haptic on accept'),
          onChanged: (v) =>
              settings.update(() => settings.hapticFeedbackOnAccept = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.soundOnAccept,
          title: const Text('Sound on accept'),
          onChanged: (v) => settings.update(() => settings.soundOnAccept = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.showPauseResumeButton,
          title: const Text('Pause / resume overlay button'),
          onChanged: (v) =>
              settings.update(() => settings.showPauseResumeButton = v),
        ),
        const SizedBox(height: 8),
        SliderField(
          label: 'Feedback duration',
          value: settings.validationFeedbackDuration.inMilliseconds.toDouble(),
          min: 200,
          max: 3000,
          divisions: 14,
          format: (v) => '${v.round()} ms',
          onChanged: (v) => settings.update(
            () => settings.validationFeedbackDuration = Duration(
              milliseconds: v.round(),
            ),
          ),
        ),
        ColorChoices(
          label: 'Paused scan-window border',
          colors: DemoSettings.pausedBorderColors,
          selectedIndex: settings.pausedBorderColorIndex,
          onSelected: (i) =>
              settings.update(() => settings.pausedBorderColorIndex = i),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.autoRequestCameraPermission,
          title: const Text('Auto-request camera permission'),
          subtitle: const Text('Off leaves the prompt to your own code'),
          onChanged: (v) =>
              settings.update(() => settings.autoRequestCameraPermission = v),
        ),
      ],
    );
  }

  Widget _chrome(DemoSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.showFlashButton,
          title: const Text('Flash button'),
          onChanged: (v) => settings.update(() => settings.showFlashButton = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.showCameraSwitchButton,
          title: const Text('Camera switch button'),
          onChanged: (v) =>
              settings.update(() => settings.showCameraSwitchButton = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.initialTorchEnabled,
          title: const Text('Start with the torch on'),
          onChanged: (v) =>
              settings.update(() => settings.initialTorchEnabled = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.statusBarTransparent,
          title: const Text('Transparent status bar'),
          onChanged: (v) =>
              settings.update(() => settings.statusBarTransparent = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.appBarTransparent,
          title: const Text('Transparent app bar'),
          onChanged: (v) =>
              settings.update(() => settings.appBarTransparent = v),
        ),
        const SizedBox(height: 12),
        LabeledControl(
          label: 'Initial camera lens',
          child: SegmentedButton<BarcodeCameraLens>(
            segments: const [
              ButtonSegment(value: BarcodeCameraLens.back, label: Text('Back')),
              ButtonSegment(
                value: BarcodeCameraLens.front,
                label: Text('Front'),
              ),
            ],
            selected: <BarcodeCameraLens>{settings.initialCameraLens},
            onSelectionChanged: (s) =>
                settings.update(() => settings.initialCameraLens = s.first),
          ),
        ),
        const SizedBox(height: 12),
        LabeledControl(
          label: 'Status bar icons',
          child: SegmentedButton<FlutterBarcodeScannerStatusBarIconBrightness>(
            segments: const [
              ButtonSegment(
                value: FlutterBarcodeScannerStatusBarIconBrightness.light,
                label: Text('Light'),
              ),
              ButtonSegment(
                value: FlutterBarcodeScannerStatusBarIconBrightness.dark,
                label: Text('Dark'),
              ),
            ],
            selected: <FlutterBarcodeScannerStatusBarIconBrightness>{
              settings.statusBarIconBrightness,
            },
            onSelectionChanged: (s) => settings.update(
              () => settings.statusBarIconBrightness = s.first,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ColorChoices(
          label: 'App bar colour',
          colors: DemoSettings.appBarColors,
          selectedIndex: settings.appBarColorIndex,
          onSelected: (i) =>
              settings.update(() => settings.appBarColorIndex = i),
        ),
        const SizedBox(height: 12),
        LabeledControl(
          label: 'Overlay intensity',
          child: Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < DemoSettings.overlayOptions.length; i++)
                ChoiceChip(
                  label: Text(
                    '${(DemoSettings.overlayOptions[i] * 100).round()}%',
                  ),
                  selected: settings.overlayOpacityIndex == i,
                  onSelected: (_) =>
                      settings.update(() => settings.overlayOpacityIndex = i),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _strings(DemoSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LabeledControl(
          label: 'Language preset',
          child: SegmentedButton<DemoLanguage>(
            segments: const [
              ButtonSegment(
                value: DemoLanguage.english,
                label: Text('English'),
              ),
              ButtonSegment(value: DemoLanguage.hebrew, label: Text('Hebrew')),
            ],
            selected: <DemoLanguage>{settings.language},
            onSelectionChanged: (s) =>
                settings.update(() => settings.language = s.first),
          ),
        ),
        const SizedBox(height: 12),
        LabeledControl(
          label: 'Scanner text direction',
          child: SegmentedButton<TextDirection?>(
            segments: const [
              ButtonSegment<TextDirection?>(value: null, label: Text('System')),
              ButtonSegment<TextDirection?>(
                value: TextDirection.ltr,
                label: Text('LTR'),
              ),
              ButtonSegment<TextDirection?>(
                value: TextDirection.rtl,
                label: Text('RTL'),
              ),
            ],
            selected: <TextDirection?>{settings.scannerTextDirection},
            onSelectionChanged: (s) =>
                settings.update(() => settings.scannerTextDirection = s.first),
          ),
        ),
      ],
    );
  }
}

/// A proportional box showing the window's shape in two different previews.
///
/// Two boxes rather than one: the point of the aspect-ratio sizing is that both
/// show the same shape, which a single preview cannot demonstrate.
class _ShapePreview extends StatelessWidget {
  const _ShapePreview({
    required this.widthFraction,
    required this.aspectRatio,
    required this.radius,
  });

  final double widthFraction;
  final double aspectRatio;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _PreviewBox(
          label: 'Full-screen',
          size: const Size(101, 180),
          widthFraction: widthFraction,
          aspectRatio: aspectRatio,
          radius: radius,
        ),
        _PreviewBox(
          label: 'Embedded',
          size: const Size(160, 100),
          widthFraction: widthFraction,
          aspectRatio: aspectRatio,
          radius: radius,
        ),
      ],
    );
  }
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox({
    required this.label,
    required this.size,
    required this.widthFraction,
    required this.aspectRatio,
    required this.radius,
  });

  final String label;
  final Size size;
  final double widthFraction;
  final double aspectRatio;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Resolved by the package, so the preview cannot disagree with the scanner.
    final window = FlutterBarcodeScannerScanWindow(
      widthFraction: widthFraction,
      aspectRatio: aspectRatio,
    ).resolve(size)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: window,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.primary, width: 2),
                    borderRadius: BorderRadius.circular(radius / 3),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
