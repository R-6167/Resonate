import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/models/song.dart';
import 'package:resonate/modes/models/media_type.dart';
import 'package:resonate/modes/models/mode_media_item.dart';
import 'package:resonate/modes/providers/mode_provider.dart';
import 'package:resonate/modes/services/mode_content_resolver.dart';
import 'package:resonate/modes/models/resonate_mode.dart';
import 'package:resonate/modes/services/mode_policy_catalog.dart';



Song _song(String id) => Song(
  id: id,
  title: id,
  artist: 'Test Artist',
  album: 'Test Album',
  filePath: '/music/$id.mp3',
  duration: const Duration(minutes: 3),
  dateAdded: DateTime(2026, 1, 1),
);

Future<ModeProvider> _mode(
  ResonateMode mode,
  Map<String, MediaType> types,
) async {
  final provider = ModeProvider();
  await provider.ready;
  await provider.setMode(mode);
  for (final entry in types.entries) {
    await provider.setUserMediaType(
      ModeMediaItem(
        id: entry.key,
        filePath: '/media/\${entry.key}.mp3',
        title: entry.key,
      ),
      entry.value,
    );
  }
  return provider;

  test('ModeContentResolver preserves the canonical candidate set in Normal mode', () async {
    final provider = await _mode(ResonateMode.normal, {});
    final songs = <Song>[
      _song('music'),
      Song(
        id: 'empty',
        title: 'empty',
        artist: 'Test Artist',
        album: 'Test Album',
        filePath: '',
        duration: const Duration(minutes: 1),
        dateAdded: DateTime(2026, 1, 1),
      ),
      _song('podcast'),
    ];

    final resolved = const ModeContentResolver().resolve(
      modes: provider,
      songs: songs,
    );

    expect(resolved.map((song) => song.id), ['music', 'empty', 'podcast']);
    expect(const ModeContentResolver().accepts(provider, songs[1]), isTrue);
  });

  test('ModeContentResolver strictly excludes avoided media and missing paths', () async {
    final provider = await _mode(
      ResonateMode.running,
      {
        'music': MediaType.music,
        'podcast': MediaType.podcast,
        'audiobook': MediaType.audiobook,
        'unknown': MediaType.unknown,
      },
    );
    final songs = [
      _song('music'),
      _song('podcast'),
      _song('audiobook'),
      _song('unknown'),
      Song(
        id: 'missing-path',
        title: 'missing-path',
        artist: 'Test Artist',
        album: 'Test Album',
        filePath: '',
        duration: const Duration(minutes: 1),
        dateAdded: DateTime(2026, 1, 1),
      ),
    ];

    final resolved = const ModeContentResolver().resolve(
      modes: provider,
      songs: songs,
    );

    expect(resolved.map((song) => song.id), ['music', 'unknown']);
    expect(const ModeContentResolver().accepts(provider, songs[1]), isFalse);
    expect(const ModeContentResolver().accepts(provider, songs[4]), isFalse);
  });

  test('preferred media is reordered without permitting avoided media', () async {
    final provider = await _mode(
      ResonateMode.running,
      {
        'unknown': MediaType.unknown,
        'music': MediaType.music,
        'podcast': MediaType.podcast,
      },
    );
    final songs = [_song('unknown'), _song('music'), _song('podcast')];

    final preferred = const ModeContentResolver().resolve(
      modes: provider,
      songs: songs,
    );
    final acceptedOrder = const ModeContentResolver().resolve(
      modes: provider,
      songs: songs,
      preferPreferredContent: false,
    );

    expect(preferred.map((song) => song.id), ['music', 'unknown']);
    expect(acceptedOrder.map((song) => song.id), ['unknown', 'music']);
    expect(preferred, isNot(contains(songs[2])));
  });

  test('limit is applied after mode acceptance and preference ordering', () async {
    final provider = await _mode(
      ResonateMode.motivation,
      {
        'unknown': MediaType.unknown,
        'music': MediaType.music,
        'motivation': MediaType.motivation,
      },
    );
    final resolved = const ModeContentResolver().resolve(
      modes: provider,
      songs: [_song('unknown'), _song('music'), _song('motivation')],
      limit: 2,
    );

    expect(resolved.map((song) => song.id), ['motivation', 'music']);
  });

  test('resolver has no fallback when a mode accepts no candidates', () async {
    final provider = await _mode(
      ResonateMode.audiobook,
      {
        'music': MediaType.music,
        'podcast': MediaType.podcast,
      },
    );

    final resolved = const ModeContentResolver().resolve(
      modes: provider,
      songs: [_song('music'), _song('podcast')],
    );

    expect(resolved, isEmpty);
  });

}

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

  test('policy matrix preserves cross-feature invariants for every mode', () {
    for (final mode in ResonateMode.values) {
      final p = ModePolicyCatalog.policyFor(mode);

      // Capability and preference are independent: a mode may permit
      // crossfade while choosing not to prefer it.
      if (!p.crossfadeAllowed) {
        expect(
          p.preferCrossfade,
          isFalse,
          reason: '$mode cannot prefer a capability it explicitly blocks',
        );
      }

      // Speech modes are precise and conservative; music-oriented modes may
      // use ordinary crossfade behavior.
      if (mode == ResonateMode.podcast ||
          mode == ResonateMode.audiobook) {
        expect(p.preciseResume, isTrue);
        expect(p.speedControlsEmphasized, isTrue);
        expect(p.sleepTimerSuggested, isTrue);
        expect(p.shuffleAllowed, isFalse);
        expect(p.crossfadeAllowed, isFalse);
      }

      // Reduced/minimal UI is only a presentation policy; it must not imply
      // that canonical playback capability disappears.
      expect(p.uiDensity, isNotNull);

      // Preferred content is a bias, while avoided content is a hard
      // generated-content exclusion enforced by ModeContentResolver.
      expect(p.preferredMediaTypes, isNotNull);
      expect(p.avoidedMediaTypes, isNotNull);
    }
  });

  test('mode policy separates capability, preference, and automation authority', () {
    final work = ModePolicyCatalog.policyFor(ResonateMode.work);
    final motivation = ModePolicyCatalog.policyFor(ResonateMode.motivation);
    final running = ModePolicyCatalog.policyFor(ResonateMode.running);
    final driving = ModePolicyCatalog.policyFor(ResonateMode.driving);

    expect(work.crossfadeAllowed, isTrue);
    expect(work.preferCrossfade, isFalse);
    expect(work.automationElevated, isFalse);

    expect(motivation.crossfadeAllowed, isTrue);
    expect(motivation.preferCrossfade, isFalse);
    expect(motivation.automationElevated, isFalse);

    expect(running.crossfadeAllowed, isTrue);
    expect(running.automationElevated, isTrue);

    expect(driving.crossfadeAllowed, isTrue);
    expect(driving.automationElevated, isTrue);
    expect(driving.preferLongSessions, isTrue);

    // Elevated automation is a policy signal, not a playback capability.
    // The actual authority remains in the host playback engine.
    expect(
      running.automationElevated || driving.automationElevated,
      isTrue,
    );
  });

  test('every mode has a deterministic policy', () {
    for (final mode in ResonateMode.values) {
      expect(ModePolicyCatalog.policyFor(mode).mode, mode);
    }
  });
}
