#!/usr/bin/env python3
"""Wire EqualizerProvider route handler to richer speaker policy."""
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "lib/providers/equalizer_provider.dart"
t = path.read_text()

old = """  void _onOutputRouteChanged() {
    final route = AudioOutputRouteService.instance;
    syncSpeakerPolicy(
      needsSpeakerProtection: route.needsSpeakerProtection,
      virtualBassAmount: 0.55,
    );
  }
"""

new = """  void _onOutputRouteChanged() {
    final route = AudioOutputRouteService.instance;
    // Auto DSP posture: phone speaker → protection + virtual bass;
    // headphones / BT → full DSP, light bass; car → full DSP, no virtual bass.
    syncSpeakerPolicy(
      needsSpeakerProtection: route.needsSpeakerProtection,
      virtualBassAmount: route.suggestedVirtualBass,
      route: route.route,
    );
  }
"""

if old not in t:
    if "suggestedVirtualBass" in t:
        print("already wired")
    else:
        raise SystemExit("route handler miss")
else:
    t = t.replace(old, new, 1)
    print("route handler updated")

# Re-apply policy when native session attaches so engines get current route.
old_attach = None
if "attachNativeSession" in t and "refreshNow" not in t:
    # after successful attach, refresh route
    needle = "if (_nativeDspEnabled) unawaited(attachNativeSession(sessionId));"
    if needle in t:
        t = t.replace(
            needle,
            "if (_nativeDspEnabled) {\n"
            "        unawaited(attachNativeSession(sessionId));\n"
            "        unawaited(AudioOutputRouteService.instance.refreshNow());\n"
            "      }",
            1,
        )
        print("session attach refresh wired")

path.write_text(t)
print("eq wire done")
