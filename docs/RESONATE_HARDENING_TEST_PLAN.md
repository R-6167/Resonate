# Resonate hardening and device validation

Target branch: `Resonate-True-Apk`

This is a release-readiness checklist, not a feature roadmap. Keep the current Resonate sound and controls intact. Prefer narrow fixes backed by a reproduced defect and regression test; do not retune DSP or rewrite playback ownership speculatively.

## Evidence boundaries

- **CI** validates the configured static analysis, automated tests, native DSP stress tests, Android unit tests, release APK build, and 100 MiB APK ceiling.
- **Automated tests** validate the individual contracts they exercise; they cannot prove audio output or OEM-specific audio-session behavior.
- **Device testing** must separately confirm playback continuity, audible DSP behavior, notification behavior, screen-off operation, and route changes.
- A successful fallback after a crossfade failure is recovery, not proof the transition itself succeeded.

## Current known edge to validate

The 2026-10-22 diagnostics captured one DJ crossfade where the incoming engine remained at 335 ms while the transition progressed. The monitor retried playback and then emitted `DJ incoming position stalled during transition`. The provider then entered its ordinary playback fallback and diagnostics showed the incoming track active and playing. This is a contained recovery in the captured session, but the stalled transition itself remains an unresolved reliability edge until it is reproduced or ruled out on device.

Two `audio_focus_pause` entries in that diagnostic session followed explicit player pause commands and were followed by explicit play commands. They are not, by themselves, evidence of an unsolicited focus interruption. Do not alter pause/focus policy based only on those entries.

## Device test matrix

Run these against the release APK built from a green merge commit. Record pass/fail and attach diagnostics for any failure.

### Playback and transport
- [ ] Play, pause, resume, seek, next, previous, and rapid repeated commands.
- [ ] Lock screen / screen off for at least 20 minutes; verify audio and notification controls.
- [ ] Force-stop and relaunch; verify queue/current track restore behavior.
- [ ] Switch Bluetooth/headphones/speaker routes during playback and near a transition.
- [ ] Receive notification/navigation ducking and restore; test call and another-player focus loss; confirm no unexpected resume.
- [ ] Pause/resume fade on and off; confirm no lingering duck or gain jump.

### Crossfade and queue
- [ ] Several consecutive crossfades in Normal mode.
- [ ] Several consecutive DJ transitions, including content-URI tracks.
- [ ] Press Next/Previous and seek during an active fade; latest user command must win.
- [ ] Repeat One loops the same track with matching title/audio; changing repeat policy during a fade takes effect once.
- [ ] Repeat All wraps once at queue end; Repeat Off stops at queue end.
- [ ] A missing/unreadable source is skipped without a stuck spinner or silent player.
- [ ] If an incoming DJ engine stalls, playback recovers to one audible track, UI/queue identity matches the audio, and pause intent is respected.

### DSP and sound identity
- [ ] Switch Resonate Signature, Warmth, and Clarity; restart and confirm the chosen profile persists.
- [ ] Adjust EQ bands and preamp; confirm audible changes and no clipping/gain jump.
- [ ] Change DVC while playing, then during an A/B transition; confirm both engines remain consistent.
- [ ] Compare leveling on quiet/loud tracks and on speaker/headphones/Bluetooth.
- [ ] Verify limiter behavior on peaks; treat crossover as protection processing, not tone shaping.
- [ ] Verify new engines inherit EQ, DVC, preamp, leveling, and limiter settings.

### UI, modes, and resources
- [ ] Switch all nine modes; verify controls, queue identity, and current track remain aligned.
- [ ] Inspect Now Playing artwork crops, text contrast, narrow screens, and large text.
- [ ] Scroll For You and Library; verify no noticeable stutter and current-row position remains stable.
- [ ] Test visualizer/orb on silence, pause, track change, and crossfade; motion should respond to real spectrum input and clear when capture stops.
- [ ] Check Settings, About, and media notification branding; verify the existing Resonate notification icon remains.
- [ ] Confirm release APK remains below 100 MiB in CI. Installed size is a separate measurement.

## Change policy

1. Keep each fix small and isolated.
2. Add a deterministic regression test for a reproducible state/logic bug before changing runtime behavior where practical.
3. Run the complete repository CI, including release-size gate.
4. Keep device/listening results separate from CI claims.
5. Avoid new features, generic preset cards, broad DSP retuning, or dependency additions during this pass.
