# Resonate UX Refinement — Phase 0 Audit

Audit date: 2026-10-21  
Repository: `R-6167/Resonate`  
Target branch: `Resonate-True-Apk`  
Audit branch: `docs/phase-0-ux-inventory`  
Scope: documentation and measurement only; no app behavior changed.

## 1. Repository and CI baseline

- PR #122 merged at commit `307edd6fc08bdd23c9338ad264acdb965b93a2ee`.
- PR #122's pull-request workflow run #39583792366 completed successfully.
- Post-merge run #39584802997 was still in progress when this audit was written; do not call the post-merge run green until it completes.
- Current CI builds a release APK with `flutter build apk --release --no-shrink`, checks the artifact exists, prints its size, and uploads it as `resonate-release-apk`.
- Successful release build from run #39579384222 (same app source as the merged PR #121; PR #122 changes documentation only) reported `app-release.apk (76.2MB)`; `ls -lh` reported `73M`. The uploaded ZIP artifact was 39,060,356 bytes, which is compressed transport size and must not be confused with the APK size.
- Use **76.2 MB reported by Flutter** as the initial comparable APK baseline for this exact workflow/build variant. The workflow is currently `--no-shrink`; don't compare this number to a Play-delivered split APK or installed size as though they were the same measurement.
- Against the current 100 MB ceiling, this leaves about 23.8 MB of nominal APK headroom. Treat that as a planning calculation, not an installed-size measurement. Rebuild and record a fresh size on the current base branch before introducing assets, then compare like-for-like.
- The current workflow reports the size but does not yet fail when a release APK crosses the 100 MB ceiling. Add a hard size gate only after confirming the measurement and desired MB/byte convention on a fresh build.

## 2. Current modes and visible identity

### Source-of-truth enum

`lib/modes/models/resonate_mode.dart` defines nine listening modes:

| Mode | Current short description / intent | Current identity |
|---|---|---|
| Normal | Full Resonate experience | 🎵 |
| Running | Large controls, music-first, fewer accidents | 🏃 |
| Workout | Music-first; 120–160 BPM target guidance from available DJ analysis | 💪 |
| Driving | Minimal UI, Resonate supervises playback | 🚗 |
| Work | Long, calm background listening | 💼 |
| Podcast | Speech-first, precise resume, no music crossfade | 🎙️ |
| Motivation | Speech-aware transitions and queues | 🔥 |
| Audiobook | Chapters, precise position, sleep timer friendly | 📚 |
| Sleep | Gentle queue, no shuffle or crossfade, sleep timer suggested | 🌙 |

The mode selector iterates `ResonateMode.values` and currently displays emoji, label, and short description. It does not use mode-specific illustrations.

### Documentation mismatch

`docs/MODES.md` documents seven modes (Normal, Running, Driving, Work, Podcast, Motivation, Audiobook) and omits Workout and Sleep even though both exist in the enum and are exposed by the selector. This is a confirmed documentation mismatch, not evidence that either mode is broken.

DJ Mode is a separate feature/provider and DJ settings screen, not a member of the nine-value `ResonateMode` enum. Future art should avoid conflating DJ Mode with the listening-mode enum.

### Mode implementation surfaces

- Mode selector and folder options: `lib/modes/screens/modes_screen.dart`.
- Active mode/policy persistence: `lib/modes/providers/mode_provider.dart`; active mode preference key is `resonate_modes_active_mode_v1`.
- Mode content shelf: `lib/screens/mode_shelf_screen.dart` and `lib/widgets/mode_shelf_card.dart`.
- Mode policies and coordinators live under `lib/modes/models/`, `lib/modes/services/`, and `lib/modes/providers/`.
- Existing mode behavior has dedicated tests under `test/modes/`, plus playback-policy and Autopilot policy tests. Preserve these policy boundaries when changing visuals.

### Artwork and assets

The current `pubspec.yaml` explicitly bundles:
- `assets/branding/resonate_app_icon.png` — 1,174,804 bytes.
- `assets/branding/resonate_in_app_logo.png` — 1,552,360 bytes.
- Six short SFX files under `assets/sfx/` — 208,416 bytes combined.

