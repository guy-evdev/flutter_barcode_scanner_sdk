import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner_sdk/flutter_barcode_scanner_sdk.dart';

import 'mount_cycle_page.dart';
import 'stress_harness_page.dart';

/// Selects a harness to run unattended, set with
/// `--dart-define=HARNESS_AUTORUN=cycles`.
///
/// Physical iPhones cannot be driven by injected taps the way an Android device
/// can, so the harness has to start itself and report over the log.
const String kHarnessAutorun = String.fromEnvironment('HARNESS_AUTORUN');

void main() {
  runApp(const ScannerShowcaseApp());
}

enum ShowcaseLanguage { english, hebrew }

enum FormatPreset { all, qrAndCode128, twoDimensionalOnly, oneDimensionalOnly }

class ScannerShowcaseApp extends StatelessWidget {
  const ScannerShowcaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0A1C58)),
        useMaterial3: true,
      ),
      home: switch (kHarnessAutorun) {
        'cycles' => MountCyclePage(
          config: FlutterBarcodeScannerConfig(),
          autoStart: true,
        ),
        'soak' => StressHarnessPage(
          config: FlutterBarcodeScannerConfig(),
          autoStart: true,
        ),
        _ => const ScannerShowcaseScreen(),
      },
    );
  }
}

class ScannerShowcaseScreen extends StatefulWidget {
  const ScannerShowcaseScreen({super.key});

  @override
  State<ScannerShowcaseScreen> createState() => _ScannerShowcaseScreenState();
}

class _ScannerShowcaseScreenState extends State<ScannerShowcaseScreen> {
  static const _appBarColors = <Color>[
    Color(0xFF0A1C58),
    Color(0xFF0D3B2E),
    Color(0xFF4A1D1F),
    Color(0xFF263238),
  ];

  static const _overlayOptions = <double>[0.30, 0.45, 0.60, 0.72];
  static const _pausedBorderColors = <Color>[
    Color(0xFFE53935),
    Color(0xFFFFB300),
    Color(0xFF00C853),
    Color(0xFF40C4FF),
  ];

  ShowcaseLanguage _language = ShowcaseLanguage.english;
  bool _isContinuousLoop = false;
  bool _isLaunchingScanner = false;
  bool _showFlashButton = true;
  bool _showCameraSwitchButton = true;
  bool _initialTorchEnabled = false;
  bool _statusBarTransparent = false;
  bool _appBarTransparent = false;
  bool _scanWindowEnabled = true;
  bool _showEmbeddedScanner = false;
  bool _embeddedAutoRequestCameraPermission = true;
  bool _embeddedAutoStart = true;
  bool _embeddedAutoPauseOnScan = true;
  bool _embeddedShowPauseResumeButton = false;
  BarcodeCameraLens _initialCameraLens = BarcodeCameraLens.back;
  FlutterBarcodeScannerStatusBarIconBrightness _statusBarIconBrightness =
      FlutterBarcodeScannerStatusBarIconBrightness.light;
  TextDirection? _scannerTextDirection = TextDirection.ltr;
  FormatPreset _formatPreset = FormatPreset.qrAndCode128;
  double _scanWindowWidthFactor = 0.58;
  double _scanWindowHeightFactor = 0.58;
  double _scanWindowCornerRadius = 18;
  int _appBarColorIndex = 0;
  int _overlayOpacityIndex = 2;
  int _pausedBorderColorIndex = 0;

  FlutterBarcodeScanResult? _lastResult;
  final FlutterBarcodeScannerController _embeddedController =
      FlutterBarcodeScannerController();
  final List<FlutterBarcodeScanResult> _scanHistory =
      <FlutterBarcodeScanResult>[];

