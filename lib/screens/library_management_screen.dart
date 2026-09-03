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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan complete — ${context.read<LibraryProvider>().allSongs.length} songs indexed.')));
    }
  }

  Future<void> _removeFolder(String uri) async { await AudioFileService.removeFolder(uri); await _loadFolders(); }
  Future<void> _scan() async { await context.read<LibraryProvider>().scanDeviceAudio(); }

  @override Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final text = Theme.of(context).textTheme;
    final hasFolders = _folders.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.library_music_rounded, size: 30, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 12), Expanded(child: Text('Your music', style: text.headlineSmall))]),
          const SizedBox(height: 10),
          Text(hasFolders ? 'Resonate is using the folders you selected below.' : 'On first startup, Resonate scans the audio Android makes available to the app. You do not need to choose a folder first.', style: text.bodyMedium),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: library.isScanning ? null : _scan, icon: library.isScanning ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync_rounded), label: Text(library.isScanning ? 'Scanning…' : 'Scan music now')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _addFolder, icon: const Icon(Icons.create_new_folder_outlined), label: const Text('Choose folders to scan')),
        ]))),
        const SizedBox(height: 14),
        Card(child: ListTile(leading: const Icon(Icons.music_note_rounded), title: Text('${library.allSongs.length} songs indexed', style: text.titleMedium), subtitle: Text(hasFolders ? 'Restricted to your selected folders' : 'Discovered from local Android audio', style: text.bodyMedium))),
        const SizedBox(height: 12),
        if (_loading) const Center(child: CircularProgressIndicator())
        else if (hasFolders) ...[
          Text('Selected folders', style: text.titleLarge),
          const SizedBox(height: 6),
          ..._folders.map((folder) => Card(child: ListTile(leading: const Icon(Icons.folder_outlined), title: Text(folder['name'] ?? 'Selected folder'), subtitle: const Text('Included in future scans'), trailing: IconButton(tooltip: 'Remove folder', icon: const Icon(Icons.remove_circle_outline), onPressed: () => _removeFolder(folder['uri']!))))),
        ] else Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [Icon(Icons.auto_awesome, size: 44, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 10), Text('No folder restriction', style: text.titleMedium), const SizedBox(height: 6), Text('This is the easiest setup for a new user. If you later want tighter control, choose one or more folders above.', textAlign: TextAlign.center, style: text.bodyMedium)]))),
        const SizedBox(height: 16),
        Text('How it works', style: text.titleLarge),
        const SizedBox(height: 8),
        Text('1. Allow audio access when Android asks.\n2. Resonate scans available local audio automatically.\n3. If you want to narrow the library, choose folders here.\n4. Scan again whenever you add new music.', style: text.bodyMedium),
      ]),
    );
  }
}