#!/usr/bin/env python3
"""Oneshot duck under fade, MediaSession honesty, EQ re-apply on bind, live phrase snap."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def patch_sfx() -> None:
    path = ROOT / "lib/services/dj_sfx_rack.dart"
    t = path.read_text()
    if "_oneshotBaseVolume" in t and "Duck oneshot under" in t:
        print("sfx already patched")
        return

    if "double _oneshotBaseVolume" not in t:
        t = t.replace(
            "  int _oneshotGen = 0;\n",
            "  int _oneshotGen = 0;\n  double _oneshotBaseVolume = 0.0;\n",
            1,
        )

    # Lower any oneshot volume assignment pattern
    t2, n = re.subn(
        r"final volume = score >= 0\.85 \? 0\.\d+ : \(score >= 0\.7 \? 0\.\d+ : 0\.\d+\);\n(\s*)await player\.setVolume\(volume\.clamp\([^)]+\)\);",
        "final volume = score >= 0.85 ? 0.08 : (score >= 0.7 ? 0.10 : 0.12);\n"
        r"\1_oneshotBaseVolume = volume.clamp(0.05, 0.14);\n"
        r"\1await player.setVolume(_oneshotBaseVolume);",
        t,
        count=2,
    )
    t = t2
    print(f"oneshot volume patches: {n}")

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

    if "_oneshotBaseVolume = 0.0" not in t:
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
    if "Do not publish playing:true optimistically" in t:
        print("media session already honest")
        return
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
    if old in t:
        path.write_text(t.replace(old, new, 1))
        print("media session fixed")
    else:
        print("WARNING media session miss")


def patch_eq() -> None:
    path = ROOT / "lib/providers/equalizer_provider.dart"
    t = path.read_text()
    if "void _pushLiveDspCurve()" in t:
        print("eq already hardened")
        return

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

    t = t.replace(
        "      await _pushToHardware();\n      await _applyPreamp();\n",
        "      await _pushToHardware();\n"
        "      await _applyPreamp();\n"
        "      _pushLiveDspCurve();\n"
        "      debugPrint('EQ re-applied after hardware bind preset=$preset preamp=$preamp');\n",
        1,
    )

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
    anchor = "  Future<void> setStudioBandGain(int index, double gainDb) async {"
    if anchor in t:
        t = t.replace(anchor, helper + "\n" + anchor, 1)
        print("helper added")

    path.write_text(t)
    print("eq done")


def patch_music_live_snap() -> None:
    path = ROOT / "lib/providers/music_provider.dart"
    t = path.read_text()
    if "_snapSfxDelayToPhrase" in t:
        print("music snap already")
        return

    helper = (
        "  /// Snap planned SFX delay onto a nearby outgoing beat during the fade window.\n"
        "  Duration _snapSfxDelayToPhrase({\n"
        "    required Duration planned,\n"
        "    required int fadeMs,\n"
        "    DjTrackProfile? outgoingProfile,\n"
        "  }) {\n"
        "    final ideal = planned.inMilliseconds.clamp(0, fadeMs);\n"
        "    final beats = outgoingProfile?.beatGrid.beatMs ?? const <int>[];\n"
        "    if (beats.length < 4 || fadeMs < 400) {\n"
        "      return Duration(milliseconds: ideal);\n"
        "    }\n"
        "    int posMs = 0;\n"
        "    try {\n"
        "      posMs = audioPlayer.position.inMilliseconds;\n"
        "    } catch (_) {}\n"
        "    var best = ideal;\n"
        "    var bestDist = 1 << 30;\n"
        "    for (final b in beats) {\n"
        "      final rel = b - posMs;\n"
        "      if (rel < 120 || rel > fadeMs - 80) continue;\n"
        "      final d = (rel - ideal).abs();\n"
        "      if (d < bestDist) {\n"
        "        bestDist = d;\n"
        "        best = rel;\n"
        "      }\n"
        "    }\n"
        "    return Duration(milliseconds: best.clamp(100, fadeMs - 60));\n"
        "  }\n\n"
    )
    anchor = "  Future<void> _engageDjTransitionSfx({"
    if anchor not in t:
        print("WARNING engage anchor miss")
        return
    t = t.replace(anchor, helper + anchor, 1)

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
        "      DjTrackProfile? outProfile;\n"
        "      try {\n"
        "        final id = outgoingSong?.id;\n"
        "        if (id != null && _djAnalysis != null) {\n"
        "          outProfile = await _djAnalysis!.getProfile(id);\n"
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
