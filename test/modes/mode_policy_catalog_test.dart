import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/modes/models/media_type.dart';
import 'package:resonate/modes/models/resonate_mode.dart';
import 'package:resonate/modes/services/mode_policy_catalog.dart';

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

  test('mode transition and session preferences are explicit', () {
    expect(ModePolicyCatalog.policyFor(ResonateMode.normal).preferCrossfade, isTrue);
    expect(ModePolicyCatalog.policyFor(ResonateMode.running).preferCrossfade, isTrue);
    expect(ModePolicyCatalog.policyFor(ResonateMode.driving).preferCrossfade, isTrue);
    expect(ModePolicyCatalog.policyFor(ResonateMode.work).preferCrossfade, isFalse);
    expect(ModePolicyCatalog.policyFor(ResonateMode.podcast).preferCrossfade, isFalse);
    expect(ModePolicyCatalog.policyFor(ResonateMode.audiobook).preferCrossfade, isFalse);

    expect(ModePolicyCatalog.policyFor(ResonateMode.running).automationElevated, isTrue);
    expect(ModePolicyCatalog.policyFor(ResonateMode.driving).automationElevated, isTrue);
    expect(ModePolicyCatalog.policyFor(ResonateMode.driving).preferLongSessions, isTrue);
    expect(ModePolicyCatalog.policyFor(ResonateMode.work).preferLongSessions, isTrue);
    expect(ModePolicyCatalog.policyFor(ResonateMode.podcast).preferLongSessions, isTrue);
    expect(ModePolicyCatalog.policyFor(ResonateMode.audiobook).preferLongSessions, isTrue);
    expect(ModePolicyCatalog.policyFor(ResonateMode.normal).preferLongSessions, isFalse);
  });

  test('every mode has a deterministic policy', () {
    for (final mode in ResonateMode.values) {
      expect(ModePolicyCatalog.policyFor(mode).mode, mode);
    }
  });
}
