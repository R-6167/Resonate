# Resonate UX Refinement Plan

Status: Phase 0 planning/baseline. This plan does not authorize feature implementation by itself; each implementation phase should be delivered in a small PR against `Resonate-True-Apk`, with CI and targeted validation before merge.

## Product direction

Resonate should feel like one intentional, local-first music product: its own sound identity, calm and clear controls, and automation that handles complexity without hiding meaningful manual control.

Principles:
- Prefer outcomes over technical parameters in common workflows.
- Keep continuous controls where fine adjustment is genuinely useful (EQ bands, preamp/headroom, seeking, and similar controls).
- Use named presets, compact chips, or buttons for a small set of understandable choices.
- Do not duplicate settings across multiple screens; establish a canonical home for each control.
- Treat audio correctness, state persistence, accessibility, responsiveness, and package size as release requirements.
- Do not add a feature merely to make a phase look larger. Refine existing behavior first.

## Phases

### Phase 0 — Baseline and inventory (current)
- [x] Confirm target branch and PR #122 merge; PR #122 CI passed. Post-merge run #39584802997 was still in progress at audit time, so its result must be checked separately. Existing open PRs were inventoried.
- [x] Inventory current screens, nine modes, EQ/DSP settings, custom preset storage/import/export, automation controls, and artwork/assets; see `docs/RESONATE_UX_PHASE_0_AUDIT.md`.
- [x] Record the release APK baseline: 76.2 MB from successful CI run #39579384222 using `flutter build apk --release --no-shrink`. The existing workflow prints the size; a hard 100 MB threshold is not yet enforced.
- [x] Identified 32 generic built-in EQ profiles, the 10-band mapping, canonical DSP settings schema, custom JSON v1 format, and legacy preference migration. Native headroom/listening validation remains Phase 1 work.
- [x] Separated source/build-confirmed findings from design ideas and documented Phase 1 acceptance criteria in the Phase 0 audit.
- [x] Kept Phase 0 changes documentation-only; no app code, DSP behavior, assets, or dependencies changed.

Exit criteria: a source-backed screen/control inventory, a size baseline, and a prioritized first implementation phase. No user-facing feature changes in this phase.

### Phase 1 — Resonate sound identity and EQ
- Define a small first-party profile set with clear intent and a reference profile (candidate directions: Signature, Warmth, Clarity, Afterhours, Pulse).
- Treat these names as design proposals, not approved final tuning or claims about sound quality.
- Inspect the current EQ model, band layout, native DSP mapping, preamp/headroom behavior, and custom preset schema before authoring curves.
- Author profiles as explicit, versioned curves with conservative gain/headroom behavior; avoid broad boosts that risk clipping.
- Listen-test across varied recordings and outputs before calling a profile complete; automated tests validate mappings and persistence, not subjective sound quality.
- Make preset selection visually clear, show modified/custom state, and offer an explicit "Save as custom" path without overwriting user presets.
- Keep band sliders in an advanced/fine-tune area; keep preamp accessible and distinguish it from loudness normalization.
- Preserve existing custom preset save/import/export compatibility unless migration is demonstrably needed.

Exit criteria: profiles map to real DSP settings, survive restart, preserve custom presets, pass tests, and have documented listening validation.

### Phase 2 — Mode identity and lightweight art
- Audit actual mode names and behaviors first; design art only for modes that exist and whose purpose can be communicated visually.
- Use one coherent Resonate art direction: high-contrast, restrained, recognizable at small sizes, with readable text and controls overlaid safely.
- Candidate visual language: Running (athlete in motion), Audiobook (book/listening atmosphere), Podcast (microphone/voice), DJ (mixing decks/waveform), Normal (abstract Resonate sound mark). Do not add unsupported modes to justify artwork.
- Prefer Flutter-drawn/vector-style illustrations or optimized local WebP/PNG where appropriate; reuse shared palettes/shapes and avoid video backgrounds, large animation packages, and duplicate near-identical assets.
- Artwork is decorative/contextual, never the only label or way to operate a mode. Support contrast, text scaling, reduced motion, and smaller screens.
- Lazy-load or only reference assets where useful; do not introduce network dependencies for core mode art.

