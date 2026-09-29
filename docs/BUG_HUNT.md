# Bug hunting — Wire_dsp_engine DSP path

## Smoke checklist (install release APK from CI)

1. **Cold start play** — library song, EQ off → audio continuous, no force-close.
2. **EQ on Flat** — no change vs off (or minimal).
3. **Bass Extreme + headphones** — strong bass, Auto shows full DSP.
4. **Bass Extreme + phone speaker + Auto** — protection + virtual bass; less crackle than Full.
5. **Bass Extreme + phone speaker + Full** — maximum; may still distort (expected).
6. **Effects section** — bass boost / virtualizer / reverb move without Loudness.
7. **Route flip** — plug/unplug headphones mid-song; route label + speaker mode switch.
8. **Crossfade A/B** — both engines get sticky EQ/volume/speaker.
9. **Advanced → Test DSP process()** — offline path reports OK.
10. **Logcat** — `DspEngineJni` create ok linked; `DspEngineRegistry` register; no SIGSEGV.

## Known residual

- Extreme gains on tiny speakers can still distort (physics).
- Android BassBoost/Virtualizer OEM quirks when Effects enabled.
- Gradle/AGP version warnings (non-blocking).

## Vendor libs in APK

Unpack APK: `lib/arm64-v8a/libdsp_engine.so` and `libdsp_jni.so` must exist.

## Speaker mode wiring

- Native: `dsp_set_speaker_mode` / `dsp_set_virtual_bass`
- Kotlin: `DspEngineRegistry.applySpeakerModeAll`
- Channel: `setLiveDspSpeakerMode` / `setLiveDspVirtualBass`
- Dart: `AudioEffectsBridge` + Equalizer route listener
