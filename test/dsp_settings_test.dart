import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resonate/models/dsp_settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DspSettings', () {
    test('round trips a versioned independent DSP snapshot', () {
      final settings = DspSettings(
        masterEnabled: true,
        eqEnabled: false,
        preset: 'Custom',
        eqBandGainsDb: [3, -2, 1],
        preampDb: -4,
        dvcDb: 2.5,
        virtualBassAmount: 0.4,
      );
      final restored = DspSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
      );
      expect(restored.masterEnabled, isTrue);
      expect(restored.eqEnabled, isFalse);
      expect(restored.preampDb, -4);
      expect(restored.dvcDb, 2.5);
      expect(restored.eqBandGainsDb, [3, -2, 1]);
      expect(restored.virtualBassAmount, 0.4);
    });

    test('clamps controls independently and rejects unknown schema', () {
      final settings = DspSettings().copyWith(
        preampDb: 20,
        dvcDb: -50,
        virtualBassAmount: 2,
        reverbAmount: double.nan,
      );
      expect(settings.preampDb, 6);
      expect(settings.dvcDb, -24);
      expect(settings.virtualBassAmount, 1);
      expect(settings.reverbAmount, 0);
      expect(
        () => DspSettings.fromJson({'version': 999}),
        throwsFormatException,
      );
    });

    test('migrates legacy DVC and EQ values to the versioned document', () async {
      SharedPreferences.setMockInitialValues({
        'live_dsp_dvc_db_v1': 3.0,
        'equalizer_enabled': false,
        'equalizer_preamp': -2.0,
        'eq_studio_band_1': 4.0,
      });
      final settings = await DspSettings.load();
      expect(settings.dvcDb, 3);
      expect(settings.eqEnabled, isFalse);
      expect(settings.preampDb, -2);
      expect(settings.eqBandGainsDb.length, 31);
      expect(settings.eqBandGainsDb[0], 0);
      expect(settings.eqBandGainsDb[1], 4);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(DspSettings.preferenceKey), isNotNull);
    });

    test('non-finite EQ band values fall back safely', () {
      final settings = DspSettings(eqBandGainsDb: [double.infinity, 20, -20]);
      expect(settings.eqBandGainsDb, [0, 12, -12]);
    });
  });
}