Exit criteria: each chosen mode is instantly recognizable, mode switching and playback behavior remain unchanged unless separately specified, and asset/package-size budgets are met.

### Phase 3 — Automation and control simplification
- Audit Audio Automation, Audio Focus, DVC, volume normalization, limiter/crossover, crossfade, and DJ controls for duplicate or confusing paths.
- Use switches for binary choices; named chips/presets for mutually exclusive behavior; retain sliders for genuinely continuous controls.
- Explain outcomes in user language, show current status, and expose advanced controls only when needed.
- Keep limiter/crossover descriptions honest: protection behavior is not tone shaping, and any claimed effect must match the implementation.
- Keep DVC, EQ preamp, and target-loudness/volume normalization conceptually and technically separate.
- Preserve explicit consent boundaries for automatic playback/Autopilot.

Exit criteria: every control has one canonical home, persistence and native wiring are tested, and the UI labels accurately describe behavior.

### Phase 4 — Visual/navigation consistency and performance
- Review Home, For You, Library, Now Playing, Settings, About, Visualization & Orb, and mode entry points as one design system.
- Reduce expensive blur/glass where it affects scrolling; retain visual character rather than flattening the UI.
- Ensure navigation preserves context and does not cause full-screen refreshes, duplicate player layouts, or lost library position.
- Keep spectrum capture optional, audio-driven animation honest, and reduce-motion behavior respected.
- Avoid adding new dependencies for visual polish without demonstrating a clear value.

Exit criteria: targeted navigation, scrolling, accessibility, and playback regression checks pass on representative devices.

### Phase 5 — Release validation and size guard
- Run Flutter analysis/tests, native DSP tests, Android build/package checks, and targeted device smoke tests.
- Verify mode artwork and sound profiles on low-end devices as well as the primary test device.
- Track both distributable package size and installed size where practical; use the same build variant and measurement method when comparing.
- Investigate unexpected growth rather than silently raising the budget.

Exit criteria: all required checks are green, manual sound/device checks are recorded, and the release artifact remains under the size ceiling.

## Size and asset budget

Hard ceiling for now: **100 MB total app size**. Treat this as a release gate, not a target to consume.

- Establish the current release APK/AAB and installed-size baseline in Phase 0 before claiming current compliance.
- Aim for new mode artwork to add no more than 2 MB compressed in aggregate; treat this as an initial planning budget to revisit only with measured evidence.
- Prefer vector/drawn art for simple shapes; use optimized WebP for rich illustrations, and avoid shipping both full-size originals and optimized copies.
- Keep individual raster illustrations small (initial target: roughly 100–200 KB each where quality permits); measure actual assets rather than enforcing a quality-damaging limit.
- Do not bundle large music samples, video loops, fonts, or image packs for decoration.
- Keep dependencies unchanged unless needed; quantify APK/AAB growth for any new dependency.
- If the build exceeds the budget, identify the largest contributors and reduce or remove nonessential assets before release.

## Interaction rules

| User intent | Preferred control | Keep manual precision? |
|---|---|---|
| Enable/disable behavior | Switch or toggle | Usually no slider |
| Pick one of a few behaviors | Named chip, segmented control, or preset card | No numeric slider |
| Choose EQ sound identity | Profile cards/chips | Fine-tune remains available |
| Adjust EQ band or preamp | Slider with visible value | Yes |
| Seek through a track | Seek bar | Yes |
| Choose visualization/mode | Compact illustrated card or chip | No slider |
| Change advanced technical behavior | Collapsed advanced section with clear explanation | Where technically useful |

## Validation and change discipline

- Work in small branches and PRs; never merge without explicit user approval.
- Do not combine subjective sound tuning, major navigation redesign, and DSP engine changes in one PR.
- Each phase must name tests, manual checks, expected asset-size delta, and rollback risk before implementation.
- CI success does not prove audio quality or audible DSP behavior; record listening/device checks separately.
- No new features during the refinement plan unless they are required to fix an existing broken or misleading behavior.
