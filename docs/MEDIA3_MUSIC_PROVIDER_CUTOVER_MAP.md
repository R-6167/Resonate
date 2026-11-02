# Media3 MusicProvider Cutover Map

This is the working dependency map for removing the legacy `just_audio` engine from `MusicProvider`. It is intentionally scoped to the migration branch and is not a declaration that production cutover is complete.

## Current ownership boundary

`PlaybackEngineSession` is the intended single provider-facing authority: commands and observations must come from the same session. `Media3ProviderSession` composes the Media3 runtime and state bridge. It is not yet injected into production `MusicProvider`.

The current provider still constructs `EnginePair` and exposes compatibility getters for both `AudioPlayer` instances. The provider also has direct responsibilities beyond transport, so replacing only its observation streams would split authority.

## Legacy dependency clusters

| Cluster | Current provider responsibilities | Required Media3 destination |
|---|---|---|
| Engine construction / identity | `EnginePair`, active/inactive player aliases, equalizer and loudness aliases | Media3 session + native deck/session capabilities; remove player object exposure |
| State and observations | active player streams, stream binding, service-state publication, completion/watchdog observation | `PlaybackEngineSession` state projection and event/observation contract |
| Transport and queue | play/load, pause/resume, seek, next/previous, stop, gapless queue seek | session command lane and native queue reconciliation |
| Crossfade / repeat-one | preload, standby deck, true crossfade, repeat-self handoff, idle-deck silencing | native Media3 dual-deck crossfade; provider retains policy only |
| Recovery | silent playback checks, engine recreation, cancelled handoff recovery, watchdogs | Media3 connection/player lifecycle and explicit recovery outcomes |
| Focus / interruptions / routing | `AudioSession.instance`, focus claims, duck/unduck, route changes, resume after focus | Media3 service focus ownership and session events |
| Volume / leveling | active-player volume, crossfade master, track leveling, interruption duck, fade multipliers | atomic session gain factors; no direct per-player volume writes |
| DSP / audio effects | active/inactive Android effect objects and session-ID subscriptions | Media3 active audio-session stream and native DSP attachment |
| DJ / automation | tempo speed, SFX, beat-aligned handoffs, automation preloads | policy remains in Resonate; execution uses session speed/preload/crossfade commands |
| Modes / history | podcast/audiobook synchronization, playback history and mode boundary logic | consume the same reconciled session state and transport outcomes |

## Migration order

1. **Session injection and lifecycle:** give `MusicProvider` one owned `PlaybackEngineSession`, with deterministic start/dispose and a test fake. Keep the legacy engine behind an explicit temporary implementation until each responsibility has moved.
2. **Transport + state together:** migrate queue loads/edits, transport commands, current-song/index/position/playing state, service publication, and observation binding as one cut. No mixed command/state authority.
3. **Crossfade and repeat-one:** replace provider A/B engine manipulation with native Media3 preload/crossfade/cancel commands; preserve Resonate transition policy and user-intent guards.
4. **Focus, recovery, and gain:** route interruption, route/session lifecycle, recovery, leveling, ducking, and volume through Media3 session capabilities.
5. **Effects, modes, DJ, history:** bind DSP to the active Media3 audio session; verify all automation and mode behavior against the same session state.
6. **Delete legacy engine:** remove `EnginePair`, `just_audio` player fields/imports, legacy session subscriptions, obsolete adapters, and package dependency only after repository-wide reference and dependency scans pass.

## Risk rules

- Never bind Media3 observations while commands still target `just_audio`.
- Never run two playback engines as competing production authorities.
- A compile/CI pass is necessary but not sufficient for audio behavior.
- Keep the migration branch isolated from `Resonate-True-Apk` until the complete production path and release APK are validated on devices.
- Any temporary compatibility path must be explicit, testable, and removed before PR #219 is marked ready to merge.

## Immediate next implementation slice

The first provider change should introduce an injectable `PlaybackEngineSession` ownership seam and lifecycle tests, without switching production transport yet. The following slice can then migrate transport and state together behind that seam. This avoids the unsafe half-step of changing only streams or only commands.
