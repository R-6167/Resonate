import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/intelligence_provider.dart';
import '../services/intelligence_mix_settings_store.dart';
import '../services/intelligence_settings_store.dart';

class IntelligenceTransferScreen extends StatefulWidget {
  const IntelligenceTransferScreen({super.key});

  @override
  State<IntelligenceTransferScreen> createState() => _IntelligenceTransferScreenState();
}

class _IntelligenceTransferScreenState extends State<IntelligenceTransferScreen> {
  bool _busy = false;

  Future<Map<String, dynamic>> _document() async {
    final prefs = await SharedPreferences.getInstance();
    final core = await IntelligenceSettingsStore.exportSettings();
    core['settings']['intelligenceEnabled'] = prefs.getBool('intelligence_enabled') ?? true;
    core['settings']['autonomy'] = prefs.getInt('intelligence_autonomy') ?? 1;
    core['settings']['autopilotGraduated'] = prefs.getBool('intelligence_autopilot_graduated') ?? false;
    core['mix'] = {
      'targetMinutes': await IntelligenceMixSettingsStore.targetMinutes(),
      'longFormEnabled': await IntelligenceMixSettingsStore.longFormEnabled(),
      'minimumLongFormMinutes': await IntelligenceMixSettingsStore.minimumLongFormMinutes(),
      'replaySensitivity': await IntelligenceMixSettingsStore.replaySensitivity(),
      'autoEvolutionEnabled': await IntelligenceMixSettingsStore.autoEvolutionEnabled(),
    };
    return core;
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final text = IntelligenceSettingsStore.encode(await _document());
      await Share.shareXFiles(
        [XFile.fromData(Uint8List.fromList(text.codeUnits), name: 'resonate-intelligence-settings.json', mimeType: 'application/json')],
        subject: 'Resonate Intelligence settings',
        text: 'Resonate Intelligence settings export',
      );
    } catch (e) {
      if (mounted) _message('Could not export settings: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
      if (result == null) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) throw const FormatException('The selected file could not be read.');
      final document = IntelligenceSettingsStore.decode(String.fromCharCodes(bytes));
      await IntelligenceSettingsStore.importSettings(document);
      final prefs = await SharedPreferences.getInstance();
      final settings = document['settings'];
      if (settings is Map) {
        final enabled = settings['intelligenceEnabled'];
        final autonomy = settings['autonomy'];
        if (enabled is bool) await prefs.setBool('intelligence_enabled', enabled);
        if (autonomy is num) await prefs.setInt('intelligence_autonomy', autonomy.round().clamp(0, 2));
        final graduated = settings['autopilotGraduated'];
        if (graduated is bool) await prefs.setBool('intelligence_autopilot_graduated', graduated);
      }
      final mix = document['mix'];
      if (mix is Map) {
        Future<void> setInt(String key, Future<void> Function(int) setter, int min, int max) async {
          final value = mix[key];
          if (value is num) await setter(value.round().clamp(min, max));
        }
        Future<void> setBool(String key, Future<void> Function(bool) setter) async {
          final value = mix[key];
          if (value is bool) await setter(value);
        }
        await setInt('targetMinutes', IntelligenceMixSettingsStore.setTargetMinutes, 15, 120);
        await setBool('longFormEnabled', IntelligenceMixSettingsStore.setLongFormEnabled);
        await setInt('minimumLongFormMinutes', IntelligenceMixSettingsStore.setMinimumLongFormMinutes, 10, 60);
        await setInt('replaySensitivity', IntelligenceMixSettingsStore.setReplaySensitivity, 1, 5);
        await setBool('autoEvolutionEnabled', IntelligenceMixSettingsStore.setAutoEvolutionEnabled);
      }
      if (mounted) {
        await context.read<IntelligenceProvider>().setEnabled(prefs.getBool('intelligence_enabled') ?? true);
        await context.read<IntelligenceProvider>().setAutonomy(prefs.getInt('intelligence_autonomy') ?? 1);
        _message('Intelligence settings imported.');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) _message('Could not import settings: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Transfer Intelligence settings')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
          children: [
            Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.swap_vert_rounded, size: 32, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 10),
              Text('Take your setup with you', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Export your Intelligence tuning once, then import it on another Resonate installation. This carries your decision, exploration, queue, session, explanation, audio-intelligence and Companion mix choices.'),
              const SizedBox(height: 10),
              const Text('Learning history, song feedback and Companion memory are deliberately not included. The destination device should learn from its own listening behavior.'),
            ]))),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _busy ? null : _export, icon: const Icon(Icons.ios_share_rounded), label: const Text('Export settings')),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _busy ? null : _import, icon: const Icon(Icons.file_open_rounded), label: const Text('Import settings')),
            if (_busy) ...[const SizedBox(height: 18), const LinearProgressIndicator()],
          ],
        ),
      );
}
