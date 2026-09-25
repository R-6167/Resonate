#!/usr/bin/env python3
"""Whole-track structure (start+end PCM), random SFX rack in music_provider."""
from pathlib import Path

# ---------- Native: startMs on extractPcmWindow ----------
MA = Path('android/app/src/main/kotlin/com/Aetherion/Resonate/MainActivity.kt')
if MA.exists():
    ma = MA.read_text()
    old_call = '''"extractPcmWindow" -> extractPcmWindow(
                    call.argument<String>("uri") ?: "",
                    (call.argument<Number>("maxSeconds") ?: 12.0).toDouble(),
                    result,'''
    new_call = '''"extractPcmWindow" -> extractPcmWindow(
                    call.argument<String>("uri") ?: "",
                    (call.argument<Number>("maxSeconds") ?: 12.0).toDouble(),
                    (call.argument<Number>("startMs") ?: 0).toLong(),
                    result,'''
    if 'startMs' not in ma.split('extractPcmWindow')[1][:200]:
        if old_call not in ma:
            print('WARN MA call miss')
        else:
            ma = ma.replace(old_call, new_call, 1)
            print('MA call startMs')
    old_sig = 'private fun extractPcmWindow(uriString: String, maxSeconds: Double, result: MethodChannel.Result)'
    new_sig = 'private fun extractPcmWindow(uriString: String, maxSeconds: Double, startMs: Long, result: MethodChannel.Result)'
    if old_sig in ma:
        ma = ma.replace(old_sig, new_sig, 1)
        print('MA sig')
    # seek after selectTrack
    seek_anchor = 'extractor.selectTrack(audioTrack)\n                val mime = format.getString(MediaFormat.KEY_MIME)'
    seek_ins = '''extractor.selectTrack(audioTrack)
                if (startMs > 0L) {
                    try {
                        extractor.seekTo(startMs * 1000L, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                    } catch (_: Exception) {}
                }
                val mime = format.getString(MediaFormat.KEY_MIME)'''
    if 'SEEK_TO_CLOSEST_SYNC' not in ma and seek_anchor in ma:
        ma = ma.replace(seek_anchor, seek_ins, 1)
        print('MA seek')
    MA.write_text(ma)
else:
    print('WARN no MainActivity path')

# ---------- Estimator: dual-window structure ----------
EST = Path('lib/services/dj_bpm_estimator.dart')
est = EST.read_text()

if 'startMs' not in est or 'estimateStructureWindows' not in est:
    # Expand _estimateFromNativePcm to accept startMs
    old_inv = '''      final raw = await _channel.invokeMethod<dynamic>('extractPcmWindow', {
        'uri': uri,
        'maxSeconds': 15.0,
      });'''
    # We'll replace the whole method with dual-pass version at the call site of estimateFile

if "'startMs':" not in est:
    # Patch invoke to support optional start
    est = est.replace(
        '''      final raw = await _channel.invokeMethod<dynamic>('extractPcmWindow', {
        'uri': uri,
        'maxSeconds': 15.0,
      });''',
        '''      final raw = await _channel.invokeMethod<dynamic>('extractPcmWindow', {
        'uri': uri,
        'maxSeconds': maxSeconds,
        'startMs': startMs,
      });''',
        1,
    )
    # Change method signature of _estimateFromNativePcm
    est = est.replace(
        'Future<DjBpmEstimate?> _estimateFromNativePcm(String uri) async {',
        'Future<DjBpmEstimate?> _estimateFromNativePcm(String uri, {double maxSeconds = 15.0, int startMs = 0, String windowRole = \'start\'}) async {',
        1,
    )
    est = est.replace(
        "windowRole: 'start',",
        'windowRole: windowRole,',
        1,
    )
    print('estimator native args')

