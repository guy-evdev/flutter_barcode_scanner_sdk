import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_barcode_scanner_sdk/flutter_barcode_scanner_sdk.dart';

/// A titled card used to group related controls or readouts.
class SectionCard extends StatelessWidget {
  const SectionCard({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// A control preceded by a small label.
class LabeledControl extends StatelessWidget {
  const LabeledControl({required this.label, required this.child, super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

/// A slider that shows its current value in the label.
class SliderField extends StatelessWidget {
  const SliderField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.format,
    super.key,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String Function(double)? format;

  @override
  Widget build(BuildContext context) {
    final text = format?.call(value) ?? value.toStringAsFixed(2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $text'),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: text,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// A row of colour swatches, one of which is selected.
class ColorChoices extends StatelessWidget {
  const ColorChoices({
    required this.label,
    required this.colors,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final String label;
  final List<Color> colors;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return LabeledControl(
      label: label,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: List.generate(colors.length, (index) {
          final color = colors[index];
          final selected = index == selectedIndex;
          return InkWell(
            onTap: () => onSelected(index),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// A `label: value` line used in readouts.
class ConfigLine extends StatelessWidget {
  const ConfigLine({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

/// One scan result, coloured by kind.
class ResultTile extends StatelessWidget {
  const ResultTile({required this.result, super.key});

  final FlutterBarcodeScanResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = result.isCancelled
        ? scheme.secondary
        : result.isBarcode
        ? scheme.primary
        : scheme.error;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        result.isBarcode
            ? Icons.qr_code_2
            : result.isCancelled
            ? Icons.close
            : Icons.warning_rounded,
        color: color,
      ),
      title: Text(
        result.rawValue.isEmpty ? result.type.name : result.rawValue,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(result.format.nativeValue),
    );
  }
}

/// A monospace report with a copy button, shared by the harness pages.
class ReportCard extends StatelessWidget {
  const ReportCard({required this.report, super.key});

  final String report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                Builder(
                  builder: (context) => TextButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: report));
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Report copied')),
                      );
                    },
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('Copy'),
                  ),
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
                report,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
