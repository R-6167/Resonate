# Resonate — Modes Lab

This branch is intentionally **Modes-only**.

It contains the independent Modes Engine for Resonate:
- listening modes and mode policies
- media-type classification
- optional user-selected content folders
- user media-type overrides
- playback/context/folder-picker integration contracts
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

## Content folders — optional user routing

Podcast, Motivation, and Audiobook can each have **zero or more user-selected folders**.

This is deliberately **not enabled by default**. If the user never selects a folder, the normal MediaClassifier continues to work exactly as before.

When a user selects a folder:
- files inside that folder are classified as the selected content type
- the folder assignment is persisted locally
- multiple folders can be assigned to the same type
- folders can be removed independently
- nested folders are included
- the most specific matching selected folder wins if assignments overlap
- a selected folder is a strong user signal, but an individual file override remains stronger

Classification precedence is:

`individual user override → selected content folder → automatic classifier → conservative fallback`

Only Podcast, Motivation, and Audiobook are exposed as content-folder categories. Music remains automatic/general-purpose rather than requiring folder configuration.

### Folder picker integration

Modes does not depend on Android/iOS file-picker APIs. The host Resonate app supplies a `ModeFolderPickerPort` implementation:

`host platform folder picker → selected path → ModeProvider.addMediaFolder() → persisted folder routing`

The reference `ModesScreen` accepts an optional `ModeFolderPickerPort`. When supplied, the user gets an **Add folder** control for Podcast, Motivation, and Audiobook. When no picker is supplied, the Modes module remains platform-agnostic.

The actual host application will decide which native/system folder-picker implementation to use.

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

## Work Mode

Work Mode is the third concrete Modes behavior. It is intentionally lighter than Running and Driving: it coordinates a work-session boundary without taking control of playback.

- Keeps a reduced UI while preserving normal listening controls.
- Allows long listening sessions and auto-next.
- Allows shuffle, but does not prefer crossfade; the host playback engine decides transitions.
- Prefers music while leaving other media types playable when explicitly selected.
- Does not use movement, Bluetooth, location, or other sensors.
- A work session can be started, paused, resumed, completed, or exited.
- Pausing a work session does not imply pausing playback; the host decides whether playback should also pause.
- Exiting Work Mode produces an explicit boundary rather than falsely reporting completion.
- Repeated invalid lifecycle operations are ignored, keeping the contract deterministic.

Integration flow:

`host UI/session action → WorkCoordinator → WorkIntent → host playback/session integration`

The coordinator owns only the Work Mode session contract. It never starts playback, changes queues, controls timers, or accesses platform services.

## Podcast Mode

Podcast Mode is the fourth concrete Modes behavior and is speech-first rather than duration-first.

- Disables crossfade and shuffle so spoken episodes keep natural boundaries.
- Enables precise resume and emphasizes playback-speed controls.
- Suggests a sleep timer through the playback policy.
- A podcast session has explicit start, pause, resume, complete, and exit boundaries.
- The coordinator can carry a known resume position into a new session.
- Pause/resume/complete/exit can carry the latest known position back to the host.
- Position updates are state-only; the coordinator never writes to storage or seeks the playback engine.
- Invalid or stale lifecycle operations are ignored.
- Podcast Mode does not classify media itself. The existing MediaClassifier, selected content folders, and individual user overrides decide whether an item is a podcast.
- A selected Podcast folder is optional; without one, automatic classification remains active.
- The coordinator does not assume that a long audio file is a podcast; duration is not used as the classification signal.

Integration flow:

`folder/user classification + host resume store → PodcastCoordinator → PodcastIntent → host playback/resume integration`

The host Resonate app remains responsible for actual seeking, position persistence, speed changes, sleep-timer execution, episode metadata, and playback.

## Motivation Mode

Motivation Mode is the fifth concrete Modes behavior. It is designed for **speech-aware motivation followed by music**, without creating a separate playback engine.

- Keeps auto-next and shuffle available.
- Allows crossfade, but does not require it; the host playback engine owns transition execution.
- Emphasizes speed controls and precise resume.
- Prefers both classified motivation/speech content and music.
- Does not use sensors or automatic movement/car behavior.
- A motivation session has explicit start, pause, resume, complete, and exit boundaries.
- Starting classified motivation content emits a `speechStarted` intent.
- Completing motivation content emits `speechCompleted` followed by `musicFollowupSuggested`.
- Music itself does not trigger a speech transition.
- The coordinator never reorders the queue or starts playback. The host decides which music item to play next.
- Stale/inactive content events are ignored, preventing old playback callbacks from affecting a new session.
- Selected Motivation folders are optional and can provide a strong user routing signal.

Integration flow:

`folder/user classification + host playback callbacks → MotivationCoordinator → MotivationIntent → host queue/playback decision`

This creates the contract for future intelligent sequencing: **motivation speech can lead into music, while the existing Resonate playback engine remains the only playback owner.**

## Audiobook Mode

Audiobook Mode is the sixth concrete Modes behavior and is built around **chapter continuity and precise resume**, not generic long-audio heuristics.

- Disables crossfade and shuffle so chapters retain natural boundaries.
- Enables precise resume and emphasizes playback speed.
- Suggests a sleep timer for the host UI.
- Exposes chapter-navigation availability as an integration signal.
- Supports explicit start, pause, resume, complete, and exit session boundaries.
- Carries the latest known position across lifecycle events without owning persistence or seeking.
- A supplied resume position produces a `resumePositionRequired` intent when a session starts.
- Invalid negative positions are ignored.
- Stale lifecycle operations are ignored after completion or exit.
- Audiobook Mode does not inspect duration itself. The MediaClassifier, selected content folders, and individual user overrides determine whether content is an audiobook.
- Selected Audiobook folders are optional and can provide a strong user routing signal.
- The coordinator never starts playback, seeks, changes chapters, manages the sleep timer, or stores progress.

Integration flow:

`folder/user classification + host resume/chapter data → AudiobookCoordinator → AudiobookIntent → host playback/navigation integration`

The host Resonate app remains responsible for chapter metadata, actual chapter navigation, position persistence/seeking, speed changes, sleep-timer execution, and playback.
