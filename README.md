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

### Running Mode — integration intent stream

`RunningCoordinator` combines the session lifecycle and movement layers into one host-facing contract.

- Lifecycle methods emit: `sessionStarted`, `sessionPaused`, `sessionResumed`, `sessionCompleted`, and `sessionExited`.
- Sensor adapters feed coarse `MotionState` values into `ingestMotion()`.
- Every accepted motion sample produces a `motionChanged` intent.
- Sustained stationary/stopped movement can additionally produce `suggestPause`.
- Stable movement after an automation pause can additionally produce `suggestResume`.
- Suggestions do **not** change session state or call playback automatically; the host explicitly accepts them.
- Explicit user playback pause is tracked separately so movement automation cannot unexpectedly resume user-paused playback.
- Idle/completed sessions reject stale movement callbacks, preventing old sensor events from affecting playback.
- The coordinator is integration-neutral: sensors, playback, notifications, and UI remain owned by the main Resonate app.

Integration flow:

`sensor adapter → RunningCoordinator → RunningIntent stream → host playback/session decision`

This is the boundary that the eventual Resonate integration should consume.

## Driving Mode

Driving Mode is the second concrete safety-oriented behavior in the Modes lab.

- Uses a **minimal UI** with large controls and no horizontal swipe navigation.
- Hides advanced settings from the primary driving surface.
- Keeps music-first playback policy while allowing long listening sessions.
- Car context is supplied by the host through `ModeContextPort`; Modes does not access Bluetooth, location, or vehicle APIs directly.
- Car detection can produce a `suggestDriving` intent; the host decides whether to accept it.
- Entering/leaving Driving is a mode decision, not a second playback engine.
- Repeated identical context samples produce no duplicate intents.
- Losing car context while already in Driving emits a clean `drivingInactive` boundary.
- The Driving coordinator never controls playback or changes the active mode itself.

Integration flow:

`host context adapter → DrivingCoordinator → DrivingIntent → ModeProvider/UI/playback integration`

The eventual Resonate app remains responsible for the actual car-context adapter, mode switch, playback behavior, and platform-specific safety handling.
