# ElvUI

Fork of [ElvUI Epoch](https://github.com/Bennylavaa/ElvUI-Epoch) v6.11, the WotLK backport for WoW 3.3.5a. Works on Project Epoch and any 3.3.5a server. The installed folder stays `ElvUI` so plugins resolving `Dependencies: ElvUI` keep working.

## What changed from stock

Performance-focused changes across nameplates, auras, unit frames, tags, and garbage collection. All changes are backward-compatible with the standard ElvUI settings panel.

Derived from community-reported issues (Reddit r/classicwow, r/WowUI, MMO-Champion) and the [upstream ElvUI CHANGELOG](https://github.com/tukui-org/ElvUI/blob/main/CHANGELOG.md) performance fixes (versions 11.11 through 14.00).

### Nameplate performance

- **Merged two VisiblePlates loops into one.** Stock iterated all visible plates twice per frame: once for the alpha pin (every frame) and once for the throttled work (20 Hz). Now a single loop with a `throttled` flag. Saves one full table iteration per frame.
- **Throttled per-plate pass at 20 Hz.** `PLATE_UPDATE_INTERVAL = 0.05`. Gates the expensive work (mouseover/target state, `GetUnitInfo`, threat, glow) while plate discovery and the alpha pin stay per-frame so new plates appear instantly and target highlighting stays smooth.
- **Alpha pin skips redundant SetAlpha(1).** Reads parent alpha first, only calls `SetAlpha(1)` when it's not already 1. Cuts the C call roughly in half when a target exists. Still per-frame, still unconditional in intent.
- **Cached bordercolor in StyleFrame.** `unpack(E.media.bordercolor)` called once into locals instead of 8 times per plate styled. Also fixes a pre-existing bug: the borderright backdrop had `noscalemult` instead of `-noscalemult` on its BOTTOMRIGHT anchor.
- **Conditional style filter events** (cf. upstream L4319). `PLAYER_TARGET_CHANGED` is now only registered when a filter actually uses `isTarget`/`notTarget` triggers. Reduces unnecessary filter evaluation on target switches.

### Aura and tag performance

- **Batched UNIT_AURA updates.** Stock processed every buff/debuff change immediately, each triggering a full `UnitAura` scan and sort. The fork debounces with a 0.15s delay so multiple changes within the window coalesce into one scan.
- **Removed PetBar UNIT_AURA** (cf. upstream L3455). Pet auras don't affect action bar icons. Stock registered `UNIT_AURA` on the pet bar and iterated all 10 action slots on every change.
- **Batched oUF tag updates** (cf. upstream L3458, "reaping issue"). Tags are queued on events and processed once per frame via OnUpdate instead of immediately on every event. Prevents call stack accumulation where multiple events in one frame each trigger cascading tag updates that drain FPS over time.
- **Fixed tag literal OnUpdate fallback** (cf. upstream L4387). Tag strings containing a mix of event-driven tags and OnUpdate tags were forced entirely to OnUpdate polling. Now only tags that explicitly need OnUpdate use it; event-driven tags in the same string keep their events.

### Unit frame performance

- **Force 2D portraits on group frames** (cf. upstream L1246). 3D `PlayerModel` frames are expensive. Raid, party, boss, and arena frames now always use 2D portraits regardless of the user's Portrait > Style setting. Individual frames (player, target, focus, pet) keep their choice.

### Garbage collection

- **Proactive GC tuning.** Increases the Lua 5.1 GC step multiplier and runs incremental collection steps once per second. Spreads garbage collection across frames instead of letting it spike and cause frame drops.

### Dead code removal

- **Removed LFR skin.** LFR was added in Cataclysm 4.3 and does not exist in 3.3.5a. The skin file was 88 lines of dead code that would error if its settings toggle were enabled.

### Tuning

The nameplate throttle has no in-game toggle. Edit `PLATE_UPDATE_INTERVAL` in `Modules/Nameplates/Nameplates.lua` directly:

- **Raise toward 0.1** to trade CPU for a choppier target glow
- **Lower toward 0.02** if highlighting feels laggy

The alpha pin must stay per-frame. Gating it causes flicker when anything is targeted.

## Dependencies

WoW 3.3.5a client. Works standalone or with any ElvUI plugin that resolves `Dependencies: ElvUI`.

## Saved variables

`ElvDB` (account-wide), `ElvPrivateDB` (account-wide), `ElvCharacterDB` (per-character).