# Dual window merge after first native pcm in estimateFile
if 'endWindow' not in est:
    # After successful nativePcm path, try end window merge when duration known
    # Add durationMs optional param to estimateFile
    if 'Future<DjBpmEstimate?> estimateFile(String filePath) async' in est:
        est = est.replace(
            'Future<DjBpmEstimate?> estimateFile(String filePath) async {',
            'Future<DjBpmEstimate?> estimateFile(String filePath, {int? durationMs}) async {',
            1,
        )
        print('estimateFile durationMs')

    # After `final nativePcm = await _estimateFromNativePcm(filePath);`
    old_np = 'final nativePcm = await _estimateFromNativePcm(filePath);'
    new_np = '''final nativePcm = await _estimateFromNativePcm(filePath);
      // Whole-track structure: second window near the end when duration is known.
      DjBpmEstimate? endPcm;
      final dur = durationMs ?? 0;
      if (dur > 45000) {
        final startMs = (dur - 18000).clamp(20000, dur - 8000);
        endPcm = await _estimateFromNativePcm(
          filePath,
          maxSeconds: 14.0,
          startMs: startMs,
          windowRole: 'end',
        );
      }
      final mergedNative = _mergeStructure(nativePcm, endPcm);'''
    if old_np in est:
        est = est.replace(old_np, new_np, 1)
        # replace uses of nativePcm after merge with mergedNative for feature fields
        # careful: only the return paths that use nativePcm structure
        est = est.replace(
            'if (nativePcm != null) {\n        // Prefer tagged BPM when present',
            'if (mergedNative != null) {\n        final nativePcm = mergedNative;\n        // Prefer tagged BPM when present',
            1,
        )
        print('dual window merge hook')

    # Add merge helper before class end or after _estimateFromNativePcm
    if '_mergeStructure' not in est:
        helper = '''
  /// Merge start-window estimate with end-window structure/outro hints.
  DjBpmEstimate? _mergeStructure(DjBpmEstimate? start, DjBpmEstimate? end) {
    if (start == null) return end;
    if (end == null) return start;
    final section = () {
      final s = start.sectionHint;
      final e = end.sectionHint;
      if (e == 'quiet_outro' || e == 'outro') {
        if (s == 'build' || s == 'drop' || s == 'chorus') return s;
        return e;
      }
      return s ?? e;
    }();
    return DjBpmEstimate(
      bpm: start.bpm > 0 ? start.bpm : end.bpm,
      confidence: start.confidence >= end.confidence ? start.confidence : end.confidence,
      beatOffsetMs: start.beatOffsetMs,
      source: start.source,
      keyRoot: start.keyRoot ?? end.keyRoot,
      keyMode: start.keyMode ?? end.keyMode,
      keyConfidence: start.keyConfidence >= end.keyConfidence
          ? start.keyConfidence
          : end.keyConfidence,
      energy: start.energy ?? end.energy,
      loudness: start.loudness ?? end.loudness,
      introHintMs: start.introHintMs,
      outroHintMs: end.outroHintMs ?? start.outroHintMs,
      sectionHint: section,
    );
  }
'''
        # insert before last closing of class DjBpmEstimator - before parseId3 or at end of class
        marker = '  Future<Uint8List?> _readMediaHeadNative'
        if marker in est:
            est = est.replace(marker, helper + '\n  Future<Uint8List?> _readMediaHeadNative', 1)
            print('merge helper')

EST.write_text(est)

# ---------- Analysis service: pass duration ----------
AS = Path('lib/services/dj_analysis_service.dart')
as_ = AS.read_text()
if 'duration.inMilliseconds' not in as_ and 'estimateFile(song.filePath)' in as_:
    as_ = as_.replace(
        'final estimate = await _estimator.estimateFile(song.filePath);',
        'final estimate = await _estimator.estimateFile(\n        song.filePath,\n        durationMs: song.duration.inMilliseconds,\n      );',
        1,
    )
    AS.write_text(as_)
    print('analysis duration')

# ---------- Idle: treat missing section as refresh-worthy ----------
IDLE = Path('lib/services/dj_idle_analysis_service.dart')
idle = IDLE.read_text()
old_skip = '''          if (existing != null &&
              !existing.isStale &&
              (existing.hasUsableBpm || existing.hasUsableKey)) {
            continue;
          }'''
new_skip = '''          if (existing != null &&
              !existing.isStale &&
              (existing.hasUsableBpm || existing.hasUsableKey) &&
              (existing.sectionHint != null &&
                  existing.sectionHint != 'unknown')) {
            continue;
          }'''
