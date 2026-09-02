import 'dart:io';
import 'package:flutter/services.dart';
import '../models/song.dart';

class AudioFileService {
  static const MethodChannel _channel =
      MethodChannel('com.example.resonate/media_store');

  static Future<bool> requestAudioPermission() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('requestAudioPermission') ?? false;
  }

  static Future<List<String>> getMusicDirectories() async {
    if (!Platform.isAndroid) return const [];
    return const ['Device audio (MediaStore)', 'Music', 'Download', 'Documents', 'DCIM'];
  }

  static Future<List<Song>> scanAudioFiles() async {
    if (!await requestAudioPermission()) return [];
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('scanAudio');
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
      print('🎵 AudioFileService: Found ${songs.length} audio files');
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
      final size = await _channel.invokeMethod<int>('getAudioSize') ?? 0;
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
