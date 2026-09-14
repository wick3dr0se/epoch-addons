# ElvUI Seal Twist

Paladin seal-twisting helper for WoW 3.3.5 (TBC mechanics). Overlays the twist window on ElvUI's swing bar and shows which seal to cast next.

## What it does

- Highlights the twist window on ElvUI_SwingBar with a colour overlay
- Shows the next seal icon next to the bar during the twist window
- Detects active seal via UnitBuff and cycles through your configured sequence
- Configurable twist window (0.30-0.60s, default 0.40s) for reaction-time padding
- Icon position, size, and offsets are all configurable

## Dependencies

- [ElvUI](https://github.com/ElvUI-WotLK/ElvUI) -- ElvUI for WotLK 3.3.5
- [ElvUI_SwingBar](https://github.com/ElvUI-WotLK/ElvUI_SwingBar) -- provides the swing bar this addon overlays

## How seal twisting works

Seals linger for 0.5s after being replaced. During that window, both the old and new seal are active. The twist window shows when you should cast the next seal so it activates before the swing lands.

## Configuration

Open ElvUI settings, go to **Plugins > Seal Twist**.

### Timing

- **Twist Window** (0.30-0.60s, default 0.40s) -- how early to show the icon and bar colour. Add padding if you react slowly; you won't cast instantly.

### Seal Sequence

- **Seal Sequence** -- comma-separated seal names (default: `Seal of Command,Seal of Righteousness`). The addon cycles through these in order. Put your faster seal first if weapon speed matters.

### Icon

- **Size** (16-64px, default 32)
- **Position** -- Left, Right, Top, Bottom of the bar
- **X/Y Offset** -- fine-tune placement

### Colours

- **Twist Window Colour** -- colour of the bar overlay and icon pulse during the twist window

## Saved variables

All settings are stored in `ElvUI_SealTwistDB` in your WTF saved variables.