Tracked files under `assets/` total approximately 2,935,580 bytes (about 2.80 MiB). There are **no dedicated mode-artwork assets** in the current asset tree. Current mode identity is text + emoji/Material icons. The two large branding PNGs are worth optimizing independently if a later measured size investigation justifies it; don't alter branding in this audit.

Artwork decision for Phase 2: choose art only after the real mode list and semantics are settled. Running/Workout are good candidates for an athlete illustration, but should remain visually distinguishable. Prefer simple Flutter/vector-drawn art where it can achieve the desired style; use optimized local WebP for richer illustrations. No network art, video backgrounds, or new image/animation dependency is needed for the first pass.

## 3. EQ and DSP inventory

### Current preset catalogue

`lib/providers/equalizer_provider.dart` defines **32 built-in presets** in six categories:

- Utility: Flat, Soft, Warm, Bright, Balanced.
- Bass: Bass Boost, Deep Bass, Sub Focus, Bass Extreme, Hip-Hop Bass.
- Treble: Treble Boost, Air.
- Voice: Vocal, Vocal Focus, Podcast, Spoken Word.
- Genre: Rock, Pop, Jazz, Classical, Electronic, Acoustic, Hip-Hop, R&B, Metal, Dance, Latin, Reggae.
- Space: Live, Club, Headphones, Car.

These are currently broad utility/genre/space profiles, not a cohesive first-party Resonate sound signature. Several curves include large boosts (up to +11 dB in a band), so Phase 1 must evaluate headroom and clipping behavior before adopting or renaming any curve. No profile should be described as listen-tested until it has been auditioned on varied recordings and output devices.

### Band and persistence contracts

- EQ preset model: `EqualizerPreset` with name, category, 10 gain values in dB, and `isCustom`.
- Current software curve: fixed 10-band studio EQ; `EqualizerProvider` is the source of truth for that curve.
- Canonical DSP settings: `lib/models/dsp_settings.dart`, schema version 2, preference key `resonate_dsp_settings_v1`; it stores preset name, EQ enabled state, band gains, preamp, automatic headroom, DVC, limiter/crossover and other DSP fields independently.
- Custom preset preference key: `equalizer_custom_presets_v1`.
- JSON backup format: `resonate-eq-presets`, version 1, containing user presets; import validates all ten bands and gain bounds before saving.
- Legacy EQ migration reads old `eq_studio_band_0..30` keys and other legacy preference keys. Preserve compatibility or explicitly test migration before changing storage.
- EQ screen already has custom preset save/delete, JSON import/export using the file picker, categories, and advanced DSP status/control surfaces. Prefer improving the existing path over adding another preset manager.
- EQ preamp, DVC, and volume normalization/target-loudness are separate concepts and should remain separate. Current canonical DSP defaults set `autoEqHeadroom` to false; inspect the actual initialization and native DSP application path before changing any defaults.

### Phase 1 implications

1. Decide the sound philosophy and reference profile before authoring curves.
2. Introduce a small set of Resonate-owned profiles alongside existing generic presets initially; do not silently delete or rename saved user-facing presets.
3. Make profile definitions explicit and tested, with safe headroom handling and stable identifiers separate from display names.
4. Preserve 10-band mapping, custom preset JSON v1 compatibility, custom preset storage, and legacy migration.
5. Add tests for exact curve values, applying a profile to the software/native DSP path, persistence/restart, and saving a modified built-in as a new custom profile.
6. Listening tests remain a separate acceptance gate; unit tests cannot certify subjective sound quality.

## 4. Screen/control inventory and interaction rules

