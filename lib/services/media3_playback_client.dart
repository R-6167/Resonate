import 'dart:async';

import 'package:flutter/services.dart';

/// Immutable snapshot from the isolated native Media3 prototype.
///
/// This API is intentionally not wired into MusicProvider. The production
/// just_audio path remains authoritative until migration parity is proven.
class Media3PlaybackState {
  const Media3PlaybackState({
    required this.connected,
    required this.isPlaying,
    required this.playbackState,
    required this.playWhenReady,
    required this.position,
    required this.duration,
    required this.mediaId,
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
          ? Duration(
              milliseconds: rawDuration.toInt().clamp(0, 0x7fffffff).toInt(),
            )
          : null,
      mediaId: stringValue(map['mediaId']),
      volume: doubleValue(map['volume']).clamp(0.0, 1.0).toDouble(),
      hasError: boolValue(map['hasError']),
      error: stringValue(map['error']),
    );
  }
}

/// Thin typed client for the experimental Media3 bridge.
///
/// Creating this client does not connect to or start the service. A connection
/// is only requested when a command is sent or [states] is listened to.
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
