# MusicProvider structural splits

~5.3k-line `ChangeNotifier` — public Phase 0 API stays on MusicProvider.

## Done (collaborators under `lib/playback/`)

| Collaborator | Owns |
|--------------|------|
| QueueStore | Queue list, index, shuffle, ID persistence |
| CrossfadeSettings | Enabled / duration / fade (value object; may still dual-own with CrossfadeProvider) |
| ResumePositionStore | Per-song + last-session resume |
| AudioFocusSettings | Automation enabled + level prefs |
| CrossfadeRuntime | In-flight flags, generations, preload ids |
| TransportEpoch | User epoch, in-flight/pending, wants-playing |
| EnginePair | A/B players + Android EQ/loudness construction |
| DjHandoffState | DJ feature flags + last-handoff snapshot |
| AudioLevelingSettings | Leveling enabled + target RMS prefs |

## Still on MusicProvider — recommended extraction order

### Low risk (state / prefs bags)
1. **FocusInterruptionRuntime** — `_isDucked`, unduck-pending, focus-resume generation, loss timers
2. **PlaybackHistorySession** — active `ListeningEvent`, serial queue, position ticks
3. **GaplessWindowState** — concatenating window ids / start index / active flag
4. **ModePlaybackPolicy** — `_modeCrossfadeAllowed`, shuffle allowed, precise resume, mode boundary gen
5. Finish **CrossfadeSettings** wiring into `setCrossfade*` if UI prefs still live only on CrossfadeProvider

### Medium risk (coordinators, still thin)
6. **LevelingRuntime** — `_eqPreampScale`, `_trackLevelingScale`, generation, refresh orchestration (keep LoudnessService)
7. **VolumeFacade** — user volume, sleep fade, system volume poll channel
8. **PlayerStreamBinder** — `_bindActivePlayerStreams`, position/state/duration subscriptions

### High risk (async orchestration — do last)
9. **CrossfadeOrchestrator** — `_performTrueCrossfade`, automatic crossfade, preload loaders
10. **TransportController** — `playSong` / `next` / `prev` / `pause` / `seek` bodies + serialize gate
11. **DjHandoffOrchestrator** — `_prepareDjHandoff` / `_applyV2DjHandoff` / recover (uses DjEngine)
12. **AudioEffectsLifecycle** — lazy native effects attach, `AudioEffectsController` beyond handles

## Rules
1. Public API unchanged
2. Transport always wins (TransportEpoch preempts CrossfadeRuntime)
3. State bags first; move async engine methods only after flags are isolated
4. Prefer small wire patches + CI when shipping GitHub-only
