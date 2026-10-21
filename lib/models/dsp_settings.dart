import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Canonical, versioned snapshot for Resonate's native DSP user settings.
///
/// Fields remain independent by design: EQ preamp is not DVC, and neither is
/// the transport/crossfade envelope. Existing preference keys are read as a
/// migration source; new writes use one JSON document.
class DspSettings {
  static const int schemaVersion = 2;
  static const String preferenceKey = 'resonate_dsp_settings_v1';
  static Future<void> _writeQueue = Future<void>.value();

  final bool masterEnabled;
  final bool eqEnabled;
  final String preset;
  final List<double> eqBandGainsDb;
  final double preampDb;
  final bool autoEqHeadroom;
  final double dvcDb;
  /// Legacy single-ceiling field retained for old call sites and migrations.
  final double limiterCeilingDb;
  final double limiterHighCeilingDb;
  final double limiterLowCeilingDb;
  final double crossoverHz;
  final bool speakerProtectionEnabled;
  final double virtualBassAmount;
  final bool effectsEnabled;
  final double reverbAmount;
  final double virtualizerAmount;

  DspSettings({
    this.masterEnabled = false,
    this.eqEnabled = true,
    this.preset = 'Flat',
    List<double> eqBandGainsDb = const [],
    this.preampDb = 0,
    this.autoEqHeadroom = false,
    this.dvcDb = 0,
    this.limiterCeilingDb = -1,
    this.limiterHighCeilingDb = -0.5,
    this.limiterLowCeilingDb = -0.2,
    this.crossoverHz = 120,
    this.speakerProtectionEnabled = false,
    this.virtualBassAmount = 0,
    this.effectsEnabled = true,
    this.reverbAmount = 0,
    this.virtualizerAmount = 0,
  }) : eqBandGainsDb = List<double>.unmodifiable(
          eqBandGainsDb.map((v) => _clamp(v, -12, 12)),
        );

  static double _clamp(double value, double min, double max) =>
      value.isFinite ? value.clamp(min, max).toDouble() : 0.0;

  DspSettings copyWith({
    bool? masterEnabled,
    bool? eqEnabled,
    String? preset,
    List<double>? eqBandGainsDb,
    double? preampDb,
    bool? autoEqHeadroom,
    double? dvcDb,
    double? limiterCeilingDb,
    double? limiterHighCeilingDb,
    double? limiterLowCeilingDb,
    double? crossoverHz,
    bool? speakerProtectionEnabled,
    double? virtualBassAmount,
    bool? effectsEnabled,
    double? reverbAmount,
    double? virtualizerAmount,
  }) => DspSettings(
        masterEnabled: masterEnabled ?? this.masterEnabled,
        eqEnabled: eqEnabled ?? this.eqEnabled,
        preset: preset ?? this.preset,
        eqBandGainsDb: eqBandGainsDb ?? this.eqBandGainsDb,
        preampDb: _clamp(preampDb ?? this.preampDb, -6, 6),
        autoEqHeadroom: autoEqHeadroom ?? this.autoEqHeadroom,
        dvcDb: _clamp(dvcDb ?? this.dvcDb, -24, 6),
        limiterCeilingDb: _clamp(limiterCeilingDb ?? this.limiterCeilingDb, -12, 0),
        limiterHighCeilingDb: _clamp(
          limiterHighCeilingDb ?? limiterCeilingDb ?? this.limiterHighCeilingDb,
          -6, -0.1),
        limiterLowCeilingDb: _clamp(
          limiterLowCeilingDb ?? limiterCeilingDb ?? this.limiterLowCeilingDb,
          -6, -0.1),
        crossoverHz: _clamp(crossoverHz ?? this.crossoverHz, 80, 200),
        speakerProtectionEnabled: speakerProtectionEnabled ?? this.speakerProtectionEnabled,
        virtualBassAmount: _clamp(virtualBassAmount ?? this.virtualBassAmount, 0, 1),
        effectsEnabled: effectsEnabled ?? this.effectsEnabled,
        reverbAmount: _clamp(reverbAmount ?? this.reverbAmount, 0, 1),
        virtualizerAmount: _clamp(virtualizerAmount ?? this.virtualizerAmount, 0, 1),
      );

  Map<String, dynamic> toJson() => {
        'version': schemaVersion,
        'masterEnabled': masterEnabled,
        'eqEnabled': eqEnabled,
        'preset': preset,
        'eqBandGainsDb': eqBandGainsDb,
        'preampDb': preampDb,
        'autoEqHeadroom': autoEqHeadroom,
        'dvcDb': dvcDb,
        'limiterCeilingDb': limiterCeilingDb,
        'limiterHighCeilingDb': limiterHighCeilingDb,
        'limiterLowCeilingDb': limiterLowCeilingDb,
        'crossoverHz': crossoverHz,
        'speakerProtectionEnabled': speakerProtectionEnabled,
        'virtualBassAmount': virtualBassAmount,
        'effectsEnabled': effectsEnabled,
        'reverbAmount': reverbAmount,
        'virtualizerAmount': virtualizerAmount,
      };

