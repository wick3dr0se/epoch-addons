--[[
    ElvUI Seal Twist — Paladin seal-twisting helper for WoW 3.3.5
    Judgment-CD based rotation: Primary seal → Finisher seal (twist) → Swing → Judgment → Primary seal.
    Only suggests the finisher seal when Judgment is off cooldown.
]]

local addonName, ns = ...

---------------------------------------------------------------------------
-- 3.3.5 timer (C_Timer doesn't exist until BfA)
---------------------------------------------------------------------------
local timerFrame = CreateFrame("Frame")
local timers = {}
local timerCount = 0

local function ScheduleTimer(delay, func)
    timerCount = timerCount + 1
    timers[timerCount] = { remaining = delay, func = func }
    timerFrame:Show()
end

timerFrame:Hide()
timerFrame:SetScript("OnUpdate", function(self, elapsed)
    local anyActive = false
    for id, t in pairs(timers) do
        t.remaining = t.remaining - elapsed
        if t.remaining <= 0 then
            t.func()
            timers[id] = nil
        else
            anyActive = true
        end
    end
    if not anyActive then self:Hide() end
end)

---------------------------------------------------------------------------
-- Defaults
---------------------------------------------------------------------------
local DEFAULTS = {
    twistWindow     = 0.40,   -- twist zone (seconds before swing; seal lingers 0.5s)
    judgementCD     = 1.5,    -- show finisher when Judgment is within this many seconds of being ready
    barColor        = { r = 1.0, g = 0.2, b = 0.1 },   -- red during twist window
    iconSize        = 32,     -- icon size (pixels)
    iconPosition    = "RIGHT", -- icon position: LEFT, RIGHT, TOP, BOTTOM
    iconXOffset     = 8,      -- horizontal offset from bar edge
    iconYOffset     = 0,      -- vertical offset from bar edge
    primarySeal     = "Seal of Command",
    finisherSeal    = "Seal of Righteousness",
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local db
local overlay          = nil
local iconFrame        = nil
local hookedBar        = nil
local hookInstalled    = false
local activeSeal       = nil   -- which seal is currently buffed
local phase            = "idle" -- "idle" | "twist" | "judgement" | "primary"
local swingLanded      = false  -- true between swing landing and next OnUpdate

---------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------
local DEBUG = false
local function dbg(msg)
    if DEBUG then print("|cfff0a0d0SealTwist|r: " .. msg) end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function DetectActiveSeal()
    for i = 1, 40 do
        local name = UnitBuff("player", i)
        if not name then break end
        if name == db.primarySeal then return db.primarySeal end
        if name == db.finisherSeal then return db.finisherSeal end
    end
    return nil
end

local function GetSealIcon(sealName)
    local _, _, icon = GetSpellInfo(sealName)
    return icon
end

local function GetJudgementCooldown()
    local start, duration, enable = GetSpellCooldown("Judgement")
    if not start or start == 0 then return 0 end
    local remaining = (start + duration) - GetTime()
    if remaining < 0 then remaining = 0 end
    return remaining
end

local function IsJudgementReady()
    return GetJudgementCooldown() == 0
end

local function IsJudgementNearlyReady()
    return GetJudgementCooldown() <= db.judgementCD
end

local function GetJudgementIcon()
    local _, _, icon = GetSpellInfo("Judgement")
    return icon
end

---------------------------------------------------------------------------
-- UI creation
---------------------------------------------------------------------------

local function CreateOverlay(bar)
    local f = CreateFrame("Frame", nil, bar)
    f:SetFrameLevel(bar:GetFrameLevel() + 5)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints(bar)
    f.tex:SetTexture(1, 1, 1, 1)
    f.tex:SetBlendMode("ADD")
    f:Hide()

    local icon = CreateFrame("Frame", nil, bar)
    icon:SetFrameLevel(bar:GetFrameLevel() + 10)
    icon.texture = icon:CreateTexture(nil, "OVERLAY")
    icon.texture:SetAllPoints(icon)
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:Hide()

    return f, icon
end

local function PositionIcon(bar, icon)
    icon:ClearAllPoints()
    local pos = db.iconPosition
    local xOff = db.iconXOffset
    local yOff = db.iconYOffset
    local sz   = db.iconSize

    icon:SetSize(sz, sz)

    if pos == "LEFT" then
        icon:SetPoint("RIGHT", bar, "LEFT", -xOff, yOff)
    elseif pos == "RIGHT" then
        icon:SetPoint("LEFT", bar, "RIGHT", xOff, yOff)
    elseif pos == "TOP" then
        icon:SetPoint("BOTTOM", bar, "TOP", xOff, yOff)
    elseif pos == "BOTTOM" then
        icon:SetPoint("TOP", bar, "BOTTOM", xOff, -yOff)
    else
        icon:SetPoint("LEFT", bar, "RIGHT", xOff, yOff)
    end
end

---------------------------------------------------------------------------
-- Icon update
---------------------------------------------------------------------------

local function ShowIcon(bar, tex)
    if not iconFrame or not tex then return end
    iconFrame:Show()
    iconFrame.texture:SetTexture(tex)
    PositionIcon(bar, iconFrame)
    local pulse = 1.0 + 0.15 * math.sin(GetTime() * 8)
    iconFrame:SetScale(pulse)
end

local function HideIcon()
    if iconFrame then iconFrame:Hide() end
end

---------------------------------------------------------------------------
-- Overlay update (bar colour during twist window)
---------------------------------------------------------------------------

local function UpdateOverlay(bar, remaining)
    if not overlay then return end

    local inTwist = remaining <= db.twistWindow and remaining > 0
    local inTwistPhase = (phase == "twist")

    if not inTwist and not inTwistPhase then
        overlay:Hide()
        return
    end

    overlay:Show()
    overlay.tex:ClearAllPoints()
    overlay.tex:SetAllPoints(bar)
    local bc = db.barColor
    if inTwist then
        local intensity = 1 - (remaining / db.twistWindow)
        overlay.tex:SetVertexColor(bc.r, bc.g, bc.b, 0.30 + 0.35 * intensity)
    else
        overlay.tex:SetVertexColor(bc.r, bc.g, bc.b, 0.30)
    end
end

---------------------------------------------------------------------------
-- Phase logic + icon update
---------------------------------------------------------------------------

local function UpdatePhase(bar, remaining)
    -- PHASE: twist — finisher seal during pre-swing window
    if phase == "twist" then
        if remaining <= 0 then
            -- Swing landed — move to judgement phase
            swingLanded = true
            if IsJudgementReady() then
                phase = "judgement"
                dbg("Phase: judgement")
                ShowIcon(bar, GetJudgementIcon())
            else
                phase = "primary"
                dbg("Phase: primary (no judgment)")
                ShowIcon(bar, GetSealIcon(db.primarySeal))
            end
        else
            ShowIcon(bar, GetSealIcon(db.finisherSeal))
        end
        return
    end

    -- PHASE: judgement — show Judgment icon after swing
    if phase == "judgement" then
        if IsJudgementReady() then
            ShowIcon(bar, GetJudgementIcon())
        else
            -- Judgment was cast (went on CD) — transition to primary
            phase = "primary"
            dbg("Phase: primary")
            ShowIcon(bar, GetSealIcon(db.primarySeal))
        end
        return
    end

    -- PHASE: primary — show primary seal icon (after Judgement, before next twist)
    if phase == "primary" then
        if activeSeal == db.primarySeal then
            -- Primary seal is active — we're done, back to idle
            phase = "idle"
            dbg("Phase: idle")
            HideIcon()
        else
            ShowIcon(bar, GetSealIcon(db.primarySeal))
        end
        return
    end

    -- PHASE: idle — decide whether to enter twist
    if phase == "idle" then
        if remaining <= db.twistWindow and remaining > 0 then
            -- In twist window — only suggest finisher if Judgment is ready or nearly ready
            if IsJudgementReady() or IsJudgementNearlyReady() then
                phase = "twist"
                dbg("Phase: twist (Judgment ready/nearly)")
                ShowIcon(bar, GetSealIcon(db.finisherSeal))
            else
                -- Judgment not ready — no twist needed
                HideIcon()
            end
        else
            HideIcon()
        end
    end
end

---------------------------------------------------------------------------
-- OnUpdate tick
---------------------------------------------------------------------------

local function SwingTick(bar, elapsed)
    if not bar.min or not bar.max then return end
    local remaining = bar.max - GetTime()

    -- Sync active seal
    activeSeal = DetectActiveSeal()

    UpdatePhase(bar, remaining)
    UpdateOverlay(bar, remaining)
end

---------------------------------------------------------------------------
-- Persistent hook via SetScript wrapper
---------------------------------------------------------------------------

local function InstallHook(bar)
    if hookInstalled then return end
    hookInstalled = true
    hookedBar = bar

    overlay, iconFrame = CreateOverlay(bar)
    dbg("Hook installed on " .. tostring(bar:GetName()))

    local lastHandler = nil
    local setting     = false

    hooksecurefunc(bar, "SetScript", function(self, script, func)
        if script ~= "OnUpdate" or setting then return end
        lastHandler = func
        setting = true
        self:SetScript("OnUpdate", function(s, e)
            if lastHandler then lastHandler(s, e) end
            SwingTick(s, e)
        end)
        setting = false
    end)

    local current = bar:GetScript("OnUpdate")
    if current then
        lastHandler = current
        setting = true
        bar:SetScript("OnUpdate", function(s, e)
            if lastHandler then lastHandler(s, e) end
            SwingTick(s, e)
        end)
        setting = false
        dbg("Wrapped existing OnUpdate")
    end
end

---------------------------------------------------------------------------
-- Scanner
---------------------------------------------------------------------------

local scanAttempts = 0

local function ScanForBar()
    scanAttempts = scanAttempts + 1
    if not ElvUF_Player then
        if scanAttempts <= 5 then dbg("Attempt " .. scanAttempts .. ": ElvUF_Player nil") end
        return
    end
    local swing = ElvUF_Player.Swing
    if not swing then
        if scanAttempts <= 5 then dbg("Attempt " .. scanAttempts .. ": Swing nil") end
        return
    end
    local bar = swing.Twohand
    if not bar then
        if scanAttempts <= 5 then dbg("Attempt " .. scanAttempts .. ": Twohand nil") end
        return
    end
    dbg("Bar found: " .. tostring(bar:GetName()))
    InstallHook(bar)
end

local function ScanWithRetry()
    scanAttempts = 0
    for i = 0, 49 do
        ScheduleTimer(i * 0.2, ScanForBar)
    end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")

f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local arg1 = ...
        if arg1 == addonName then
            ElvUI_SealTwistDB = ElvUI_SealTwistDB or {}
            for k, v in pairs(DEFAULTS) do
                if ElvUI_SealTwistDB[k] == nil then
                    if type(v) == "table" then
                        ElvUI_SealTwistDB[k] = {}
                        for kk, vv in pairs(v) do
                            ElvUI_SealTwistDB[k][kk] = vv
                        end
                    else
                        ElvUI_SealTwistDB[k] = v
                    end
                end
            end
            db = ElvUI_SealTwistDB

            local E = unpack(ElvUI)
            local EP = E.Libs.EP
            if EP then
                EP:RegisterPlugin(addonName, function()
                    E.Options.args.sealTwist = {
                        order = 51,
                        type  = "group",
                        name  = "|cfff0a0d0Seal Twist|r",
                        args  = {
                            header = {
                                order = 1, type = "header",
                                name  = "|cfff0a0d0Seal Twist|r",
                            },
                            desc = {
                                order = 2, type = "description",
                                name  = "Judgment-CD based seal twisting.\n"
                                      .. "Primary seal active → Finisher seal (twist window) → Swing → Judgment → Primary seal.",
                            },
                            version = {
                                order = 3, type = "description",
                                name  = "|cfff0a0d0Version 1.1.0|r",
                            },
                            spacer = { order = 4, type = "description", name = "" },

                            -- Seals
                            sealGroup = {
                                order = 10, type = "group", name = "Seals", guiInline = true,
                                args = {
                                    primarySeal = {
                                        order = 1, type = "input",
                                        name  = "Primary Seal",
                                        desc  = "The seal active most of the time (e.g. Seal of Command).",
                                        get   = function() return db.primarySeal end,
                                        set   = function(_, v) db.primarySeal = strtrim(v) end,
                                    },
                                    finisherSeal = {
                                        order = 2, type = "input",
                                        name  = "Finisher Seal",
                                        desc  = "Cast during the twist window, right before the swing.\n"
                                              .. "Only suggested when Judgment is off cooldown.",
                                        get   = function() return db.finisherSeal end,
                                        set   = function(_, v) db.finisherSeal = strtrim(v) end,
                                    },
                                },
                            },

                            -- Timing
                            timingGroup = {
                                order = 20, type = "group", name = "Timing", guiInline = true,
                                args = {
                                    twistWindow = {
                                        order = 1, type = "range",
                                        name  = "Twist Window",
                                        desc  = "Seconds before the swing to cast the finisher seal.\n"
                                              .. "Seal lingers 0.5s — 0.4s is the safe default.\n"
                                              .. "0.6s adds reaction-time padding.",
                                        min = 0.30, max = 0.60, step = 0.05,
                                        get = function() return db.twistWindow end,
                                        set = function(_, v) db.twistWindow = v end,
                                    },
                                    judgementCD = {
                                        order = 2, type = "range",
                                        name  = "Judgment Ready Window",
                                        desc  = "Show the finisher seal when Judgment is within this many seconds of being ready.\n"
                                              .. "Set to 0 to only twist when Judgment is fully off cooldown.",
                                        min = 0, max = 3.0, step = 0.5,
                                        get = function() return db.judgementCD end,
                                        set = function(_, v) db.judgementCD = v end,
                                    },
                                },
                            },

                            -- Icon
                            iconGroup = {
                                order = 30, type = "group", name = "Icon", guiInline = true,
                                args = {
                                    iconSize = {
                                        order = 1, type = "range",
                                        name  = "Size",
                                        min = 16, max = 64, step = 2,
                                        get = function() return db.iconSize end,
                                        set = function(_, v) db.iconSize = v end,
                                    },
                                    iconPosition = {
                                        order = 2, type = "select",
                                        name  = "Position",
                                        values = {
                                            LEFT = "Left of bar",
                                            RIGHT = "Right of bar",
                                            TOP = "Above bar",
                                            BOTTOM = "Below bar",
                                        },
                                        get = function() return db.iconPosition end,
                                        set = function(_, v) db.iconPosition = v end,
                                    },
                                    iconXOffset = {
                                        order = 3, type = "range",
                                        name  = "X Offset",
                                        min = -50, max = 50, step = 1,
                                        get = function() return db.iconXOffset end,
                                        set = function(_, v) db.iconXOffset = v end,
                                    },
                                    iconYOffset = {
                                        order = 4, type = "range",
                                        name  = "Y Offset",
                                        min = -50, max = 50, step = 1,
                                        get = function() return db.iconYOffset end,
                                        set = function(_, v) db.iconYOffset = v end,
                                    },
                                },
                            },

                            -- Colours
                            colourGroup = {
                                order = 40, type = "group", name = "Colours", guiInline = true,
                                args = {
                                    barColor = {
                                        order = 1, type = "color",
                                        name  = "Twist Window Colour",
                                        desc  = "Colour of the bar overlay during the twist window.",
                                        hasAlpha = false,
                                        get = function() local c = db.barColor; return c.r, c.g, c.b end,
                                        set = function(_, r, g, b) db.barColor.r, db.barColor.g, db.barColor.b = r, g, b end,
                                    },
                                },
                            },

                            spacer3 = { order = 50, type = "description", name = "" },

                            restore = {
                                order = 60, type = "execute",
                                name  = "Restore Defaults",
                                func  = function()
                                    for k, v in pairs(DEFAULTS) do
                                        if type(v) == "table" then
                                            db[k] = {}
                                            for kk, vv in pairs(v) do db[k][kk] = vv end
                                        else
                                            db[k] = v
                                        end
                                    end
                                end,
                            },
                        },
                    }
                end)
            end
            dbg("Loaded")
        end

    elseif event == "PLAYER_LOGIN" then
        ScheduleTimer(1, function()
            ScanForBar()
            if not hookInstalled then
                dbg("Bar not found, retrying...")
                ScanWithRetry()
            end
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        hookInstalled = false
        hookedBar = nil
        overlay = nil
        iconFrame = nil
        activeSeal = nil
        phase = "idle"
        swingLanded = false
        ScheduleTimer(0.5, function()
            ScanForBar()
            if not hookInstalled then ScanWithRetry() end
        end)

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not db then return end
        -- 3.3.5: (timestamp, subEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
        --         destGUID, destName, destFlags, destRaidFlags, ...)
        local _, subEvent, _, sourceGUID, _, _, _, _, _, _, _, arg12, arg13 = ...
        if sourceGUID ~= UnitGUID("player") then return end

        if subEvent == "SPELL_CAST_SUCCESS" then
            local spellName = arg13
            if not spellName then return end

            -- Seal cast — update active seal
            if spellName == db.primarySeal then
                activeSeal = db.primarySeal
                dbg("Seal cast: " .. spellName)
            elseif spellName == db.finisherSeal then
                activeSeal = db.finisherSeal
                dbg("Seal cast: " .. spellName)
            end

            -- Judgment cast — transition to primary phase
            if spellName == "Judgement" then
                if phase == "judgement" then
                    phase = "primary"
                    dbg("Judgment cast → primary phase")
                end
            end
        end
    end
end)
