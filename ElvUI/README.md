# ElvUI

Fork of [ElvUI Epoch](https://github.com/Bennylavaa/ElvUI-Epoch) v6.11, the WotLK backport for WoW 3.3.5a. Works on Project Epoch and any 3.3.5a server. The installed folder stays `ElvUI` so plugins resolving `Dependencies: ElvUI` keep working.

## What changed from stock

The main improvement is a performance-optimised nameplate update loop. Stock ElvUI ran the expensive per-plate pass (mouseover/target state, unit info, threat, glow) on every rendered frame with no throttling. This fork fixes that, plus cleans up dead code and a pre-existing rendering bug.

All changes are in `Modules/Nameplates/Nameplates.lua` unless noted.

### Nameplate performance

- **Merged two VisiblePlates loops into one.** Stock iterated all visible plates twice per frame: once for the alpha pin (every frame) and once for the throttled work (20 Hz). Now a single loop with a `throttled` flag. Saves one full table iteration per frame.
- **Throttled per-plate pass at 20 Hz.** `PLATE_UPDATE_INTERVAL = 0.05`. This gates the expensive work (mouseover/target state, `GetUnitInfo`, threat, glow) while plate discovery and the alpha pin stay per-frame so new plates appear instantly and target highlighting stays smooth.
- **Alpha pin skips redundant SetAlpha(1).** Reads parent alpha first, only calls `SetAlpha(1)` when it's not already 1. Cuts the C call roughly in half when a target exists. Still per-frame, still unconditional in intent. Gating this to 20 Hz caused visible flicker; skipping a *redundant* write is different and safe.
- **Cached bordercolor in StyleFrame.** `unpack(E.media.bordercolor)` called once into locals instead of 8 times per plate styled. Also fixes a pre-existing bug: the borderright backdrop had `noscalemult` instead of `-noscalemult` on its BOTTOMRIGHT anchor, which offset the right border backdrop incorrectly.

### Dead code removal

- **Removed LFR skin** (`Modules/Skins/Blizzard/LFR.lua`). LFR was added in Cataclysm 4.3 and does not exist in 3.3.5a. The skin file was 88 lines of dead code that would error if its settings toggle were enabled.

### Aura performance

- **Batched UNIT_AURA updates.** Stock processed every buff/debuff change immediately, each triggering a full `UnitAura` scan and sort. In raids this fires extremely often. The fork debounces with a 0.15s delay so multiple changes within the window coalesce into one scan.

### Tuning

The nameplate throttle has no in-game toggle. Edit `PLATE_UPDATE_INTERVAL` in `Modules/Nameplates/Nameplates.lua` directly:

- **Raise toward 0.1** to trade CPU for a choppier target glow
- **Lower toward 0.02** if highlighting feels laggy

The alpha pin must stay per-frame. Gating it causes flicker when anything is targeted.

## Dependencies

WoW 3.3.5a client. Works standalone or with any ElvUI plugin that resolves `Dependencies: ElvUI`.

## Saved variables

`ElvDB` (account-wide), `ElvPrivateDB` (account-wide), `ElvCharacterDB` (per-character).
