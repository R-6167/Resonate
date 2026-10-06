import 'package:flutter_test/flutter_test.dart';
import 'package:resonate_modes_lab/modes/models/media_type.dart';
import 'package:resonate_modes_lab/modes/models/resonate_mode.dart';
import 'package:resonate_modes_lab/modes/services/mode_policy_catalog.dart';

void main() {
  test('speech modes disable music-style transitions', () {
    expect(ModePolicyCatalog.policyFor(ResonateMode.podcast).crossfadeAllowed, isFalse);
    expect(ModePolicyCatalog.policyFor(ResonateMode.audiobook).crossfadeAllowed, isFalse);
    expect(ModePolicyCatalog.policyFor(ResonateMode.podcast).shuffleAllowed, isFalse);
    expect(ModePolicyCatalog.policyFor(ResonateMode.audiobook).shuffleAllowed, isFalse);
  });

  test('running and driving prefer music and avoid long-form speech', () {
    for (final mode in [ResonateMode.running, ResonateMode.driving]) {
      final p = ModePolicyCatalog.policyFor(mode);
      expect(p.preferredMediaTypes, contains(MediaType.music));
      expect(p.avoidedMediaTypes, contains(MediaType.podcast));
      expect(p.avoidedMediaTypes, contains(MediaType.audiobook));
    }
  });

  test('every mode has a deterministic policy', () {
    for (final mode in ResonateMode.values) {
      expect(ModePolicyCatalog.policyFor(mode).mode, mode);
    }
  });
}