  factory DspSettings.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version != 1 && version != schemaVersion) {
      throw const FormatException('Unsupported Resonate DSP settings version.');
    }
    double number(String key, double fallback, double min, double max) {
      final value = json[key];
      if (value is! num || !value.toDouble().isFinite) return fallback;
      return value.toDouble().clamp(min, max).toDouble();
    }

    final rawBands = json['eqBandGainsDb'];
    final bands = rawBands is List
        ? rawBands.whereType<num>().map((v) => _clamp(v.toDouble(), -12, 12)).toList()
        : <double>[];
    return DspSettings(
      masterEnabled: json['masterEnabled'] is bool ? json['masterEnabled'] as bool : false,
      eqEnabled: json['eqEnabled'] is bool ? json['eqEnabled'] as bool : true,
      preset: json['preset'] is String ? json['preset'] as String : 'Flat',
      eqBandGainsDb: bands,
      preampDb: number('preampDb', 0, -6, 6),
      autoEqHeadroom: json['autoEqHeadroom'] is bool ? json['autoEqHeadroom'] as bool : false,
      dvcDb: number('dvcDb', 0, -24, 6),
      limiterCeilingDb: number('limiterCeilingDb', -1, -12, 0),
      limiterHighCeilingDb: number(
        'limiterHighCeilingDb',
        version == 1 ? number('limiterCeilingDb', -0.5, -6, -0.1) : -0.5,
        -6, -0.1,
      ),
      limiterLowCeilingDb: number(
        'limiterLowCeilingDb',
        version == 1 ? number('limiterCeilingDb', -0.2, -6, -0.1) : -0.2,
        -6, -0.1,
      ),
      crossoverHz: number('crossoverHz', 120, 80, 200),
      speakerProtectionEnabled: json['speakerProtectionEnabled'] is bool ? json['speakerProtectionEnabled'] as bool : false,
      virtualBassAmount: number('virtualBassAmount', 0, 0, 1),
      effectsEnabled: json['effectsEnabled'] is bool ? json['effectsEnabled'] as bool : true,
      reverbAmount: number('reverbAmount', 0, 0, 1),
      virtualizerAmount: number('virtualizerAmount', 0, 0, 1),
    );
  }

  static DspSettings _readFromPreferences(SharedPreferences prefs) {
    final raw = prefs.getString(preferenceKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return DspSettings.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {
        // Invalid/future schema falls through to legacy migration and safe defaults.
      }
    }
    final hasLegacyBands = List<int>.generate(31, (i) => i)
        .any((i) => prefs.containsKey('eq_studio_band_$i'));
    final bandGains = hasLegacyBands
        ? List<double>.generate(31, (i) => prefs.getDouble('eq_studio_band_$i') ?? 0.0)
        : <double>[];
    return DspSettings(
      masterEnabled: prefs.getBool('equalizer_native_dsp') ?? false,
      eqEnabled: prefs.getBool('equalizer_enabled') ?? true,
      preset: prefs.getString('equalizer_preset') ?? 'Flat',
      eqBandGainsDb: bandGains,
      preampDb: prefs.getDouble('equalizer_preamp') ?? 0,
      autoEqHeadroom: prefs.getBool('equalizer_auto_headroom') ?? false,
      dvcDb: prefs.getDouble('live_dsp_dvc_db_v1') ?? 0,
      effectsEnabled: prefs.getBool('effects_enabled') ?? true,
      reverbAmount: prefs.getDouble('reverb') ?? 0,
      virtualizerAmount: prefs.getDouble('virtualizer') ?? 0,
    );
  }

  static Future<DspSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = _readFromPreferences(prefs);
    if (prefs.getString(preferenceKey) == null) {
      await save(settings);
    } else {
      try {
        final decoded = jsonDecode(prefs.getString(preferenceKey)!);
        if (decoded is! Map || decoded['version'] != schemaVersion) {
          await save(settings);
        }
      } catch (_) {
        await save(settings);
      }
    }
    return settings;
  }

  /// Atomically read-modify-write the latest canonical snapshot.
  ///
  /// The transform runs inside the same serialized queue as the write, so
  /// overlapping controls cannot save a stale full snapshot over a newer one.
  static Future<void> update(DspSettings Function(DspSettings current) transform) {
    _writeQueue = _writeQueue.catchError((_) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final current = _readFromPreferences(prefs);
      final next = transform(current);
      await prefs.setString(preferenceKey, jsonEncode(next.toJson()));
    });
    return _writeQueue;
  }

  /// Save a complete snapshot. Prefer [update] for individual control changes.
  static Future<void> save(DspSettings settings) {
    final snapshot = jsonEncode(settings.toJson());
    _writeQueue = _writeQueue.catchError((_) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(preferenceKey, snapshot);
    });
    return _writeQueue;
  }
}
