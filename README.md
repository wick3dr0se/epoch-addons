# epoch-addons

WoW 3.3.5a addons for Project Epoch. Most work on any WotLK server but may be tuned toward Epoch specifics (vanilla + TBC talents, custom mechanics).

## Addons

| Addon | Type | Description |
|-------|------|-------------|
| [ElvUI](ElvUI/) | UI replacement | Fork of [ElvUI-Epoch](https://github.com/Bennylavaa/ElvUI-Epoch) (v6.11). Performance-optimised nameplates, auras, tags, portraits, and GC. Stable on Epoch. |
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
```

`ElvUI` replaces the stock ElvUI install. It still needs `ElvUI_OptionsUI` (unmodified, taken from the upstream ElvUI release) alongside it for the in-game config panel.

## Compatibility

Tested on WoW 3.3.5a (Project Epoch). The ElvUI fork should work on any WotLK 3.3.5a server. Plugins require the ElvUI fork as a dependency.

3.3.5a runs embedded Lua 5.1. No `C_Timer`, `SetColorTexture`, `CombatLogGetCurrentEventInfo`, `BackdropTemplateMixin`, or other retail APIs.
