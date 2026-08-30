import 'package:flutter/material.dart';

/// Audio Visualization Settings
///
/// This screen provides the user with controls for the audio visualization
/// system used by Resonate. The settings are kept locally for now so the
/// screen works without requiring an additional provider or database table.
///
/// You can later connect these values to an AudioVisualizationProvider
/// or persistent storage when the visualization engine is implemented.
class AudioVisualizationSettingsScreen extends StatefulWidget {
  const AudioVisualizationSettingsScreen({Key? key}) : super(key: key);

  @override
  State<AudioVisualizationSettingsScreen> createState() =>
      _AudioVisualizationSettingsScreenState();
}

class _AudioVisualizationSettingsScreenState
    extends State<AudioVisualizationSettingsScreen> {
  bool _visualizationEnabled = true;
  bool _showWaveform = true;
  bool _showParticles = true;
  bool _mirrorVisualization = false;
  bool _reactToBass = true;
  bool _smoothAnimation = true;

  String _visualizationType = 'Spectrum';

  double _sensitivity = 0.65;
  double _smoothing = 0.55;
  double _frameRate = 60.0;

  final List<String> _visualizationTypes = [
    'Spectrum',
    'Waveform',
    'Circular Spectrum',
    'Bars',
    'Particles',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Visualization'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ------------------------------------------------------------
          // Header
          // ------------------------------------------------------------
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary.withOpacity(0.18),
                  theme.colorScheme.secondary.withOpacity(0.08),
                ],
              ),
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.15),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.graphic_eq_rounded,
                  size: 54,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'Audio Visualization',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Customize how Resonate reacts to your music.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),

          // ------------------------------------------------------------
          // General
          // ------------------------------------------------------------
          _sectionTitle(context, 'General'),

          SwitchListTile(
            title: const Text('Enable Visualization'),
            subtitle: const Text(
              'Show animated graphics while music is playing',
            ),
            secondary: const Icon(Icons.visibility_outlined),
            value: _visualizationEnabled,
            onChanged: (value) {
              setState(() {
                _visualizationEnabled = value;
              });
            },
          ),

          ListTile(
            leading: const Icon(Icons.auto_graph_rounded),
            title: const Text('Visualization Type'),
            subtitle: Text(_visualizationType),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            enabled: _visualizationEnabled,
            onTap: _visualizationEnabled
                ? () => _showVisualizationTypeDialog(context)
                : null,
          ),

          const Divider(),

          // ------------------------------------------------------------
          // Appearance
          // ------------------------------------------------------------
          _sectionTitle(context, 'Appearance'),

          SwitchListTile(
            title: const Text('Waveform'),
            subtitle: const Text(
              'Display the audio waveform with the visualization',
            ),
            secondary: const Icon(Icons.waves_rounded),
            value: _showWaveform,
            onChanged: _visualizationEnabled
                ? (value) {
                    setState(() {
                      _showWaveform = value;
                    });
                  }
                : null,
          ),

          SwitchListTile(
            title: const Text('Particles'),
            subtitle: const Text(
              'Add floating particles to the visualization',
            ),
            secondary: const Icon(Icons.blur_on_rounded),
            value: _showParticles,
            onChanged: _visualizationEnabled
                ? (value) {
                    setState(() {
                      _showParticles = value;
                    });
                  }
                : null,
          ),

          SwitchListTile(
            title: const Text('Mirror Visualization'),
            subtitle: const Text(
              'Mirror the visualization around its center',
            ),
            secondary: const Icon(Icons.flip_rounded),
            value: _mirrorVisualization,
            onChanged: _visualizationEnabled
                ? (value) {
                    setState(() {
                      _mirrorVisualization = value;
                    });
                  }
                : null,
          ),

          const Divider(),

          // ------------------------------------------------------------
          // Audio Response
          // ------------------------------------------------------------
          _sectionTitle(context, 'Audio Response'),

          SwitchListTile(
            title: const Text('Bass Response'),
            subtitle: const Text(
              'Make the visualization react more strongly to bass',
            ),
            secondary: const Icon(Icons.speaker_group_outlined),
            value: _reactToBass,
            onChanged: _visualizationEnabled
                ? (value) {
                    setState(() {
                      _reactToBass = value;
                    });
                  }
                : null,
          ),

          _sliderTile(
            context: context,
            icon: Icons.tune_rounded,
            title: 'Sensitivity',
            subtitle: 'How strongly the visualization reacts to audio',
            value: _sensitivity,
            min: 0.1,
            max: 1.0,
            divisions: 18,
            valueLabel: '${(_sensitivity * 100).round()}%',
            enabled: _visualizationEnabled,
            onChanged: (value) {
              setState(() {
                _sensitivity = value;
              });
            },
          ),

          _sliderTile(
            context: context,
            icon: Icons.blur_linear_rounded,
            title: 'Smoothing',
            subtitle: 'Reduce sudden changes in animation',
            value: _smoothing,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            valueLabel: '${(_smoothing * 100).round()}%',
            enabled: _visualizationEnabled,
            onChanged: (value) {
              setState(() {
                _smoothing = value;
              });
            },
          ),

          const Divider(),

          // ------------------------------------------------------------
          // Performance
          // ------------------------------------------------------------
          _sectionTitle(context, 'Performance'),

          SwitchListTile(
            title: const Text('Smooth Animation'),
            subtitle: const Text(
              'Use smoother transitions between audio frames',
            ),
            secondary: const Icon(Icons.animation_rounded),
            value: _smoothAnimation,
            onChanged: _visualizationEnabled
                ? (value) {
                    setState(() {
                      _smoothAnimation = value;
                    });
                  }
                : null,
          ),

          _sliderTile(
            context: context,
            icon: Icons.speed_rounded,
            title: 'Frame Rate',
            subtitle: 'Higher values produce smoother animations',
            value: _frameRate,
            min: 30,
            max: 120,
            divisions: 9,
            valueLabel: '${_frameRate.round()} FPS',
            enabled: _visualizationEnabled,
            onChanged: (value) {
              setState(() {
                _frameRate = value;
              });
            },
          ),

          const Divider(),

          // ------------------------------------------------------------
          // Preview
          // ------------------------------------------------------------
          _sectionTitle(context, 'Preview'),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildVisualizationPreview(context),
          ),

          const SizedBox(height: 20),

          // ------------------------------------------------------------
          // Reset
          // ------------------------------------------------------------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: _resetSettings,
              icon: const Icon(Icons.restore_rounded),
              label: const Text('Reset Visualization Settings'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _sliderTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String valueLabel,
    required bool enabled,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: enabled
                      ? theme.colorScheme.primary
                      : theme.disabledColor,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  valueLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: enabled
                        ? theme.colorScheme.primary
                        : theme.disabledColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: valueLabel,
              onChanged: enabled ? onChanged : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualizationPreview(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.5),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_visualizationEnabled)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(
                24,
                (index) {
                  final height = 20.0 +
                      ((index * 17) % 90).toDouble() *
                          _sensitivity;

                  return AnimatedContainer(
                    duration: Duration(
                      milliseconds: _smoothAnimation ? 300 : 100,
                    ),
                    width: 5,
                    height: height,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: theme.colorScheme.primary.withOpacity(
                        0.45 + ((index % 5) * 0.1),
                      ),
                    ),
                  );
                },
              ),
            )
          else
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.visibility_off_outlined,
                  size: 42,
                  color: theme.disabledColor,
                ),
                const SizedBox(height: 10),
                Text(
                  'Visualization Disabled',
                  style: theme.textTheme.bodyLarge,
                ),
              ],
            ),

          Positioned(
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withOpacity(0.8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _visualizationType,
                style: theme.textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showVisualizationTypeDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Visualization Type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _visualizationTypes.map((type) {
              return RadioListTile<String>(
                title: Text(type),
                value: type,
                groupValue: _visualizationType,
                onChanged: (value) {
                  if (value == null) return;

                  setState(() {
                    _visualizationType = value;
                  });

                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _resetSettings() {
    setState(() {
      _visualizationEnabled = true;
      _showWaveform = true;
      _showParticles = true;
      _mirrorVisualization = false;
      _reactToBass = true;
      _smoothAnimation = true;
      _visualizationType = 'Spectrum';
      _sensitivity = 0.65;
      _smoothing = 0.55;
      _frameRate = 60.0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Visualization settings reset'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
