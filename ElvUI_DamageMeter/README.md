# ElvUI Damage Meter

Minimal damage meter for WoW 3.3.5. Tracks damage per spell with DPS, hit count, and averages. Toggle via `/dm` or the icon button in the right chat panel.

## What it does

- Tracks all player damage via combat log (auto-attacks, spells, DoTs)
- Shows per-spell breakdown: icon, name, total damage, DPS, hits, percentage
- Bar width shows relative damage (Melee at 33% = full bar, Crusader Strike at 24% = ~73% bar)
- Spell icons via GetSpellInfo with spellID fallback
- Auto Attack icon for melee swings
- Coloured bars based on spell school (fire=orange, frost=blue, holy=yellow, etc.)
- Shows by default on login, data resets on zone or manual reset (X button)

## Dependencies

- [ElvUI](../ElvUI/) -- forked from [ElvUI-Epoch](https://github.com/Bennylavaa/ElvUI-Epoch), stable/tested on Epoch

## Configuration

Open ElvUI settings, go to **Plugins > Damage Meter**.

- **Row Height** (14-28, default 18)
- **Accent Color** -- colour of the status bars
- **Backdrop Color** -- window background
- **Show DPS** -- toggle DPS column
- **Show Hits** -- toggle hit count column
- **Sort By** -- Total Damage or DPS

## Saved variables

All settings are stored in `ElvUI_DamageMeterDB` in your WTF saved variables.
