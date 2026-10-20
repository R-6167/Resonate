import 'package:flutter/material.dart';
import '../models/dsp_settings.dart';
import '../services/audio_effects_bridge.dart';
import '../ui/resonate_glass.dart';

/// Persistent user DVC control. This is intentionally separate from EQ preamp,
/// the system media volume and the player-owned crossfade envelope.
class LiveDvcControl extends StatefulWidget {
  const LiveDvcControl({super.key});

  @override
  State<LiveDvcControl> createState() => _LiveDvcControlState();
}

class _LiveDvcControlState extends State<LiveDvcControl> {
  static const _minimumDb = -24.0;
  static const _maximumDb = 6.0;

  double _db = 0.0;
  bool _loading = true;
  String _status = 'Digital gain is at unity (0 dB).';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var value = 0.0;
    try {
      final settings = await DspSettings.load();
      value = settings.dvcDb.clamp(_minimumDb, _maximumDb).toDouble();
    } catch (_) {
      // Unity gain is the safe default if preferences cannot be read.
    }
    if (!mounted) return;
    setState(() {
      _db = value;
      _loading = false;
    });
    await _apply(value, persist: false);
  }

  Future<void> _apply(double value, {required bool persist}) async {
    final result = await AudioEffectsBridge.setLiveDspDvcDb(value);
    if (persist) {
      try {
        final settings = await DspSettings.load();
        await DspSettings.save(settings.copyWith(dvcDb: value));
      } catch (_) {
        if (mounted) setState(() => _status = 'Applied for this session; could not save the preference.');
        return;
      }
    }
    if (!mounted) return;
    if (result == null || result['ok'] != true) {
      setState(() => _status = 'Native DVC is temporarily unavailable; playback remains available.');
      return;
    }
    final active = (result['active'] as num?)?.toInt() ?? 0;
    setState(() => _status = active > 0
        ? 'Applied to $active active engine${active == 1 ? '' : 's'}; new crossfade engines inherit this setting.'
        : 'Saved to the DSP engine state and will apply when playback starts.');
  }

  @override
  Widget build(BuildContext context) => ResonateGlassCard(
        blurEnabled: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Digital volume control (DVC)',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text(
              'A separate native digital-gain stage. It does not change EQ preamp, Android media volume, or crossfade fades. Positive gain can increase clipping risk; the DSP protection stage remains responsible for limiting peaks.',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(child: Text('DVC gain')),
                Text('${_db > 0 ? '+' : ''}${_db.toStringAsFixed(1)} dB',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            Slider(
              value: _db,
              min: _minimumDb,
              max: _maximumDb,
              divisions: 60,
              label: '${_db > 0 ? '+' : ''}${_db.toStringAsFixed(1)} dB',
              onChanged: _loading
                  ? null
                  : (value) {
                      setState(() {
                        _db = value;
                        _status = 'Applying DVC…';
                      });
                      _apply(value, persist: false);
                    },
              onChangeEnd: _loading ? null : (value) => _apply(value, persist: true),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('−24 dB', style: Theme.of(context).textTheme.bodySmall),
                Text('0 dB · Unity', style: Theme.of(context).textTheme.bodySmall),
                Text('+6 dB', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 6),
            Text(_status, style: Theme.of(context).textTheme.bodySmall),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _loading
                    ? null
                    : () {
                        setState(() => _db = 0.0);
                        _apply(0.0, persist: true);
                      },
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Reset to unity'),
              ),
            ),
          ],
        ),
      );
}
