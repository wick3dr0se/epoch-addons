# ElvUI Damage Meter

Minimal damage meter for Project Epoch. Tracks damage per spell with DPS, hit count, and averages. Integrates with ElvUI's mover system for positioning.

## What it does

- Tracks all player damage via combat log (auto-attacks, spells, DoTs)
- Shows per-spell breakdown: icon, name, total damage, DPS, hits, percentage
- Displays spell icons via GetSpellInfo with spellID fallback
- Uses ElvUI's class/accent colour for the title bar
- Shows by default on login, data resets on zone or manual reset

## Dependencies

- [ElvUI Epoch](https://github.com/Bennylavaa/ElvUI-Epoch) -- Epoch's custom ElvUI fork

## Configuration

Open ElvUI settings, go to **Plugins > Damage Meter**. Position is managed via **Toggle Anchors** (ElvUI > Move Anchors), same as any other ElvUI frame.

### Size

- **Width** (180-500, default 250)
- **Height** (80-500, default 200)
- **Row Height** (14-28, default 18)

### Colours

- **Accent Color** -- colour of the status bars
- **Backdrop Color** -- window background (matches ElvUI's semi-transparent dark by default)

### Display

- **Show DPS** -- toggle DPS column
- **Show Hits** -- toggle hit count column
- **Sort By** -- Total Damage or DPS

### Behaviour

- Close/reset button (X) in title bar clears all data
- `/dm` toggles the window

## Saved variables

All settings are stored in `ElvUI_DamageMeterDB` in your WTF saved variables.
