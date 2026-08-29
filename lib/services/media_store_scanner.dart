import 'dart:async';
import 'package:flutter/services.dart';
import '../models/song.dart';

class MediaStoreScanner {
  static const MethodChannel _channel = MethodChannel('resonate/media_store');

  static Future<List<Song>> scan() async {
    final List<dynamic> list = await _channel.invokeMethod('scan');
    return list.map((m) {
      final Map<dynamic, dynamic> map = m as Map<dynamic, dynamic>;
      return Song(
        id: map['id']?.toString() ?? '',
        title: map['title'] ?? map['display_name'] ?? '',
        artist: map['artist'] ?? 'Unknown',
        album: map['album'] ?? 'Unknown',
        duration: (map['duration'] is int) ? map['duration'] : int.tryParse(map['duration']?.toString() ?? '0') ?? 0,
        path: map['path'] ?? '',
        dateAdded: DateTime.fromMillisecondsSinceEpoch((map['date_added'] is int) ? map['date_added'] : int.tryParse(map['date_added']?.toString() ?? '0') ?? 0),
        playCount: 0,
        isFavorite: false,
      );
    }).toList();
  }
}
