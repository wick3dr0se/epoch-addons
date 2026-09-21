# ElvUI Seal Twist

Paladin seal-twisting helper for WoW 3.3.5 (TBC mechanics). Judgment-CD based rotation overlay for ElvUI_SwingBar.

## How it works

The optimal seal twist rotation:

1. **Primary seal active** (Seal of Command), most of the time
2. **Twist window**, in the last ~0.4s before the swing, cast the finisher seal (Seal of Penitence/Righteousness/Justice). Both seals proc on the swing.
3. **Judgment**, cast immediately after the swing lands
4. **Primary seal**, recast to start the cycle again

The addon only suggests the finisher seal when Judgment is off cooldown (or nearly off), since there's no point twisting if you can't Judgement right after.

## What it shows

- **Finisher seal icon** during the twist window (when Judgment is ready)
- **Judgment icon** immediately after the swing lands
- **Primary seal icon** after Judgment is cast (until the next twist window)
- **Bar colour overlay** during the twist window (intensifies as swing approaches)
- **No icon** when Judgment is on cooldown (no twist needed)

## Dependencies

- [ElvUI](../ElvUI/) -- forked from [ElvUI-Epoch](https://github.com/Bennylavaa/ElvUI-Epoch), stable/tested on Epoch
- [ElvUI_SwingBar](https://github.com/ElvUI-WotLK/ElvUI_SwingBar) -- provides the swing bar this addon overlays

## Configuration

Open ElvUI settings, go to **Plugins > Seal Twist**.

### Seals

- **Primary Seal**, the seal active most of the time (default: Seal of Command)
- **Finisher Seal**, cast during the twist window, right before the swing (default: Seal of Righteousness). Only suggested when Judgment is off cooldown.

### Timing

- **Twist Window** (0.30-0.60s, default 0.40s), how early to show the finisher seal. Seal lingers 0.5s; 0.4s is the safe default. Add padding if you react slowly.
- **Judgment Ready Window** (0-3.0s, default 1.5s), show the finisher seal when Judgment is within this many seconds of being ready.
- **Show Prediction** (default: on), show a dimmed finisher seal icon before the twist window as a "get ready" indicator.
- **Prediction Window** (0.20-1.50s, default 0.60s), how early to show the dimmed icon before the twist window starts.

### Icon

- **Size** (16-64px, default 32)
- **Position**: Left, Right, Top, Bottom of the bar
- **X/Y Offset**, fine-tune placement

### Colours

- **Twist Window Colour**, colour of the bar overlay during the twist window
- **Judgment Window Colour**, colour of the bar overlay when Judgment is ready and finisher seal is active

## Saved variables

All settings are stored in `ElvUI_SealTwistDB` in your WTF saved variables.
