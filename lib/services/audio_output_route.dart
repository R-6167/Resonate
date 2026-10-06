import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// Where audio is actually going — drives EQ / live DSP delivery policy.
enum AudioOutputRoute {
  /// Built-in earpiece / loudspeaker (limited LF, easy to distort).
  builtInSpeaker,

  /// Wired or USB headphones / headset.
  headphones,

  /// Bluetooth A2DP / LE audio / SCO (headphones, buds, etc.).
  bluetooth,

  /// External speaker, soundbar, HDMI, line-out.
  externalSpeaker,

  /// Car / vehicle audio (carAudio type or BT name heuristics).
  car,

  unknown,
}

/// Watches [AudioSession] devices and classifies the active output route.
///
/// Classification is conservative for speaker protection and uses device-name
/// heuristics so car kits that report as generic A2DP still map to [car].
class AudioOutputRouteService extends ChangeNotifier {
  AudioOutputRouteService._();
  static final AudioOutputRouteService instance = AudioOutputRouteService._();

  AudioOutputRoute _route = AudioOutputRoute.unknown;
  String _deviceLabel = '';
  StreamSubscription<AudioDevicesChangedEvent>? _sub;
  bool _started = false;
  Timer? _debounce;
  DateTime? _lastRefreshAt;

  AudioOutputRoute get route => _route;
  String get deviceLabel => _deviceLabel;

  /// True when aggressive EQ / boost should be tempered (phone speaker).
  bool get needsSpeakerProtection =>
      _route == AudioOutputRoute.builtInSpeaker ||
      _route == AudioOutputRoute.unknown;

  /// True when full DSP potential is appropriate (HP / BT / car / external).
  bool get allowsFullDsp => !needsSpeakerProtection;

  /// Suggested virtual-bass amount for the current route (0–1).
  double get suggestedVirtualBass => switch (_route) {
        AudioOutputRoute.builtInSpeaker => 0.62,
        AudioOutputRoute.unknown => 0.40,
        AudioOutputRoute.headphones => 0.14,
        AudioOutputRoute.bluetooth => 0.18,
        AudioOutputRoute.externalSpeaker => 0.08,
        AudioOutputRoute.car => 0.0, // car systems already have LF energy
      };

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
        // Debounce OEM bursts of device add/remove during BT handshakes.
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 280), () {
          unawaited(refresh(session));
        });
      });
    } catch (e) {
      debugPrint('AudioOutputRouteService.start failed: $e');
    }
  }

  Future<void> refresh([AudioSession? session]) async {
    final now = DateTime.now();
    if (_lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < const Duration(milliseconds: 120)) {
      return;
    }
    _lastRefreshAt = now;
    try {
      session ??= await AudioSession.instance;
      final devices =
          (await session.getDevices(includeInputs: false, includeOutputs: true))
              .toList();
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

  /// Force a refresh (e.g. after play starts or session attaches).
  Future<void> refreshNow() => refresh();

  static AudioOutputRoute _classify(List<AudioDevice> devices) {
    if (devices.isEmpty) return AudioOutputRoute.builtInSpeaker;

    // Prefer explicit types first, then name heuristics on remaining devices.
    bool hasType(bool Function(AudioDeviceType t) pred) =>
        devices.any((d) => pred(d.type));

    if (hasType((t) => t == AudioDeviceType.carAudio)) {
      return AudioOutputRoute.car;
    }

    // Name-based car detection (many head units expose only A2DP).
    for (final d in devices) {
      if (_looksLikeCar(d.name)) return AudioOutputRoute.car;
    }

    if (hasType((t) =>
        t == AudioDeviceType.wiredHeadset ||
        t == AudioDeviceType.wiredHeadphones ||
        t == AudioDeviceType.hearingAid)) {
      return AudioOutputRoute.headphones;
    }

    if (hasType((t) =>
        t == AudioDeviceType.bluetoothA2dp ||
        t == AudioDeviceType.bluetoothSco ||
        t == AudioDeviceType.bluetoothLe)) {
      // BT already checked for car names above.
      for (final d in devices) {
        if (_looksLikeHeadphones(d.name)) return AudioOutputRoute.headphones;
      }
      return AudioOutputRoute.bluetooth;
    }

    if (hasType((t) =>
        t == AudioDeviceType.usbAudio ||
        t == AudioDeviceType.hdmi ||
        t == AudioDeviceType.lineAnalog)) {
      return AudioOutputRoute.externalSpeaker;
    }

    // Only built-in listed.
    if (devices.every((d) =>
        d.type == AudioDeviceType.builtInSpeaker ||
        d.type == AudioDeviceType.builtInEarpiece)) {
      return AudioOutputRoute.builtInSpeaker;
    }

    return AudioOutputRoute.builtInSpeaker;
  }

  static bool _looksLikeCar(String raw) {
    final n = raw.toLowerCase();
    if (n.isEmpty) return false;
    const keys = [
      'car',
      'auto',
      'vehicle',
      'android auto',
      'carplay',
      'toyota',
      'honda',
      'ford',
      'bmw',
      'mercedes',
      'hyundai',
      'kia',
      'subaru',
      'nissan',
      'mazda',
      'vw',
      'volkswagen',
      'audi',
      'gm',
      'chevrolet',
      'uconnect',
      'sync',
      'entune',
      'mymitra',
      'car audio',
    ];
    return keys.any(n.contains);
  }

  static bool _looksLikeHeadphones(String raw) {
    final n = raw.toLowerCase();
    if (n.isEmpty) return false;
    const keys = [
      'headphone',
      'headset',
      'buds',
      'airpods',
      'earphone',
      'wh-',
      'sony wh',
      'bose',
      'galaxy buds',
      'pixel buds',
      'freebuds',
      'earbuds',
      'iem',
    ];
    return keys.any(n.contains);
  }

  static String _labelFor(List<AudioDevice> devices, AudioOutputRoute route) {
    if (devices.isEmpty) return 'Built-in';
    for (final d in devices) {
      final n = d.name.trim();
      if (n.isEmpty) continue;
      final t = d.type;
      if (t == AudioDeviceType.bluetoothA2dp ||
          t == AudioDeviceType.bluetoothSco ||
          t == AudioDeviceType.bluetoothLe ||
          t == AudioDeviceType.wiredHeadset ||
          t == AudioDeviceType.wiredHeadphones ||
          t == AudioDeviceType.hearingAid ||
          t == AudioDeviceType.usbAudio ||
          t == AudioDeviceType.hdmi ||
          t == AudioDeviceType.lineAnalog ||
          t == AudioDeviceType.carAudio) {
        return n;
      }
    }
    final fallback = devices.first.name.trim();
    return fallback.isNotEmpty ? fallback : route.name;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    unawaited(_sub?.cancel());
    super.dispose();
  }
}
