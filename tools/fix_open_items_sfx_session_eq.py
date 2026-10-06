#!/usr/bin/env python3
"""Oneshot duck under fade, MediaSession honesty, EQ re-apply on bind."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def patch_sfx() -> None:
    path = ROOT / "lib/services/dj_sfx_rack.dart"
    t = path.read_text()
    if "_oneshotBaseVolume" in t and "duck oneshot" in t:
        print("sfx already patched")
        return

    # Field for base oneshot volume
    if "double _oneshotBaseVolume" not in t:
        t = t.replace(
            "  int _oneshotGen = 0;\n",
            "  int _oneshotGen = 0;\n  double _oneshotBaseVolume = 0.0;\n",
            1,
        )

    # Lower oneshot volumes + store base
    old_vol = (
        "      final volume = score >= 0.85 ? 0.14 : (score >= 0.7 ? 0.17 : 0.20);\n"
        "      await player.setVolume(volume.clamp(0.10, 0.24));\n"
    )
    new_vol = (
        "      // Keep samples under the music so they colour the fade, not dominate it.\n"
        "      final volume = score >= 0.85 ? 0.08 : (score >= 0.7 ? 0.10 : 0.12);\n"
        "      _oneshotBaseVolume = volume.clamp(0.05, 0.14);\n"
        "      await player.setVolume(_oneshotBaseVolume);\n"
    )
    if old_vol in t:
        t = t.replace(old_vol, new_vol, 1)
        print("oneshot volume lowered")
    else:
        # alternate path in _playOneshot
        old2 = re.search(
            r"final volume = score >= 0\.85 \? 0\.\d+ : \(score >= 0\.7 \? 0\.\d+ : 0\.\d+\);\n\s*await player\.setVolume\(volume\.clamp\([^)]+\)\);",
            t,
        )
        if old2:
            t = t[: old2.start()] + (
                "final volume = score >= 0.85 ? 0.08 : (score >= 0.7 ? 0.10 : 0.12);\n"
                "      _oneshotBaseVolume = volume.clamp(0.05, 0.14);\n"
                "      await player.setVolume(_oneshotBaseVolume);"
            ) + t[old2.end() :]
            print("oneshot volume lowered via regex")
        else:
            print("WARNING oneshot volume miss")

    # Duck in tick
    old_tick = (
        "    try {\n"
        "      await _applyFxAt(t, score);\n"
        "      if (_usesEq(activePreset!)) {\n"
        "        await _applyEqAt(equalizerA, t);\n"
        "        await _applyEqAt(equalizerB, t);\n"
        "        _eqTouched = true;\n"
        "      }\n"
        "    } catch (_) {}\n"
    )
    new_tick = (
        "    try {\n"
        "      await _applyFxAt(t, score);\n"
        "      if (_usesEq(activePreset!)) {\n"
        "        await _applyEqAt(equalizerA, t);\n"
        "        await _applyEqAt(equalizerB, t);\n"
        "        _eqTouched = true;\n"
        "      }\n"
        "      // Duck oneshot under the incoming rise so samples fade with the blend.\n"
        "      final shot = _oneshot;\n"
        "      if (shot != null && _oneshotBaseVolume > 0) {\n"
        "        final progress = t.clamp(0.0, 1.6);\n"
        "        final duck = progress <= 1.0\n"
        "            ? (1.0 - progress * 0.85)\n"
        "            : (0.15 * (1.6 - progress) / 0.6).clamp(0.0, 0.15);\n"
        "        try {\n"
        "          await shot.setVolume((_oneshotBaseVolume * duck).clamp(0.0, 0.14));\n"
        "        } catch (_) {}\n"
        "      }\n"
        "    } catch (_) {}\n"
    )
    if old_tick in t:
        t = t.replace(old_tick, new_tick, 1)
        print("tick duck added")
    else:
        print("WARNING tick duck miss")

    # Clear base on restore
    if "_oneshotBaseVolume = 0.0" not in t.split("Future<void> restore")[1][:800] if "Future<void> restore" in t else "":
        t = t.replace(
            "    ++_oneshotGen;\n",
            "    ++_oneshotGen;\n    _oneshotBaseVolume = 0.0;\n",
            1,
        )

    path.write_text(t)
    print("sfx done")


def patch_media_session() -> None:
    path = ROOT / "lib/services/audio_service_handler.dart"
    t = path.read_text()
    old = (
        "  Future<void> play() async {\n"
        "    final callback = _onPlay;\n"
        "    if (callback == null) return;\n"
        "    PlaybackAuthority.instance.markExternalUserCommand('audio_service', 'play');\n"
        "    publishPositionTick(playing: true, position: playbackState.value.position, force: true);\n"
        "    await callback();\n"
        "  }\n"
    )
    new = (
        "  Future<void> play() async {\n"
        "    final callback = _onPlay;\n"
        "    if (callback == null) return;\n"
        "    PlaybackAuthority.instance.markExternalUserCommand('audio_service', 'play');\n"
        "    // Do not publish playing:true optimistically — MusicProvider publishes\n"
        "    // after native play succeeds so pause/focus state stays honest.\n"
        "    await callback();\n"
        "  }\n"
    )
    if "Do not publish playing:true optimistically" in t:
        print("media session already honest")
    elif old in t:
        path.write_text(t.replace(old, new, 1))
        print("media session fixed")
    else:
        # try without PlaybackAuthority line variance
        m = re.search(
            r"Future<void> play\(\) async \{[\s\S]*?await callback\(\);\n  \}",
            t,
        )
        if m and "optimistically" not in m.group(0):
            path.write_text(t[: m.start()] + new.strip() + "\n" + t[m.end() :])
            print("media session fixed via regex")
        else:
            print("WARNING media session miss")


def patch_eq() -> None:
    path = ROOT / "lib/providers/equalizer_provider.dart"
    t = path.read_text()
    if "syncStudioBandsToNativeEq" in t and "eq_reapply_after_bind" in t:
        print("eq already hardened")
        return

    # After digital preamp at init, also push live DSP so process-death restore sticks
    old_init = (
        "      // Digital preamp only at startup (player volume scale). Hardware EQ\n"
        "      // bind waits until playback has been running for a moment.\n"
        "      await _applyPreamp();\n"
        "      notifyListeners();\n"
    )
    new_init = (
        "      // Digital preamp + live DSP curve so settings survive process death\n"
        "      // even before hardware EQ binds on first play.\n"
        "      await _applyPreamp();\n"
        "      _pushLiveDspCurve();\n"
        "      notifyListeners();\n"
    )
    if old_init in t:
        t = t.replace(old_init, new_init, 1)
        print("eq init live push")

    # After hardware bind, push live DSP again
    if "_pushLiveDspCurve();" not in t[t.find("_bindHardwareAfterPlayback"):t.find("_bindHardwareAfterPlayback")+900]:
        t = t.replace(
            "      await _pushToHardware();\n      await _applyPreamp();\n",
            "      await _pushToHardware();\n"
            "      await _applyPreamp();\n"
            "      _pushLiveDspCurve();\n"
            "      // ignore: discarded_futures\n"
            "      unawaited(ResonateDiagnostics.record('eq_reapply_after_bind', {\n"
            "        'preset': preset,\n"
            "        'preamp': preamp,\n"
            "        'enabled': isEnabled,\n"
            "      }).catchError((_) => null));\n",
            1,
        )
        print("eq bind live push")

    # Helper method if missing
    if "void _pushLiveDspCurve()" not in t:
        helper = (
            "\n  void _pushLiveDspCurve() {\n"
            "    try {\n"
            "      final centers = studioBands.map((b) => b.frequencyHz).toList();\n"
            "      final gains = studioBands.map((b) => b.gainDb).toList();\n"
            "      syncStudioBandsToNativeEq(\n"
            "        centersHz: centers,\n"
            "        gainsDb: gains,\n"
            "        enabled: isEnabled,\n"
            "      );\n"
            "      syncPreampToDvc(preamp, enabled: isEnabled);\n"
            "      final route = AudioOutputRouteService.instance;\n"
            "      syncSpeakerPolicy(\n"
            "        needsSpeakerProtection: route.needsSpeakerProtection,\n"
            "        virtualBassAmount: route.suggestedVirtualBass,\n"
            "        route: route.route,\n"
            "      );\n"
            "    } catch (e) {\n"
            "      debugPrint('pushLiveDspCurve failed: $e');\n"
            "    }\n"
            "  }\n"
        )
        # insert before setStudioBandGain
        anchor = "  Future<void> setStudioBandGain(int index, double gainDb) async {"
        if anchor in t:
            t = t.replace(anchor, helper + "\n" + anchor, 1)
            print("helper added")

    # Import diagnostics if needed for record - use soft fail without import
    if "eq_reapply_after_bind" in t and "resonate_diagnostics" not in t:
        # remove diagnostics call to avoid missing import - simpler
        t = t.replace(
            "      // ignore: discarded_futures\n"
            "      unawaited(ResonateDiagnostics.record('eq_reapply_after_bind', {\n"
            "        'preset': preset,\n"
            "        'preamp': preamp,\n"
            "        'enabled': isEnabled,\n"
            "      }).catchError((_) => null));\n",
            "      debugPrint('EQ re-applied after hardware bind preset=$preset preamp=$preamp');\n",
            1,
        )

    path.write_text(t)
    print("eq done")


def patch_music_live_snap() -> None:
    """When engaging SFX, snap delay to live outgoing beats if grid is richer."""
    path = ROOT / "lib/providers/music_provider.dart"
    t = path.read_text()
    if "_snapSfxDelayToPhrase" in t:
        print("music snap already")
        return

    # Add helper before _engageDjTransitionSfx
    helper = r'''  /// Snap planned SFX delay onto a nearby outgoing beat during the fade window.
  Duration _snapSfxDelayToPhrase({
    required Duration planned,
    required int fadeMs,
    DjTrackProfile? outgoingProfile,
  }) {
    final ideal = planned.inMilliseconds.clamp(0, fadeMs);
    final beats = outgoingProfile?.beatGrid.beatMs ?? const <int>[];
    if (beats.length < 4 || fadeMs < 400) {
      return Duration(milliseconds: ideal);
    }
    int posMs = 0;
    try {
      posMs = audioPlayer.position.inMilliseconds;
    } catch (_) {}
    var best = ideal;
    var bestDist = 1 << 30;
    for (final b in beats) {
      final rel = b - posMs;
      if (rel < 120 || rel > fadeMs - 80) continue;
      final d = (rel - ideal).abs();
      if (d < bestDist) {
        bestDist = d;
        best = rel;
      }
    }
    return Duration(milliseconds: best.clamp(100, fadeMs - 60));
  }

'''
    anchor = "  Future<void> _engageDjTransitionSfx({"
    if anchor not in t:
        print("WARNING engage anchor miss")
        return
    t = t.replace(anchor, helper + anchor, 1)

    # Wrap delay at call site
    old_call = (
        "      await _engageDjTransitionSfx(\n"
        "        energyScore: _lastDjEnergyScore,\n"
        "        transitionKind: _djTransitionKindFromName(_lastDjStrategy),\n"
        "        delay: Duration(milliseconds: sfxStep?.atMs ?? 0),\n"
        "      );\n"
    )
    new_call = (
        "      final plannedSfxMs = sfxStep?.atMs ?? 0;\n"
        "      final fadeWindowMs = milliseconds.clamp(500, 12000);\n"
        "      await _engageDjTransitionSfx(\n"
        "        energyScore: _lastDjEnergyScore,\n"
        "        transitionKind: _djTransitionKindFromName(_lastDjStrategy),\n"
        "        delay: _snapSfxDelayToPhrase(\n"
        "          planned: Duration(milliseconds: plannedSfxMs),\n"
        "          fadeMs: fadeWindowMs,\n"
        "          outgoingProfile: null, // beat grid passed inside engage via profile arg\n"
        "        ),\n"
        "        outgoingProfile: null,\n"
        "      );\n"
    )
    # Better: pass profile from handoff - look for outgoing song analysis
    # Keep simple live snap using audioPlayer position + profile from _djAnalysis
    new_call = (
        "      final plannedSfxMs = sfxStep?.atMs ?? 0;\n"
        "      final fadeWindowMs = milliseconds.clamp(500, 12000);\n"
        "      DjTrackProfile? outProfile;\n"
        "      try {\n"
        "        final path = outgoingSong?.filePath;\n"
        "        if (path != null && _djAnalysis != null) {\n"
        "          outProfile = await _djAnalysis!.profileFor(path);\n"
        "        }\n"
        "      } catch (_) {}\n"
        "      await _engageDjTransitionSfx(\n"
        "        energyScore: _lastDjEnergyScore,\n"
        "        transitionKind: _djTransitionKindFromName(_lastDjStrategy),\n"
        "        delay: _snapSfxDelayToPhrase(\n"
        "          planned: Duration(milliseconds: plannedSfxMs),\n"
        "          fadeMs: fadeWindowMs,\n"
        "          outgoingProfile: outProfile,\n"
        "        ),\n"
        "        outgoingProfile: outProfile,\n"
        "      );\n"
    )
    if old_call in t:
        t = t.replace(old_call, new_call, 1)
        print("music call site snapped")
    else:
        print("WARNING music call miss")

    path.write_text(t)
    print("music done")


def main() -> None:
    patch_sfx()
    patch_media_session()
    patch_eq()
    patch_music_live_snap()
    print("open items complete")


if __name__ == "__main__":
    main()
