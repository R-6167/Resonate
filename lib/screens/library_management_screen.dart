import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../services/audio_file_service.dart';

class LibraryManagementScreen extends StatefulWidget {
  const LibraryManagementScreen({Key? key}) : super(key: key);
  @override State<LibraryManagementScreen> createState() => _LibraryManagementScreenState();
}

class _LibraryManagementScreenState extends State<LibraryManagementScreen> {
  List<Map<String, String>> _folders = [];
  bool _loading = true;
  @override void initState() { super.initState(); _loadFolders(); }

  Future<void> _loadFolders() async {
    final folders = await AudioFileService.getSelectedFolders();
    if (mounted) setState(() { _folders = folders; _loading = false; });
  }

  Future<void> _addFolder() async {
    final added = await AudioFileService.addFolder();
    await _loadFolders();
    if (added && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Folder added. Scanning it now…')));
      await context.read<LibraryProvider>().scanDeviceAudio();
      if (mounted) {
        final count = context.read<LibraryProvider>().allSongs.length;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan complete — $count songs indexed.')));
      }
    }
  }

  Future<void> _removeFolder(String uri) async { await AudioFileService.removeFolder(uri); await _loadFolders(); }
  Future<void> _scan() async { await context.read<LibraryProvider>().scanDeviceAudio(); }

  @override Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Library Management')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Music folders', style: text.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Resonate only scans folders you explicitly choose. Nothing else on the device is indexed.', style: text.bodyMedium),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _addFolder, icon: const Icon(Icons.create_new_folder_outlined), label: const Text('Add folder')),
        ]))),
        const SizedBox(height: 16),
        if (_loading) const Center(child: CircularProgressIndicator())
        else if (_folders.isEmpty) Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
          Icon(Icons.folder_open_outlined, size: 52, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12), Text('No music folders selected', textAlign: TextAlign.center, style: text.titleMedium),
          const SizedBox(height: 6), Text('Add your Music, Downloads, or another folder to get started.', textAlign: TextAlign.center, style: text.bodyMedium),
        ])))
        else ..._folders.map((folder) => Card(child: ListTile(
          leading: const Icon(Icons.folder_outlined), title: Text(folder['name'] ?? 'Selected folder'), subtitle: Text('Included in music scans', style: text.bodyMedium),
          trailing: IconButton(tooltip: 'Remove folder', icon: const Icon(Icons.remove_circle_outline), onPressed: () => _removeFolder(folder['uri']!)),
        ))),
        const SizedBox(height: 20),
        Card(child: ListTile(
          leading: const Icon(Icons.library_music_outlined), title: const Text('Scan selected folders'),
          subtitle: Text(library.isScanning ? 'Scanning…' : '${library.allSongs.length} songs currently indexed', style: text.bodyMedium),
          trailing: library.isScanning ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : FilledButton(onPressed: _folders.isEmpty ? null : _scan, child: const Text('Scan')),
        )),
        const SizedBox(height: 12),
        Text('Tip: Select a parent folder and Resonate will include its music subfolders.', style: text.bodySmall),
      ]),
    );
  }
}
