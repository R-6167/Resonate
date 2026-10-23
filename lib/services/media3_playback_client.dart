import 'dart:async';

import 'package:flutter/services.dart';

/// Immutable playback snapshot published by the native Media3 session.
class Media3PlaybackState {
  const Media3PlaybackState({
    required this.connected,
    required this.isPlaying,
    required this.playbackState,
    required this.playWhenReady,
    required this.position,
    required this.duration,
    required this.mediaId,
    required this.title,
    required this.artist,
    required this.album,
    required this.currentMediaItemIndex,
    required this.mediaItemCount,
    required this.volume,
    required this.hasError,
    required this.error,
  });

  final bool connected;
  final bool isPlaying;
  final int playbackState;
  final bool playWhenReady;
  final Duration position;
  final Duration? duration;
  final String? mediaId;
  final String? title;
  final String? artist;
  final String? album;
  final int currentMediaItemIndex;
  final int mediaItemCount;
  final double volume;
  final bool hasError;
  final String? error;

  factory Media3PlaybackState.fromMap(Map<Object?, Object?> map) {
    int integerValue(Object? value, [int fallback = 0]) =>
        value is num ? value.toInt() : fallback;
    double doubleValue(Object? value, [double fallback = 1.0]) =>
        value is num && value.isFinite ? value.toDouble() : fallback;
    bool boolValue(Object? value) => value == true;
    String? stringValue(Object? value) => value is String ? value : null;

    final rawDuration = map['durationMs'];
    return Media3PlaybackState(
      connected: boolValue(map['connected']),
      isPlaying: boolValue(map['isPlaying']),
      playbackState: integerValue(map['playbackState']),
      playWhenReady: boolValue(map['playWhenReady']),
      position: Duration(
        milliseconds: integerValue(map['positionMs']).clamp(0, 0x7fffffff).toInt(),
      ),
      duration: rawDuration is num && rawDuration >= 0
          ? Duration(milliseconds: rawDuration.toInt().clamp(0, 0x7fffffff).toInt())
          : null,
      mediaId: stringValue(map['mediaId']),
      title: stringValue(map['title']),
      artist: stringValue(map['artist']),
      album: stringValue(map['album']),
      currentMediaItemIndex: integerValue(map['currentMediaItemIndex'], -1),
      mediaItemCount: integerValue(map['mediaItemCount']),
      volume: doubleValue(map['volume']).clamp(0.0, 1.0).toDouble(),
      hasError: boolValue(map['hasError']),
      error: stringValue(map['error']),
    );
  }
}