if 'sectionHint != \'unknown\'' not in idle and 'sectionHint != "unknown"' not in idle:
    if old_skip in idle:
        idle = idle.replace(old_skip, new_skip, 1)
        IDLE.write_text(idle)
        print('idle structure refresh')

# ---------- Model version 6 ----------
MOD = Path('lib/models/dj_analysis.dart')
mod = MOD.read_text()
for v in (5, 4):
    if f'currentVersion = {v}' in mod:
        mod = mod.replace(f'currentVersion = {v}', 'currentVersion = 6', 1)
        MOD.write_text(mod)
        print('analysis v6')
        break

# ---------- music_provider: wire DjSfxRack ----------
MP = Path('lib/providers/music_provider.dart')
mp = MP.read_text()

if "import '../services/dj_sfx_rack.dart';" not in mp:
    mp = mp.replace(
        "import '../services/audio_effects_bridge.dart';",
        "import '../services/audio_effects_bridge.dart';\nimport '../services/dj_sfx_rack.dart';",
        1,
    )
    print('import rack')

if 'DjSfxRack' not in mp:
    mp = mp.replace(
        '  bool _djSfxEngaged = false;',
        '  bool _djSfxEngaged = false;\n  final DjSfxRack _djSfxRack = DjSfxRack();',
        1,
    )
    print('rack field')

# Replace engage body to use rack
old_eng = None
if "style': 'club_open'" in mp or 'club_open' in mp:
    # find engage function and replace entirely until tick
    start = mp.find('  Future<void> _engageDjTransitionSfx({double energyScore = 0.5}) async {')
    tick = mp.find('  /// Progress-based club filter-sweep')
    if tick < 0:
        tick = mp.find('  Future<void> _tickDjClubFxSweep')
    rest = mp.find('  Future<void> _restoreDjTransitionSfx() async {')
    if start > 0 and rest > start:
        new_block = '''  Future<void> _engageDjTransitionSfx({double energyScore = 0.5}) async {
    if (!_djSfxActive) return;
    try {
      await _djSfxRack.engage(
        energyScore: energyScore,
        equalizerA: _equalizerA,
        equalizerB: _equalizerB,
      );
      _djSfxEngaged = true;
      await ResonateDiagnostics.record('dj_transition_sfx', {
        'action': 'engage',
        'preset': _djSfxRack.presetName,
        'energyScore': energyScore,
      });
    } catch (e) {
      debugPrint('DJ transition SFX engage: $e');
    }
  }

  Future<void> _tickDjClubFxSweep(double t) async {
    if (!_djSfxEngaged) return;
    await _djSfxRack.tick(
      t,
      equalizerA: _equalizerA,
      equalizerB: _equalizerB,
      energyScore: _lastDjEnergyScore,
    );
  }

'''
        mp = mp[:start] + new_block + mp[rest:]
        print('engage/tick via rack')

# Restore via rack
if '_djSfxRack.restore' not in mp:
    start = mp.find('  Future<void> _restoreDjTransitionSfx() async {')
    end = mp.find('  /// Step 2', start)
    if end < 0:
        end = mp.find('\n  Future<void> _prepareDjHandoff', start)
    if start > 0 and end > start:
        new_res = '''  Future<void> _restoreDjTransitionSfx() async {
    if (!_djSfxEngaged && !_djSfxActive && !_djSfxRack.engaged) return;
    try {
      final preset = _djSfxRack.presetName;
      await _djSfxRack.restore(
        equalizerA: _equalizerA,
        equalizerB: _equalizerB,
      );
      _djSfxEngaged = false;
      await ResonateDiagnostics.record('dj_transition_sfx', {
        'action': 'restore',
        'preset': preset,
      });
    } catch (e) {
      _djSfxEngaged = false;
      debugPrint('DJ transition SFX restore: $e');
    }
  }

'''
        mp = mp[:start] + new_res + mp[end:]
        print('restore via rack')

MP.write_text(mp)
print('ALL STRUCTURE+SFX V2 DONE')
