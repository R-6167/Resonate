import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

class AudioFileService {
  static const MethodChannel _channel =
      MethodChannel('com.example.resonate/media_store');
  static const _foldersKey = 'resonate_library_folders';

  static Future<bool> requestAudioPermission() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('requestAudioPermission') ?? false;
  }

  static Future<List<Map<String, String>>> getSelectedFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_foldersKey) ?? const [];
    return raw.map((value) {
      final parts = value.split('|');
      return {
        'uri': parts.first,
        'name': parts.length > 1 ? parts.sublist(1).join('|') : 'Selected folder',
      };
    }).toList();
  }

  static Future<bool> addFolder() async {
    if (!Platform.isAndroid) return false;
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('pickFolder');
    if (result == null || result['uri'] == null) return false;
    final uri = result['uri'].toString();
    final name = (result['name'] ?? 'Selected folder').toString();
    final prefs = await SharedPreferences.getInstance();
    final folders = prefs.getStringList(_foldersKey) ?? <String>[];
    if (!folders.any((item) => item.split('|').first == uri)) {
      folders.add('$uri|$name');
      await prefs.setStringList(_foldersKey, folders);
    }
    return true;
  }

  static Future<void> removeFolder(String uri) async {
    final prefs = await SharedPreferences.getInstance();
    final folders = prefs.getStringList(_foldersKey) ?? <String>[];
    folders.removeWhere((item) => item.split('|').first == uri);
    await prefs.setStringList(_foldersKey, folders);
  }

  static Future<List<Song>> scanAudioFiles({List<String>? folderUris}) async {
    if (!await requestAudioPermission()) return [];
    final folders = folderUris ??
        (await getSelectedFolders()).map((folder) => folder['uri']!).toList();
    if (folders.isEmpty) return [];

    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'scanAudio',
        {'folders': folders},
      );
      final songs = <Song>[];
      for (final raw in result ?? const []) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final uri = (map['filePath'] ?? '').toString();
        if (uri.isEmpty) continue;
        final added = _toInt(map['dateAdded']);
        songs.add(Song(
          id: uri,
          title: _text(map['title'], 'Unknown Title'),
          artist: _text(map['artist'], 'Unknown Artist'),
          album: _text(map['album'], 'Unknown Album'),
          filePath: uri,
          duration: Duration(milliseconds: _toInt(map['duration'])),
          dateAdded: added > 0
              ? DateTime.fromMillisecondsSinceEpoch(added * 1000)
              : DateTime.now(),
          albumArt: null,
        ));
      }
      print('🎵 AudioFileService: Found ${songs.length} audio files in selected folders');
      return songs;
    } catch (e) {
      print('❌ MediaStore scan failed: $e');
      return [];
    }
  }

  static Future<int> getMusicFileCount() async => (await scanAudioFiles()).length;

  static Future<Map<String, dynamic>> getStorageInfo() async {
    try {
      final songs = await scanAudioFiles();
      final size = await _channel.invokeMethod<int>('getAudioSize', {
        'folders': (await getSelectedFolders()).map((folder) => folder['uri']!).toList(),
      }) ?? 0;
      return {'totalSize': size, 'formattedSize': formatBytes(size), 'fileCount': songs.length};
    } catch (_) {
      return {'totalSize': 0, 'formattedSize': '0 B', 'fileCount': 0};
    }
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    var index = 0;
    while (value >= 1024 && index < suffixes.length - 1) {
      value /= 1024;
      index++;
    }
    return '${value.toStringAsFixed(index == 0 ? 0 : 2)} ${suffixes[index]}';
  }

  static String formatDuration(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    final s = duration.inSeconds % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static String _text(dynamic value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == '<unknown>' ? fallback : text;
  }

  static int _toInt(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;
}
