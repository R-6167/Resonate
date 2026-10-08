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

    for (final mode in ResonateMode.values) {
      expect(
        ModePolicyCatalog.policyFor(mode).autoNextPreferred,
        isTrue,
        reason: 'Current modes all permit automatic next-track behavior: $mode',
      );
    }
  });

  test('DJ handoff authority follows the Mode crossfade capability matrix', () {
    final blocked = [ResonateMode.podcast, ResonateMode.audiobook];
    final enabled = [
      ResonateMode.normal,
      ResonateMode.running,
      ResonateMode.driving,
      ResonateMode.work,
      ResonateMode.motivation,
    ];

    for (final mode in blocked) {
      final p = ModePolicyCatalog.policyFor(mode);
      expect(
        p.crossfadeAllowed,
        isFalse,
        reason: '$mode must block DJ/crossfade handoffs at the Mode boundary',
      );
    }

    for (final mode in enabled) {
      final p = ModePolicyCatalog.policyFor(mode);
      expect(
        p.crossfadeAllowed,
        isTrue,
        reason: '$mode permits DJ/crossfade handoffs when the user has enabled crossfade',
      );
    }

    // Preference is intentionally distinct from capability: Work and
    // Motivation may prefer ordinary transitions while still permitting the
    // user's DJ/crossfade capability.
    expect(
      ModePolicyCatalog.policyFor(ResonateMode.work).preferCrossfade,
      isFalse,
    );
    expect(
      ModePolicyCatalog.policyFor(ResonateMode.motivation).preferCrossfade,
      isFalse,
    );
  });

  test('every mode has a deterministic policy', () {
    for (final mode in ResonateMode.values) {
      expect(ModePolicyCatalog.policyFor(mode).mode, mode);
    }
  });
}