  @override
  void dispose() {
    _embeddedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveDirection =
        _scannerTextDirection ?? Directionality.of(context);
    final isRtl = effectiveDirection == TextDirection.rtl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner SDK Showcase'),
        actions: [
          IconButton(
            onPressed: _openMountCycles,
            icon: const Icon(Icons.repeat),
            tooltip: 'Mount / unmount cycles',
          ),
          IconButton(
            onPressed: _openStressHarness,
            icon: const Icon(Icons.speed_outlined),
            tooltip: 'Stress harness',
          ),
          FilledButton.tonalIcon(
            onPressed: _isLaunchingScanner ? null : _startScannerFlow,
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(_isLaunchingScanner ? 'Scanning…' : 'Start'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 1100;
          final controlsSections = _buildControlsSections(context, isRtl);
          final resultsSections = _buildResultsSections(context, scheme, isRtl);

          final controlsPane = ListView(
            padding: const EdgeInsets.all(16),
            children: controlsSections,
          );

          final resultsPane = Container(
            color: scheme.surfaceContainerLowest,
            padding: const EdgeInsets.all(16),
            child: ListView(children: resultsSections),
          );

          if (isCompact) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...controlsSections,
                const SizedBox(height: 8),
                Container(
                  color: scheme.surfaceContainerLowest,
                  padding: const EdgeInsets.all(16),
                  child: Column(children: resultsSections),
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(flex: 8, child: controlsPane),
              Expanded(flex: 5, child: resultsPane),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildControlsSections(BuildContext context, bool isRtl) {
    return [
      _SectionCard(
        title: 'Scan Flow',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isContinuousLoop,
              title: const Text('Continuous loop'),
              subtitle: const Text(
                'Reopen the native scanner after each successful result until the user cancels.',
              ),
              onChanged: (value) {
                setState(() {
                  _isContinuousLoop = value;
                });
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _SectionCard(
        title: 'Embedded Scanner',
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _showEmbeddedScanner,
              title: const Text('Show embedded scanner widget'),
              subtitle: const Text(
                'Uses the same native engines inside a Flutter layout.',
              ),
              onChanged: (value) {
                setState(() {
                  _showEmbeddedScanner = value;
                });
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _embeddedAutoRequestCameraPermission,
              title: const Text('Auto-request camera permission'),
              onChanged: (value) {
                setState(() {
                  _embeddedAutoRequestCameraPermission = value;
                });
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _embeddedAutoStart,
              title: const Text('Embedded auto-start'),
              onChanged: (value) {
                setState(() {
                  _embeddedAutoStart = value;
                });
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _embeddedAutoPauseOnScan,
              title: const Text('Embedded auto-pause after result'),
              onChanged: (value) {
                setState(() {
                  _embeddedAutoPauseOnScan = value;
                });
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _embeddedShowPauseResumeButton,
              title: const Text('Show pause / resume overlay button'),
              onChanged: (value) {
                setState(() {
                  _embeddedShowPauseResumeButton = value;
                });
              },
            ),
            const SizedBox(height: 12),
            _ColorChoices(
              label: 'Paused scan-window border color',
              colors: _pausedBorderColors,
              selectedIndex: _pausedBorderColorIndex,
              onSelected: (index) {
                setState(() {
                  _pausedBorderColorIndex = index;
                });
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _SectionCard(
        title: 'Strings And Direction',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LabeledControl(
              label: 'Language preset',
              child: SegmentedButton<ShowcaseLanguage>(
                segments: const [
                  ButtonSegment(
                    value: ShowcaseLanguage.english,
                    label: Text('English'),
                  ),
                  ButtonSegment(
                    value: ShowcaseLanguage.hebrew,
                    label: Text('Hebrew'),
                  ),
                ],
                selected: <ShowcaseLanguage>{_language},
                onSelectionChanged: (selection) {
                  setState(() {
                    _language = selection.first;
                  });
                },
              ),
            ),
            const SizedBox(height: 12),
            _LabeledControl(
              label: 'Scanner text direction',
              child: SegmentedButton<TextDirection?>(
                segments: const [
                  ButtonSegment<TextDirection?>(
                    value: null,
                    label: Text('System'),
                  ),
                  ButtonSegment<TextDirection?>(
                    value: TextDirection.ltr,
                    label: Text('LTR'),
                  ),
                  ButtonSegment<TextDirection?>(
                    value: TextDirection.rtl,
                    label: Text('RTL'),
                  ),
                ],
                selected: <TextDirection?>{_scannerTextDirection},
                onSelectionChanged: (selection) {
                  setState(() {
                    _scannerTextDirection = selection.first;
                  });
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Current effective direction: ${isRtl ? 'RTL' : 'LTR'}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _SectionCard(
        title: 'Allowed Formats',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: FormatPreset.values.map((preset) {
                return ChoiceChip(
                  label: Text(_formatPresetLabel(preset)),
                  selected: _formatPreset == preset,
                  onSelected: (_) {
                    setState(() {
                      _formatPreset = preset;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Text(_formatSummary, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _SectionCard(
        title: 'Native UI',
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _showFlashButton,
              title: const Text('Show flash button'),
              onChanged: (value) {
                setState(() {
                  _showFlashButton = value;
                });
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _showCameraSwitchButton,
              title: const Text('Show camera switch button'),
              onChanged: (value) {
                setState(() {
                  _showCameraSwitchButton = value;
                });
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _initialTorchEnabled,
              title: const Text('Start with torch enabled'),
              onChanged: (value) {
                setState(() {
                  _initialTorchEnabled = value;
                });
              },
            ),
            const SizedBox(height: 12),
            _LabeledControl(
              label: 'Initial camera lens',
              child: SegmentedButton<BarcodeCameraLens>(
                segments: const [
                  ButtonSegment(
                    value: BarcodeCameraLens.back,
                    label: Text('Back'),
                  ),
                  ButtonSegment(
                    value: BarcodeCameraLens.front,
                    label: Text('Front'),
                  ),
                ],
                selected: <BarcodeCameraLens>{_initialCameraLens},
                onSelectionChanged: (selection) {
                  setState(() {
                    _initialCameraLens = selection.first;
                  });
                },
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _SectionCard(
        title: 'Scan Window',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SliderField(
              label: 'Width factor',
              value: _scanWindowWidthFactor,
              min: 0.35,
              max: 0.85,
              onChanged: (value) {
                setState(() {
                  _scanWindowWidthFactor = value;
                });
              },
            ),
            _SliderField(
              label: 'Height factor',
              value: _scanWindowHeightFactor,
              min: 0.35,
              max: 0.85,
              onChanged: (value) {
                setState(() {
                  _scanWindowHeightFactor = value;
                });
              },
            ),
            _SliderField(
              label: 'Corner radius',
              value: _scanWindowCornerRadius,
              min: 0,
              max: 36,
              divisions: 18,
              onChanged: (value) {
                setState(() {
                  _scanWindowCornerRadius = value;
                });
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _scanWindowEnabled,
              title: const Text('Enable scan window'),
              subtitle: const Text(
                'Turn this off to scan across the full preview with no scan-box UI.',
              ),
              onChanged: (value) {
                setState(() {
                  _scanWindowEnabled = value;
                });
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _scanWindowWidthFactor = 0.58;
                      _scanWindowHeightFactor = 0.58;
                    });
                  },
                  child: const Text('Square default'),
                ),
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _scanWindowWidthFactor = 0.62;
                      _scanWindowHeightFactor = 0.42;
                    });
                  },
                  child: const Text('Wide barcode window'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _SectionCard(
        title: 'Status Bar And Chrome',
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _statusBarTransparent,
              title: const Text('Transparent status bar'),
              onChanged: (value) {
                setState(() {
                  _statusBarTransparent = value;
                });
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _appBarTransparent,
              title: const Text('Transparent app bar'),
              onChanged: (value) {
                setState(() {
                  _appBarTransparent = value;
                });
              },
            ),
            const SizedBox(height: 12),
            _LabeledControl(
              label: 'Status bar icon brightness',
              child:
                  SegmentedButton<FlutterBarcodeScannerStatusBarIconBrightness>(
                    segments: const [
                      ButtonSegment(
                        value:
                            FlutterBarcodeScannerStatusBarIconBrightness.light,
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value:
                            FlutterBarcodeScannerStatusBarIconBrightness.dark,
                        label: Text('Dark'),
                      ),
                    ],
                    selected: <FlutterBarcodeScannerStatusBarIconBrightness>{
                      _statusBarIconBrightness,
                    },
                    onSelectionChanged: (selection) {
                      setState(() {
                        _statusBarIconBrightness = selection.first;
                      });
                    },
                  ),
            ),
            const SizedBox(height: 12),
            _ColorChoices(
              label: 'App bar color',
              colors: _appBarColors,
              selectedIndex: _appBarColorIndex,
              onSelected: (index) {
                setState(() {
                  _appBarColorIndex = index;
                });
              },
            ),
            const SizedBox(height: 12),
            _LabeledControl(
              label: 'Overlay intensity',
              child: Wrap(
                spacing: 8,
                children: List.generate(_overlayOptions.length, (index) {
                  final opacity = _overlayOptions[index];
                  return ChoiceChip(
                    label: Text('${(opacity * 100).round()}%'),
                    selected: _overlayOpacityIndex == index,
                    onSelected: (_) {
                      setState(() {
                        _overlayOpacityIndex = index;
                      });
                    },
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildResultsSections(
    BuildContext context,
    ColorScheme scheme,
    bool isRtl,
  ) {
    return [
      if (_showEmbeddedScanner) ...[
        _SectionCard(
          title: 'Embedded Scanner Widget',
          child: Column(
            children: [
              SizedBox(
                height: 360,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: FlutterBarcodeScannerView(
                    config: _buildConfig(),
                    widgetConfig: _buildWidgetConfig(),
                    controller: _embeddedController,
                    autoStart: _embeddedAutoStart,
                    autoPauseOnScan: _embeddedAutoPauseOnScan,
                    onScan: _recordResult,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _embeddedController.startCamera,
                    icon: const Icon(Icons.videocam_outlined),
                    label: const Text('Start'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _embeddedController.stopCamera,
                    icon: const Icon(Icons.videocam_off_outlined),
                    label: const Text('Stop'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _embeddedController.pauseDetection,
                    icon: const Icon(Icons.pause_circle_outline),
                    label: const Text('Pause detection'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _embeddedController.resumeDetection,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Resume detection'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
      _SectionCard(
        title: 'Active Config Preview',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ConfigLine(label: 'Direction', value: isRtl ? 'RTL' : 'LTR'),
            _ConfigLine(label: 'Formats', value: _formatSummary),
            _ConfigLine(
              label: 'Window',
              value: _scanWindowEnabled
                  ? '${_scanWindowWidthFactor.toStringAsFixed(2)} x ${_scanWindowHeightFactor.toStringAsFixed(2)}'
                  : 'Full preview',
            ),
            _ConfigLine(
              label: 'Radius',
              value: _scanWindowCornerRadius.toStringAsFixed(0),
            ),
            _ConfigLine(
              label: 'Flash',
              value:
                  '${_showFlashButton ? 'shown' : 'hidden'} / ${_initialTorchEnabled ? 'on' : 'off'}',
            ),
            _ConfigLine(
              label: 'Camera switch',
              value: _showCameraSwitchButton ? 'shown' : 'hidden',
            ),
            _ConfigLine(
              label: 'Status bar',
              value: _statusBarTransparent
                  ? 'transparent'
                  : _statusBarIconBrightness.name,
            ),
            _ConfigLine(
              label: 'App bar',
              value: _appBarTransparent ? 'transparent' : 'colored',
            ),
            _ConfigLine(
              label: 'Language',
              value: _language == ShowcaseLanguage.hebrew
                  ? 'Hebrew'
                  : 'English',
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _SectionCard(
        title: 'Last Result',
        child: _lastResult == null
            ? const Text('No scan result yet.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ConfigLine(label: 'Type', value: _lastResult!.type.name),
                  _ConfigLine(
                    label: 'Raw value',
                    value: _lastResult!.rawValue.isEmpty
                        ? '—'
                        : _lastResult!.rawValue,
                  ),
                  _ConfigLine(
                    label: 'Format',
                    value: _lastResult!.format.nativeValue,
                  ),
                  if (_lastResult!.errorMessage != null)
                    _ConfigLine(
                      label: 'Error',
                      value: _lastResult!.errorMessage!,
                    ),
                ],
              ),
      ),
      const SizedBox(height: 16),
      _SectionCard(
        title: 'Recent History',
        child: _scanHistory.isEmpty
            ? const Text('No scans captured in this session.')
            : Column(
                children: _scanHistory.map((result) {
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
                      result.rawValue.isEmpty
                          ? result.type.name
                          : result.rawValue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(result.format.nativeValue),
                  );
                }).toList(),
              ),
      ),
    ];
  }

  Future<void> _startScannerFlow() async {
    if (_isLaunchingScanner) {
      return;
    }

    setState(() {
      _isLaunchingScanner = true;
    });

    try {
      while (mounted) {
        await _prepareForScannerPresentation();
        if (!mounted) {
          return;
        }
        final result = await FlutterBarcodeScanner.scan(_buildConfig());
        if (!mounted) {
          return;
        }

        if (result != null) {
          _recordResult(result);
        }

        if (!_isContinuousLoop || result == null || result.isCancelled) {
          break;
        }

        if (_isContinuousLoop) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLaunchingScanner = false;
        });
      }
    }
  }

  void _recordResult(FlutterBarcodeScanResult result) {
    setState(() {
      _lastResult = result;
      _scanHistory.insert(0, result);
      if (_scanHistory.length > 8) {
        _scanHistory.removeLast();
      }
    });
  }

  Future<void> _prepareForScannerPresentation() async {
    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 64));
  }

  FlutterBarcodeScannerConfig _buildConfig() {
    final appBarColor = _appBarColors[_appBarColorIndex];
    final overlayOpacity = _overlayOptions[_overlayOpacityIndex];
    final strings = switch (_language) {
      ShowcaseLanguage.english => const FlutterBarcodeScannerStrings(
        title: 'Scan Barcode',
        close: 'Close',
        flashOn: 'Flash on',
        flashOff: 'Flash off',
        switchCamera: 'Switch camera',
        cameraPermissionRequired: 'Camera permission is required',
        cameraUnavailable: 'Camera unavailable',
      ),
      ShowcaseLanguage.hebrew => const FlutterBarcodeScannerStrings(
        title: 'מצלמה',
        close: 'סגור',
        flashOn: 'הפעל פלאש',
        flashOff: 'כבה פלאש',
        switchCamera: 'החלף מצלמה',
        cameraPermissionRequired: 'נדרשת הרשאת מצלמה',
        cameraUnavailable: 'המצלמה אינה זמינה',
      ),
    };

    return FlutterBarcodeScannerConfig().copyWith(
      allowedFormats: _allowedFormats,
      strings: strings,
      scanWindow: FlutterBarcodeScannerScanWindow(
        enabled: _scanWindowEnabled,
        widthFactor: _scanWindowWidthFactor,
        heightFactor: _scanWindowHeightFactor,
        cornerRadius: _scanWindowCornerRadius,
      ),
      uiConfig: FlutterBarcodeScannerUiConfig(
        showFlashButton: _showFlashButton,
        showCameraSwitchButton: _showCameraSwitchButton,
        initialCameraLens: _initialCameraLens,
        initialTorchEnabled: _initialTorchEnabled,
      ),
      statusBarStyle: FlutterBarcodeScannerStatusBarStyle(
        isTransparent: _statusBarTransparent,
        backgroundColor: _statusBarTransparent ? null : appBarColor,
        iconBrightness: _statusBarIconBrightness,
      ),
      textDirection: _scannerTextDirection,
      appBarTransparent: _appBarTransparent,
      appBarBackgroundColor: appBarColor,
      appBarForegroundColor: Colors.white,
      overlayColor: Colors.black.withValues(alpha: overlayOpacity),
    );
  }

  void _openMountCycles() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MountCyclePage(config: _buildConfig()),
      ),
    );
  }

  void _openStressHarness() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => StressHarnessPage(config: _buildConfig()),
      ),
    );
  }

  FlutterBarcodeScannerWidgetConfig _buildWidgetConfig() {
    return FlutterBarcodeScannerWidgetConfig(
      autoRequestCameraPermission: _embeddedAutoRequestCameraPermission,
      showPauseResumeButton: _embeddedShowPauseResumeButton,
      pausedScanWindowBorderColor: _pausedBorderColors[_pausedBorderColorIndex],
    );
  }

  Set<FlutterBarcodeScannerFormat> get _allowedFormats {
    switch (_formatPreset) {
      case FormatPreset.all:
        return FlutterBarcodeScannerFormats.all;
      case FormatPreset.qrAndCode128:
        return const {
          FlutterBarcodeScannerFormat.qrCode,
          FlutterBarcodeScannerFormat.code128,
        };
      case FormatPreset.twoDimensionalOnly:
        return FlutterBarcodeScannerFormats.twoDimensional;
      case FormatPreset.oneDimensionalOnly:
        return FlutterBarcodeScannerFormats.oneDimensional;
    }
  }

  String get _formatSummary {
    switch (_formatPreset) {
      case FormatPreset.all:
        return 'All supported formats';
      case FormatPreset.qrAndCode128:
        return 'QR Code + CODE_128';
      case FormatPreset.twoDimensionalOnly:
        return 'QR + PDF417 + Data Matrix + Aztec';
      case FormatPreset.oneDimensionalOnly:
        return 'CODE_128 + CODE_39 + CODE_93 + EAN/UPC + ITF';
    }
  }

  String _formatPresetLabel(FormatPreset preset) {
    switch (preset) {
      case FormatPreset.all:
        return 'All';
      case FormatPreset.qrAndCode128:
        return 'QR + 128';
      case FormatPreset.twoDimensionalOnly:
        return '2D only';
      case FormatPreset.oneDimensionalOnly:
        return '1D only';
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

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
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _LabeledControl extends StatelessWidget {
  const _LabeledControl({required this.label, required this.child});

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

class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toStringAsFixed(2)}'),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: value.toStringAsFixed(2),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ColorChoices extends StatelessWidget {
  const _ColorChoices({
    required this.label,
    required this.colors,
    required this.selectedIndex,
    required this.onSelected,
  });

  final String label;
  final List<Color> colors;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return _LabeledControl(
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

class _ConfigLine extends StatelessWidget {
  const _ConfigLine({required this.label, required this.value});

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
