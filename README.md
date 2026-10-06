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
## Running Mode — movement-aware behavior

Running Mode now has a pure movement decision layer. It is intentionally sensor-agnostic: the host Resonate app will supply coarse movement states through an adapter.

- Movement states: unknown, stationary, stopped, moving.
- A brief stop does **not** pause playback.
- Sustained stationary/stopped state (15 seconds by default) emits a pause suggestion.
- Movement must remain stable (5 seconds by default) before an automation resume suggestion.
- A cooldown prevents rapid pause/resume oscillation.
- An explicit user pause blocks automatic resume.
- Unknown movement never triggers automation.
- The decision engine emits intents only; it never calls the playback engine.

This keeps Running Mode safe and deterministic while leaving sensors and playback ownership to the main Resonate app.

### Running session lifecycle

Running Mode also defines a session boundary independent of playback:

- **Idle** — no active run session.
- **Active** — run session is in progress.
- **Paused** — session remains open but active running time is frozen.
- **Completed** — session is finished and cannot be resumed.
- Leaving Running Mode ends the current session without falsely marking it completed.
- Paused time is excluded from active running duration.
- The lifecycle controller is deterministic and does not access sensors or playback.
