import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/intelligence_settings_store.dart';

class IntelligenceTransferScreen extends StatefulWidget {
  const IntelligenceTransferScreen({super.key});

  @override
  State<IntelligenceTransferScreen> createState() => _IntelligenceTransferScreenState();
}

class _IntelligenceTransferScreenState extends State<IntelligenceTransferScreen> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final document = await IntelligenceSettingsStore.exportSettings();
      final text = IntelligenceSettingsStore.encode(document);
      final fileName = 'resonate-intelligence-settings.json';
      await Share.shareXFiles(
        [XFile.fromData(Uint8List.fromList(text.codeUnits), name: fileName, mimeType: 'application/json')],
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
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (result == null) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) throw const FormatException('The selected file could not be read.');
      final document = IntelligenceSettingsStore.decode(String.fromCharCodes(bytes));
      await IntelligenceSettingsStore.importSettings(document);
      if (mounted) {
        _message('Intelligence settings imported.');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) _message('Could not import settings: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Transfer Intelligence settings')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.swap_vert_rounded, size: 32, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 10),
                  Text('Take your setup with you', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('Export your Intelligence tuning once, then import it on another Resonate installation. This avoids manually reproducing your Exploration, confidence, queue, session and other Intelligence choices.'),
                  const SizedBox(height: 10),
                  const Text('Learning history and recommendation feedback are deliberately not included. The destination device should learn from its own listening behavior.'),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _busy ? null : _export, icon: const Icon(Icons.ios_share_rounded), label: const Text('Export settings')),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _busy ? null : _import, icon: const Icon(Icons.file_open_rounded), label: const Text('Import settings')),
            if (_busy) ...[const SizedBox(height: 18), const LinearProgressIndicator()],
          ],
        ),
      );
}
