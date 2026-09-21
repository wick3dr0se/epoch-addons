# epoch-addons

My Project Epoch (3.3.5 private server) addons

Most will work with across WotLK but may be configured towards Epoch specifics (how vanilla + TBC talents and other things affect).

## Addons

| Addon | Type | Description |
|-------|------|-------------|
| [ElvUI](ElvUI/) | UI replacement | Fork of ElvUI Epoch (v6.11) for 3.3.5a, slimmed down and tuned for performance. |
| [ElvUI Seal Twist](ElvUI_SealTwist/) | ElvUI plugin | Paladin seal-twisting helper. Highlights the twist window on your swing bar and shows which seal to cast next. |
| [ElvUI Damage Meter](ElvUI_DamageMeter/) | ElvUI plugin | Minimal damage meter. Tracks damage per spell with DPS, hit count, and averages. |

## Install

Download the addon folder(s) you want and drop them into your WoW `Interface/AddOns/` directory.

```
Wow/
  Interface/
    AddOns/
      ElvUI/
        ElvUI.toc
        (Core/, Modules/, Libraries/, Media/, ...)
      ElvUI_SealTwist/
        ElvUI_SealTwist.toc
        ElvUI_SealTwist.lua
        (README.md)
      ElvUI_DamageMeter/
        ElvUI_DamageMeter.toc
        ElvUI_DamageMeter.lua
        (README.md)
```

`ElvUI` replaces the stock ElvUI install. It still needs `ElvUI_OptionsUI` (unmodified, taken from the upstream ElvUI release) alongside it for the in-game config panel.