| Area | Current source(s) | Phase 0 observation / later focus |
|---|---|---|
| Modes | `modes_screen.dart`, `mode_shelf_screen.dart`, `mode_shelf_card.dart` | Nine enum values; emoji-led list; artwork absent; docs omit Workout and Sleep. |
| EQ | `equalizer_screen.dart`, `equalizer_provider.dart` | 32 built-ins plus custom presets; sliders are appropriate for 10 EQ bands and preamp; preset selection should become clearer rather than removing fine control. |
| DSP/Audio Lab | `audio_effects_screen.dart`, `audio_effects_bridge.dart`, native DSP registry | Effects screen is a compatibility redirect to EQ; the bridge exposes live DSP controls. Audit labels against actual native capability before redesign. |
| Audio automation | `audio_automation_settings_screen.dart`, `DspSettings`, `MusicProvider` | Contains audio-focus automation, DVC and peak-protection profile controls, plus pause/resume fade. Common outcomes should be easier to choose; don't imply limiter/crossover is tone shaping. |
| Visualization & Orb | `audio_visualization_settings_screen.dart`, `AudioVisualizationProvider`, `AskResonateController` | Already has shape chips and switches; sensitivity, smoothing and frame-rate sliders remain meaningful advanced controls. Both visualizers should continue using the shared optional spectrum source. |
| Crossfade/DJ | `crossfade_screen.dart`, `dj_mode_settings_screen.dart`, providers and policy tests | Keep DJ distinct from listening modes; preserve user intent, mode policy and consent boundaries. |
| Home/For You/Library/Now Playing | `home_screen.dart`, `home_dashboard.dart`, `library_screen.dart`, `player_screen.dart` | Existing navigation and playback behavior must be regression-tested; visual polish must not introduce expensive blur or screen rebuilds. |
| Settings/About | `settings_screen.dart`, `about_screen.dart` | Use a consistent visual system and one canonical home for each setting. |

Control selection rule:
- Switch/toggle for true binary behavior.
- Named chips, compact segmented choices, or preset cards for a few mutually exclusive outcomes.
- Sliders for continuous controls where precision matters (EQ bands, preamp, seek, and optional visualization tuning).
- Keep technical controls available in advanced sections rather than removing them.
- Use artwork for recognition/context, never as the sole label or control.

## 5. Size policy

- User ceiling: **100 MB total app size**.
- Current comparable release APK baseline: **76.2 MB** from CI run #39579384222, built with `flutter build apk --release --no-shrink`.
- New mode-art planning budget: at most **2 MB compressed in aggregate**, as a planning cap rather than a requirement to use all of it.
- Keep new artwork local and optimized. Prefer vector/drawn art when appropriate and WebP for rich art; avoid shipping both source and optimized copies.
- Report release APK size in CI on every build and later add a threshold failure once the current base build has been remeasured and the MB convention is explicit.
- Track APK size separately from installed size and Play-delivered splits. This audit has not measured installed size.
- No new dependencies are justified for artwork at this stage.

## 6. Confirmed findings vs ideas

### Confirmed from source/build evidence
- Nine listening modes are in the enum; the mode selector exposes them.
- `docs/MODES.md` lists only seven and omits Workout and Sleep.
- No dedicated mode-art assets currently exist.
- The 32 built-in EQ presets are generic category-based profiles; custom save/delete and JSON import/export already exist.
- The release CI build reports 76.2 MB with `--no-shrink`; the uploaded ZIP size is not the APK size.
- EQ curves can contain high positive band gains; headroom/clipping should be evaluated during Phase 1.

### Ideas that still need validation
- Which modes benefit most from illustration; likely first candidates are Running/Workout and Audiobook, followed by Driving/Podcast/Sleep if the visual hierarchy benefits.
- Whether existing generic presets should be retained under a collapsed “Classic” category, and how many first-party profiles are useful.
- Whether the current default headroom behavior is appropriate for the new curves.
- Whether logo assets can be compressed substantially without visible quality loss.
- Whether the 100 MB ceiling refers only to the release APK or also requires a separate installed-size measurement on target devices.

## 7. Recommended next phase

**Phase 1 — Resonate sound identity and EQ**, but begin with a small implementation design review: define the reference sound and profile intent, inspect actual native EQ/headroom behavior, and write curve/migration tests before changing UI. In parallel, fix the confirmed documentation mismatch (Workout and Sleep) as a tiny documentation-only change if desired; don't bundle it with EQ/DSP changes.
