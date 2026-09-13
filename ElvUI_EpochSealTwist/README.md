# ElvUI Epoch Seal Twist

A Retribution Paladin seal-twisting helper for Project Epoch. Overlays a twist window on your ElvUI swing bar and shows which seal to cast next.

## What it does

- Highlights the twist window (last 0.40s before your swing) with a red overlay on the swing bar
- Shows a pulsing icon of the next seal to cast during the twist window
- Suggests which seal to use based on your configured sequence
- Defaults to the first seal in your sequence when no seal is active

## Dependencies

- [ElvUI Epoch](https://github.com/Bennylavaa/ElvUI-Epoch) -- Epoch's custom ElvUI fork
- [ElvUI_SwingBar](https://github.com/ElvUI-WotLK/ElvUI_SwingBar) -- swing timer plugin

The addon hooks into the Twohand swing bar element. If the swing bar isn't enabled in ElvUI, nothing will show.

## Configuration

Open ElvUI settings, go to **Plugins > Epoch Seal Twist**.

### Timing

- **Twist Window** (0.30s - 0.60s, default 0.40s) -- how many seconds before the swing to show the indicator. Seal lingers 0.5s after casting, so 0.40s is the safe default with a small buffer.

### Seal Sequence

Comma-separated list of seal names in cast order. The addon cycles through this list.

Default: `Seal of Command,Seal of Righteousness`

Examples:
- `Seal of Command,Seal of Righteousness` -- SoC/SoR twist
- `Seal of Righteousness,Seal of Command` -- SoR/SoC twist
- `Seal of Command,Seal of Blood` -- SoC/SoB twist (if available on your server)

When no seal is active, the addon suggests the first seal in the sequence.

### Icon

- **Size** (16-64px, default 32)
- **Position** -- LEFT, RIGHT, TOP, or BOTTOM relative to the swing bar
- **X/Y Offset** -- fine-tune placement

### Colours

- **Twist Window Colour** -- colour of the bar overlay and icon pulse during the twist window

## How seal twisting works

When you cast a new seal, the old seal doesn't disappear immediately -- it lingers for about 0.5 seconds. If your swing lands during that overlap, you get the benefit of both seals. The twist window is the safe period to cast the new seal so the overlap covers your swing.

## Saved variables

All settings are stored in `EpochSealTwistDB` in your WTF saved variables.
