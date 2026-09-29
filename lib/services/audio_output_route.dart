import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// Where audio is actually going — drives EQ delivery policy.
enum AudioOutputRoute {
  /// Built-in earpiece / loudspeaker (limited LF, easy to distort).
  builtInSpeaker,

  /// Wired or USB headphones / headset.
  headphones,

  /// Bluetooth A2DP / LE audio / SCO (headphones, buds, etc.).
  bluetooth,

  /// External speaker, soundbar, HDMI, line-out.
  externalSpeaker,

  /// Car / vehicle audio.
  car,

  unknown,
}

/// Watches [AudioSession] devices and classifies the active output route.
class AudioOutputRouteService extends ChangeNotifier {
  AudioOutputRouteService._();
  static final AudioOutputRouteService instance = AudioOutputRouteService._();

  AudioOutputRoute _route = AudioOutputRoute.unknown;
  String _deviceLabel = '';
  StreamSubscription<AudioDevicesChangedEvent>? _sub;
  bool _started = false;

  AudioOutputRoute get route => _route;
  String get deviceLabel => _deviceLabel;

  /// True when aggressive EQ should be tempered (built-in speaker only).
  bool get needsSpeakerProtection =>
      _route == AudioOutputRoute.builtInSpeaker ||
      _route == AudioOutputRoute.unknown;

  /// True when full DSP potential is appropriate.
  bool get allowsFullDsp => !needsSpeakerProtection;

  String get routeLabel => switch (_route) {
        AudioOutputRoute.builtInSpeaker => 'Phone speaker',
        AudioOutputRoute.headphones => 'Headphones',
        AudioOutputRoute.bluetooth => 'Bluetooth',
        AudioOutputRoute.externalSpeaker => 'External speaker',
        AudioOutputRoute.car => 'Car audio',
        AudioOutputRoute.unknown => 'Unknown',
      };

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final session = await AudioSession.instance;
      await refresh(session);
      await _sub?.cancel();
      _sub = session.devicesChangedEventStream.listen((_) {
        unawaited(refresh(session));
      });
    } catch (e) {
      debugPrint('AudioOutputRouteService.start failed: $e');
    }
  }

  Future<void> refresh([AudioSession? session]) async {
    try {
      session ??= await AudioSession.instance;
      final devices =
          await session.getDevices(includeInputs: false, includeOutputs: true);
      final next = _classify(devices);
      final label = _labelFor(devices, next);
      if (next != _route || label != _deviceLabel) {
        _route = next;
        _deviceLabel = label;
        debugPrint('AudioOutputRoute → $routeLabel ($label)');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('AudioOutputRouteService.refresh failed: $e');
    }
  }

  static AudioOutputRoute _classify(List<AudioDevice> devices) {
    if (devices.isEmpty) return AudioOutputRoute.builtInSpeaker;

    bool has(bool Function(AudioDeviceType t) pred) =>
        devices.any((d) => pred(d.type));

    if (has((t) => t == AudioDeviceType.carAudio)) {
      return AudioOutputRoute.car;
    }
    if (has((t) =>
        t == AudioDeviceType.bluetoothA2dp ||
        t == AudioDeviceType.bluetoothSco ||
        t == AudioDeviceType.bluetoothLe)) {
      return AudioOutputRoute.bluetooth;
    }
    if (has((t) =>
        t == AudioDeviceType.wiredHeadset ||
        t == AudioDeviceType.wiredHeadphones ||
        t == AudioDeviceType.hearingAid)) {
      return AudioOutputRoute.headphones;
    }
    if (has((t) =>
        t == AudioDeviceType.usbAudio ||
        t == AudioDeviceType.hdmi ||
        t == AudioDeviceType.lineAnalog)) {
      return AudioOutputRoute.externalSpeaker;
    }

    final onlyBuiltIn = devices.every((d) =>
        d.type == AudioDeviceType.speaker ||
        d.type == AudioDeviceType.earpiece ||
        d.type.name.toLowerCase().contains('speaker') ||
        d.type.name.toLowerCase().contains('builtin'));
    if (onlyBuiltIn || devices.length == 1) {
      return AudioOutputRoute.builtInSpeaker;
    }
    return AudioOutputRoute.unknown;
  }

  static String _labelFor(List<AudioDevice> devices, AudioOutputRoute route) {
    if (devices.isEmpty) return 'Built-in';
    for (final d in devices) {
      final n = d.name.trim();
      if (n.isEmpty) continue;
      final t = d.type;
      if (t == AudioDeviceType.speaker || t == AudioDeviceType.earpiece) {
        continue;
      }
      return n;
    }
    return devices.first.name.trim().isNotEmpty
        ? devices.first.name.trim()
        : route.name;
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }
}
