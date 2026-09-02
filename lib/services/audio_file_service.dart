import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/song.dart';

/// Android media-library access for Resonate.
/// Android 10+ uses MediaStore to work correctly with scoped storage.
class AudioFileService {
  static const MethodChannel _channel =
      MethodChannel('com.example.resonate/media_store');

  static Future<bool> requestAudioPermission() async {
    if (!Platform.isAndroid) return true;

    if (await Permission.audio.request().isGranted) return true;
    return (await Permission.storage.request()).isGranted;
  }

  static Future<List<String>> getMusicDirectories() async {
    if (!Platform.isAndroid) return const [];
    return const [
      'Device audio (MediaStore)',
      'Music',
      'Download',
      'Documents',
      'DCIM',
    ];
  }

  static Future<List<Song>> scanAudioFiles() async {
    print('🔍 AudioFileService: Starting MediaStore audio scan...');

    if (!await requestAudioPermission()) {
      print('❌ Audio permission denied');
      return [];
    }

    try {
      final result = await _channel.invokeMethod<List<dynamic>>('scanAudio');
      final songs = <Song>[];

      for (final raw in result ?? const []) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final uri = (map['filePath'] ?? '').toString();
        if (uri.isEmpty) continue;

        final dateAdded = _toInt(map['dateAdded']);
        songs.add(
          Song(
            // The MediaStore content URI is stable for the indexed item.
            id: uri,
            title: _text(map['title'], 'Unknown Title'),
            artist: _text(map['artist'], 'Unknown Artist'),
            album: _text(map['album'], 'Unknown Album'),
            filePath: uri,
            duration: Duration(milliseconds: _toInt(map['duration'])),
            dateAdded: dateAdded > 0
                ? DateTime.fromMillisecondsSinceEpoch(dateAdded * 1000)
                : DateTime.now(),
            albumArt: null,
          ),
        );
      }

      print('🎵 AudioFileService: Found ${songs.length} audio files');
      return songs;
    } on PlatformException catch (e) {
      print('❌ MediaStore scan failed: ${e.code}: ${e.message}');
      return [];
    } catch (e) {
      print('❌ MediaStore scan failed: $e');
      return [];
    }
  }

  static Future<int> getMusicFileCount() async {
    return (await scanAudioFiles()).length;
  }

  static Future<Map<String, dynamic>> getStorageInfo() async {
    try {
      final songs = await scanAudioFiles();
      final totalSize = await _channel.invokeMethod<int>('getAudioSize') ?? 0;
      return {
        'totalSize': totalSize,
        'formattedSize': formatBytes(totalSize),
        'fileCount': songs.length,
      };
    } catch (e) {
      print('❌ Error getting storage info: $e');
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
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  static String _text(dynamic value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == '<unknown>' ? fallback : text;
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
