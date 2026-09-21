# ElvUI

Personal fork of [ElvUI Epoch](https://github.com/Bennylavaa/ElvUI-Epoch) v6.11, the WotLK backport for WoW 3.3.5a on Project Epoch. Handles frames, layout, and profiles. The installed folder stays `ElvUI` so plugins resolving `Dependencies: ElvUI` keep working.

## What changed from stock

The only code change is a performance throttle on the nameplate update loop (`Modules/Nameplates/Nameplates.lua`). Stock ElvUI ran the expensive per-plate pass (mouseover/target state, unit info, threat, glow) on every rendered frame. The fork gates it to 20 Hz via `PLATE_UPDATE_INTERVAL` (0.05s). Plate discovery and the alpha pin stay per-frame so new plates appear instantly and target highlighting stays smooth.

**If target glow or highlight feels choppy**, raise `PLATE_UPDATE_INTERVAL` toward 0.1. **If it feels laggy**, lower toward 0.02. The alpha pin must stay per-frame; gating it causes flicker when anything is targeted.

## Dependencies

WoW 3.3.5a client (Project Epoch). No optional dependencies beyond stock ElvUI OptionalDeps (`Blizzard_DebugTools`, `SharedMedia`, `Tukui`, `ButtonFacade`).

Known-compatible plugins: ElvUI_SwingBar, ElvUI_ExtraActionBars, ElvUI_DmgAtNameplates, AddOnSkins, ProjectZidras, ElvUIEnhanced.

## Configuration

All settings are in the standard ElvUI settings panel. The nameplate throttle has no in-game toggle; edit `PLATE_UPDATE_INTERVAL` in `Modules/Nameplates/Nameplates.lua` directly.

## Saved variables

`ElvDB` (account-wide), `ElvPrivateDB` (account-wide), `ElvCharacterDB` (per-character).
