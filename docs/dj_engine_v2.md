# Resonate DJ Engine V2

This branch contains an isolated, player-agnostic DJ intelligence core.

## Why it exists

The existing `dj_Mode` implementation already provides useful cached analysis, BPM/key/energy extraction, beat alignment and transition memory. V2 does not delete or replace those systems yet. It creates a richer decision layer that can eventually consume their output.

## Architecture

Library analysis -> DJTrackProfile -> candidate generation -> scoring -> risk analysis -> execution timeline -> Resonate dual-engine adapter.

The engine never owns playback and never requires analysis to succeed. If confidence is low or risk is excessive, the adapter can use ordinary playback/crossfade.

## Current V2 foundation

- Rich track profile with beat grid, sections, energy curve, spectrum and transition markers.
- Multiple transition candidates rather than one fixed strategy.
- Weighted musical scoring: tempo, harmony, energy, spectrum, phrase and structure.
- Explicit risk detection for bass collision, energy shock, harmonic conflict and structural collision.
- Engine-neutral execution timeline suitable for two audio engines.
- Unit tests for musical selection and fallback behavior.

## Next implementation stages

1. Build real analyzers that populate the profile from decoded PCM/metadata without assuming WAV input.
2. Persist profiles and analysis versions in SQLite.
3. Add phrase/downbeat/structure detection.
4. Add beat-grid-aware tempo alignment and execution parameters.
5. Add runtime monitoring and adaptive transition correction.
6. Add richer transition telemetry and learning.
7. Add a thin Resonate two-engine adapter.
8. Benchmark on MP3 libraries and hard cases (long mixes, intros/outros, beatless tracks, variable tempo).

## Non-negotiable behavior

DJ intelligence is an enhancement, never a playback gate.