/// Typed command/state boundary for native Media3 playback.
class Media3PlaybackClient {
  Media3PlaybackClient({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel = methodChannel ??
            const MethodChannel('com.aetherion.resonate/media3'),
        _eventChannel = eventChannel ??
            const EventChannel('com.aetherion.resonate/media3_events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  Stream<Media3PlaybackState> get states => _eventChannel
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => Media3PlaybackState.fromMap(
            Map<Object?, Object?>.from(event as Map),
          ));

  Future<void> setSource(Uri uri) async {
    if (!uri.hasScheme) {
      throw ArgumentError.value(uri, 'uri', 'A URI with a scheme is required.');
    }
    await _methodChannel.invokeMethod<bool>(
      'setSource',
      <String, Object>{'uri': uri.toString()},
    );
  }

  /// Loads a native Media3 queue and selects [startIndex] as the active item.
  /// Queue items are immutable metadata + URI descriptors; native Player objects
  /// never cross the Flutter boundary.
  Future<void> setQueue(
    List<Media3QueueItem> items, {
    int startIndex = 0,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError.value(items, 'items', 'Queue must not be empty.');
    }
    if (items.length > 500) {
      throw ArgumentError.value(items.length, 'items', 'Queue cannot exceed 500 items.');
    }
    if (startIndex < 0 || startIndex >= items.length) {
      throw ArgumentError.value(startIndex, 'startIndex', 'Must point to an item in the queue.');
    }
    await _methodChannel.invokeMethod<bool>(
      'setQueue',
      <String, Object>{
        'items': items.map((item) => item.toMap()).toList(growable: false),
        'startIndex': startIndex,
      },
    );
  }

  Future<void> skipToNext() => _command('skipToNext');
  Future<void> skipToPrevious() => _command('skipToPrevious');

  Future<void> setRepeatMode(String mode) async {
    if (!const {'off', 'one', 'all'}.contains(mode)) {
      throw ArgumentError.value(mode, 'mode', 'Must be off, one, or all.');
    }
    await _methodChannel.invokeMethod<bool>(
      'setRepeatMode',
      <String, Object>{'mode': mode},
    );
  }

  Future<void> play() => _command('play');
  Future<void> pause() => _command('pause');
  Future<void> stop() => _command('stop');

  Future<void> seekTo(Duration position) async {
    if (position.isNegative) {
      throw ArgumentError.value(position, 'position', 'Must not be negative.');
    }
    await _methodChannel.invokeMethod<bool>(
      'seekTo',
      <String, Object>{'positionMs': position.inMilliseconds},
    );
  }

  Future<void> setVolume(double volume) async {
    if (!volume.isFinite) {
      throw ArgumentError.value(volume, 'volume', 'Must be finite.');
    }
    await _methodChannel.invokeMethod<bool>(
      'setVolume',
      <String, Object>{'value': volume.clamp(0.0, 1.0).toDouble()},
    );
  }

  Future<void> preloadNext(Uri uri) async {
    if (!uri.hasScheme) {
      throw ArgumentError.value(uri, 'uri', 'A URI with a scheme is required.');
    }
    await _methodChannel.invokeMethod<bool>(
      'preloadNext',
      <String, Object>{'uri': uri.toString()},
    );
  }

  Future<void> crossfade({Duration duration = const Duration(seconds: 5)}) async {
    if (duration < const Duration(milliseconds: 250) ||
        duration > const Duration(seconds: 15)) {
      throw ArgumentError.value(duration, 'duration', 'Must be between 250 ms and 15 s.');
    }
    await _methodChannel.invokeMethod<bool>(
      'crossfade',
      <String, Object>{'durationMs': duration.inMilliseconds},
    );
  }

  Future<void> cancelCrossfade() => _command('cancelCrossfade');

  Future<Map<Object?, Object?>> getCrossfadeState() async {
    final state = await _methodChannel.invokeMapMethod<Object?, Object?>('crossfadeState');
    return state ?? <Object?, Object?>{'status': 'unknown'};
  }

  Future<Media3PlaybackState> getState() async {
    final value = await _methodChannel.invokeMapMethod<Object?, Object?>('getState');
    if (value == null) {
      throw StateError('Native Media3 bridge returned no playback state.');
    }
    return Media3PlaybackState.fromMap(value);
  }

  Future<void> _command(String method) async {
    await _methodChannel.invokeMethod<bool>(method);
  }
}


/// Queue descriptor sent to the native Media3 session.
class Media3QueueItem {
  const Media3QueueItem({
    required this.id,
    required this.uri,
    required this.title,
    this.artist,
    this.album,
    this.artworkUri,
  });

  final String id;
  final Uri uri;
  final String title;
  final String? artist;
  final String? album;
  final Uri? artworkUri;

  Map<String, Object?> toMap() {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Queue item ID must not be empty.');
    }
    if (!uri.hasScheme) {
      throw ArgumentError.value(uri, 'uri', 'A URI with a scheme is required.');
    }
    if (artworkUri != null && !artworkUri!.hasScheme) {
      throw ArgumentError.value(artworkUri, 'artworkUri', 'Artwork URI must have a scheme.');
    }
    return <String, Object?>{
      'id': id,
      'uri': uri.toString(),
      'title': title,
      if (artist != null) 'artist': artist!,
      if (album != null) 'album': album!,
      if (artworkUri != null) 'artworkUri': artworkUri.toString(),
    };
  }
}
