# Resonate — Modes Lab

This branch is intentionally **Modes-only**.

It contains the independent Modes Engine for Resonate:
- listening modes and mode policies
- media-type classification
- user media-type overrides
- playback/context integration contracts
- Modes UI
- focused unit tests
- a minimal Flutter package definition

It does **not** contain the main Resonate playback engine, DJ engine, DSP engine, library, intelligence engine, or unrelated screens/providers.

## Integration model

User intent → Modes policy → existing Resonate playback/intelligence engines

The main app will provide adapters for the integration contracts in `lib/modes/integration/`. Modes must never become a second playback engine.

## Current modes

Normal, Running, Driving, Work, Podcast, Motivation, Audiobook.

## Branch purpose

Bake and test Modes independently. When complete, merge the Modes module into a working Resonate branch and connect the adapters there.


## Running Mode

Running Mode is the first concrete interaction behavior in the Modes lab.

- Requires a **two-finger tap** for every actionable control.
- Rejects long presses as accidental/ambiguous input.
- Uses large controls and a reduced control set.
- Disables horizontal swipe navigation in the interaction contract.
- Keeps music-first playback behavior in the existing playback policy.
- The interaction guard only approves/blocks actions; it never performs playback itself.

The host Resonate UI will consume `InteractionPolicy` and `ModeInteractionGuard` when Modes is integrated.