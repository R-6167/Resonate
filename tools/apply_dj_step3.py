#!/usr/bin/env python3
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
MP = ROOT / "lib/providers/music_provider.dart"
FRAG = Path(__file__).with_name("frag_dj_step3_method.txt")

def main() -> int:
    mt = MP.read_text()
    if "_prepareDjHandoff" in mt and "_djTempoMatchActive" in mt:
        print("step3 already"); return 0
    if "configureDjMode" not in mt:
        print("need step2"); return 1
    METHOD = FRAG.read_text()
    if "_djTempoMatchActive" not in mt:
        mt = mt.replace(
            "  bool _djBeatAlignActive = false;\n  DjAnalysisService? _djAnalysis;\n",
            "  bool _djBeatAlignActive = false;\n  bool _djTempoMatchActive = false;\n  int _djMaxStretchPercent = 12;\n  DjAnalysisService? _djAnalysis;\n  double? _djStretchSpeedOut;\n  double? _djStretchSpeedIn;\n",
            1,
        )
    old_cfg = (
        "  void configureDjMode({\n"
        "    required bool beatAlignActive,\n"
        "    DjAnalysisService? analysis,\n"
        "  }) {\n"
        "    _djBeatAlignActive = beatAlignActive;\n"
        "    _djAnalysis = analysis;\n"
        "  }"
    )
    new_cfg = (
        "  void configureDjMode({\n"
        "    required bool beatAlignActive,\n"
        "    bool tempoMatchActive = false,\n"
        "    int maxStretchPercent = 12,\n"
        "    DjAnalysisService? analysis,\n"
        "  }) {\n"
        "    _djBeatAlignActive = beatAlignActive;\n"
        "    _djTempoMatchActive = tempoMatchActive;\n"
        "    _djMaxStretchPercent = maxStretchPercent.clamp(3, 20);\n"
        "    _djAnalysis = analysis;\n"
        "  }"
    )
    if old_cfg in mt:
        mt = mt.replace(old_cfg, new_cfg, 1)
    start = mt.find("  /// When DJ Mode beat-align is active")
    if start < 0:
        start = mt.find("  Future<void> _maybeBeatAlignIncoming")
    end = mt.find("  Future<bool> _performTrueCrossfade")
    if start < 0 or end <= start:
        print("bounds", start, end); return 3
    mt = mt[:start] + METHOD + mt[end:]
    mt = mt.replace(
        "      await _maybeBeatAlignIncoming(\n"
        "        outgoing: outgoing,\n"
        "        incoming: incoming,\n"
        "        outgoingSong: outgoingSong,\n"
        "        incomingSong: nextSong,\n"
        "      );",
        "      await _prepareDjHandoff(\n"
        "        outgoing: outgoing,\n"
        "        incoming: incoming,\n"
        "        outgoingSong: outgoingSong,\n"
        "        incomingSong: nextSong,\n"
        "      );",
        1,
    )
    commit = (
        "      try { await incoming.setVolume(master); } catch (_) {}\n"
        "      _activeIsA = !_activeIsA; // Phase 2: only crossfade may leave Engine B active"
    )
    if commit in mt:
        mt = mt.replace(commit,
            "      try { await incoming.setVolume(master); } catch (_) {}\n"
            "      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);\n"
            "      _activeIsA = !_activeIsA; // Phase 2: only crossfade may leave Engine B active", 1)
    old_cancel = (
        "          try { await incoming.stop(); } catch (_) {}\n"
        "          try { await outgoing.setVolume(master); } catch (_) {}\n"
        "          await ResonateDiagnostics.record('crossfade_cancelled', {\n"
        "            'stage': 'fade',"
    )
    if old_cancel in mt:
        mt = mt.replace(old_cancel,
            "          try { await incoming.stop(); } catch (_) {}\n"
            "          try { await outgoing.setVolume(master); } catch (_) {}\n"
            "          await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);\n"
            "          await ResonateDiagnostics.record('crossfade_cancelled', {\n"
            "            'stage': 'fade',", 1)
    old_abort = (
        "            try { await incoming.stop(); } catch (_) {}\n"
        "            try { await outgoing.setVolume(base); } catch (_) {}\n"
        "            return false;\n"
        "          }\n"
        "          remainingMs = (rem - 150).clamp(1200, plannedMs);"
    )
    if old_abort in mt:
        mt = mt.replace(old_abort,
            "            try { await incoming.stop(); } catch (_) {}\n"
            "            try { await outgoing.setVolume(base); } catch (_) {}\n"
            "            await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);\n"
            "            return false;\n"
            "          }\n"
            "          remainingMs = (rem - 150).clamp(1200, plannedMs);", 1)
    old_catch = "    } catch (e, stack) {\n      debugPrint('True crossfade failed: $e');"
    if old_catch in mt:
        mt = mt.replace(old_catch,
            "    } catch (e, stack) {\n"
            "      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);\n"
            "      debugPrint('True crossfade failed: $e');", 1)
    MP.write_text(mt)
    print("applied", MP.stat().st_size)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
