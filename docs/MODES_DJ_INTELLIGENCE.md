# Modes × DJ Mode × Intelligence

## Short answer

**Podcast / Audiobook do not hard-disable DJ or Intelligence settings.**  
They **constrain the engine** so speech stays precise:

| Feature | Podcast / Audiobook | Music-oriented modes |
|---------|---------------------|----------------------|
| Crossfade | **Blocked by policy** | User setting + mode allow |
| DJ handoffs (beat/tempo/SFX) | **Soft-gated off** while crossfade is blocked | Active when DJ master is on |
| Intelligence recommendations | Still generated; shelf keeps **mode-acceptable** items | Full mix on shelf + home |
| Autopilot | Biased toward speech types | Music-first |
| Mode shelf | Folders + classifier + filtered intel | Same pipeline |

## Why

- DJ Mode is a **crossfade refinement layer**. Without crossfade, beat-align and stretch have nowhere safe to act.
- Intelligence is a **ranking / suggestion** layer. It should not force music blends into a podcast session.
- Modes own **policy**, not a second player.

## User-visible honesty

- Crossfade screen: “Blocked by {mode}” when settings are on but policy forbids blending.
- DJ settings can remain enabled; engine ignores handoff features until the mode allows crossfade again.

## Shelf refresh

Shelves rebuild whenever `ModeProvider` or library/intelligence notifies (folder add/remove, mode change, recommendation refresh). No separate cache to go stale.
