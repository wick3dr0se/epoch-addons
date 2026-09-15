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
    twistWindow      = 0.40,
    judgementCD      = 1.5,
    showPrediction   = true,
    predictionWindow = 0.60,
    barColor         = { r = 1.0, g = 0.2, b = 0.1 },
    judgementBarColor= { r = 1.0, g = 0.85, b = 0.0 },
    sealIconSize     = 32,
    sealIconPosition = "RIGHT",
    sealIconXOffset  = 8,
    sealIconYOffset  = 0,
    judIconSize      = 32,
    judIconPosition  = "RIGHT",
    judIconXOffset   = 8,
    judIconYOffset   = 0,
    primarySeal      = "Seal of Command",
    finisherSeal     = "Seal of Righteousness",
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local db
local sealOverlay       = nil   -- red overlay during twist window
local judOverlay        = nil   -- gold overlay during judgment window
local sealIconFrame     = nil   -- seal icon
local judIconFrame      = nil   -- judgment icon
local hookedBar         = nil
local hookInstalled     = false
local activeSeal        = nil
local judgementJustCast = false

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
    local start, duration = GetSpellCooldown("Judgement")
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

local function CreateOverlay(bar, name)
    local f = CreateFrame("Frame", nil, bar)
    f:SetFrameLevel(bar:GetFrameLevel() + 5)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints(bar)
    f.tex:SetTexture(1, 1, 1, 1)
    f.tex:SetBlendMode("ADD")
    f:Hide()
    return f
end

local function CreateIconFrame(bar, name)
    local f = CreateFrame("Frame", nil, bar)
    f:SetFrameLevel(bar:GetFrameLevel() + 10)
    f.texture = f:CreateTexture(nil, "OVERLAY")
    f.texture:SetAllPoints(f)
    f.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f:Hide()
    return f
end

local function PositionIcon(bar, icon, pos, xOff, yOff, sz)
    icon:ClearAllPoints()
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

local function ShowSealIcon(bar, tex)
    if not sealIconFrame or not tex then return end
    sealIconFrame:Show()
    sealIconFrame:SetAlpha(1.0)
    sealIconFrame.texture:SetTexture(tex)
    PositionIcon(bar, sealIconFrame, db.sealIconPosition, db.sealIconXOffset, db.sealIconYOffset, db.sealIconSize)
    local pulse = 1.0 + 0.15 * math.sin(GetTime() * 8)
    sealIconFrame:SetScale(pulse)
end

local function ShowSealIconDimmed(bar, tex)
    if not sealIconFrame or not tex then return end
    sealIconFrame:Show()
    sealIconFrame:SetAlpha(0.35)
    sealIconFrame.texture:SetTexture(tex)
    PositionIcon(bar, sealIconFrame, db.sealIconPosition, db.sealIconXOffset, db.sealIconYOffset, db.sealIconSize)
    sealIconFrame:SetScale(1.0)
end

local function ShowJudIcon(bar, tex, dimmed)
    if not judIconFrame or not tex then return end
    judIconFrame:Show()
    judIconFrame.texture:SetTexture(tex)
    PositionIcon(bar, judIconFrame, db.judIconPosition, db.judIconXOffset, db.judIconYOffset, db.judIconSize)
    if dimmed then
        judIconFrame:SetAlpha(0.4)
        judIconFrame:SetScale(1.0)
    else
        judIconFrame:SetAlpha(1.0)
        local pulse = 1.0 + 0.15 * math.sin(GetTime() * 8)
        judIconFrame:SetScale(pulse)
    end
end

local function HideAllIcons()
    if sealIconFrame then sealIconFrame:Hide() end
    if judIconFrame then judIconFrame:Hide() end
end

---------------------------------------------------------------------------
-- OnUpdate tick — the core logic
---------------------------------------------------------------------------

local function SwingTick(bar, elapsed)
    if not bar.min or not bar.max then return end
    local remaining = bar.max - GetTime()

    activeSeal = DetectActiveSeal()
    if not activeSeal and ns._cleuSeal then
        activeSeal = ns._cleuSeal
    end

    local inTwistWindow = remaining > 0 and remaining <= db.twistWindow
    local inPrediction = db.showPrediction and remaining > db.twistWindow and remaining <= (db.twistWindow + db.predictionWindow)
    local judReady = IsJudgementReady()

    -- Seal colour overlay (twist window)
    if inTwistWindow then
        sealOverlay:Show()
        sealOverlay.tex:ClearAllPoints()
        sealOverlay.tex:SetAllPoints(bar)
        local bc = db.barColor
        local intensity = 1 - (remaining / db.twistWindow)
        sealOverlay.tex:SetVertexColor(bc.r, bc.g, bc.b, 0.30 + 0.35 * intensity)
    else
        sealOverlay:Hide()
    end

    -- Judgment colour overlay (when finisher seal active + Judgment ready)
    local finisherActive = (activeSeal == db.finisherSeal)
    if finisherActive and judReady then
        judOverlay:Show()
        judOverlay.tex:ClearAllPoints()
        judOverlay.tex:SetAllPoints(bar)
        local bc = db.judgementBarColor
        judOverlay.tex:SetVertexColor(bc.r, bc.g, bc.b, 0.35 + 0.20 * math.sin(GetTime() * 6))
    else
        judOverlay:Hide()
    end

    -- Icon logic
    HideAllIcons()

    if judgementJustCast then
        -- After Judgment — suggest primary seal until it's active
        if activeSeal == db.primarySeal then
            judgementJustCast = false
        else
            ShowSealIcon(bar, GetSealIcon(db.primarySeal))
        end
    elseif not activeSeal then
        -- No seal active — suggest primary seal
        ShowSealIcon(bar, GetSealIcon(db.primarySeal))
    elseif inTwistWindow then
        -- Twist window
        if judReady or IsJudgementNearlyReady() then
            -- Judgment ready — suggest finisher seal
            local iconTex = GetSealIcon(db.finisherSeal)
            if iconTex then
                ShowSealIcon(bar, iconTex)
            else
                ShowJudIcon(bar, GetJudgementIcon(), false)
            end
        else
            -- Judgment on CD — show dimmed Judgment as "charging" indicator
            ShowJudIcon(bar, GetJudgementIcon(), true)
        end
    elseif inPrediction and activeSeal == db.primarySeal then
        -- Prediction window — show dimmed finisher seal as "get ready" indicator
        local iconTex = GetSealIcon(db.finisherSeal)
        if iconTex then
            ShowSealIconDimmed(bar, iconTex)
        end
    elseif finisherActive and judReady then
        -- Finisher seal active + Judgment ready — suggest Judgment
        ShowJudIcon(bar, GetJudgementIcon(), false)
    end
end

---------------------------------------------------------------------------
-- Persistent hook via SetScript wrapper
---------------------------------------------------------------------------

local function InstallHook(bar)
    if hookInstalled then return end
    hookInstalled = true
    hookedBar = bar

    sealOverlay = CreateOverlay(bar, "SealTwistSealOverlay")
    judOverlay = CreateOverlay(bar, "SealTwistJudOverlay")
    sealIconFrame = CreateIconFrame(bar, "SealTwistSealIcon")
    judIconFrame = CreateIconFrame(bar, "SealTwistJudIcon")
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
                                      .. "Primary seal → Finisher seal (twist) → Swing → Judgment → Primary seal.",
                            },
                            version = {
                                order = 3, type = "description",
                                name  = "|cfff0a0d0Version 1.3.0|r",
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
                                              .. "Seal lingers 0.5s — 0.4s is the safe default.",
                                        min = 0.30, max = 0.60, step = 0.05,
                                        get = function() return db.twistWindow end,
                                        set = function(_, v) db.twistWindow = v end,
                                    },
                                    judgementCD = {
                                        order = 2, type = "range",
                                        name  = "Judgment Ready Window",
                                        desc  = "Show the finisher seal when Judgment is within this many seconds of being ready.",
                                        min = 0, max = 3.0, step = 0.5,
                                        get = function() return db.judgementCD end,
                                        set = function(_, v) db.judgementCD = v end,
                                    },
                                    showPrediction = {
                                        order = 3, type = "toggle",
                                        name  = "Show Prediction",
                                        desc  = "Show a dimmed finisher seal icon before the twist window\n"
                                              .. "as a \"get ready\" indicator.",
                                        get = function() return db.showPrediction end,
                                        set = function(_, v) db.showPrediction = v end,
                                    },
                                    predictionWindow = {
                                        order = 4, type = "range",
                                        name  = "Prediction Window",
                                        desc  = "Seconds before the twist window to show the dimmed finisher icon.\n"
                                              .. "0.6s means the icon appears 0.6s before the twist window starts.",
                                        min = 0.20, max = 1.50, step = 0.10,
                                        get = function() return db.predictionWindow end,
                                        set = function(_, v) db.predictionWindow = v end,
                                    },
                                },
                            },

                            -- Seal Icon
                            sealIconGroup = {
                                order = 30, type = "group", name = "Seal Icon", guiInline = true,
                                args = {
                                    sealIconSize = {
                                        order = 1, type = "range",
                                        name  = "Size",
                                        min = 16, max = 64, step = 2,
                                        get = function() return db.sealIconSize end,
                                        set = function(_, v) db.sealIconSize = v end,
                                    },
                                    sealIconPosition = {
                                        order = 2, type = "select",
                                        name  = "Position",
                                        values = {
                                            LEFT = "Left of bar",
                                            RIGHT = "Right of bar",
                                            TOP = "Above bar",
                                            BOTTOM = "Below bar",
                                        },
                                        get = function() return db.sealIconPosition end,
                                        set = function(_, v) db.sealIconPosition = v end,
                                    },
                                    sealIconXOffset = {
                                        order = 3, type = "range",
                                        name  = "X Offset",
                                        min = -50, max = 50, step = 1,
                                        get = function() return db.sealIconXOffset end,
                                        set = function(_, v) db.sealIconXOffset = v end,
                                    },
                                    sealIconYOffset = {
                                        order = 4, type = "range",
                                        name  = "Y Offset",
                                        min = -50, max = 50, step = 1,
                                        get = function() return db.sealIconYOffset end,
                                        set = function(_, v) db.sealIconYOffset = v end,
                                    },
                                },
                            },

                            -- Judgment Icon
                            judIconGroup = {
                                order = 35, type = "group", name = "Judgment Icon", guiInline = true,
                                args = {
                                    judIconSize = {
                                        order = 1, type = "range",
                                        name  = "Size",
                                        min = 16, max = 64, step = 2,
                                        get = function() return db.judIconSize end,
                                        set = function(_, v) db.judIconSize = v end,
                                    },
                                    judIconPosition = {
                                        order = 2, type = "select",
                                        name  = "Position",
                                        values = {
                                            LEFT = "Left of bar",
                                            RIGHT = "Right of bar",
                                            TOP = "Above bar",
                                            BOTTOM = "Below bar",
                                        },
                                        get = function() return db.judIconPosition end,
                                        set = function(_, v) db.judIconPosition = v end,
                                    },
                                    judIconXOffset = {
                                        order = 3, type = "range",
                                        name  = "X Offset",
                                        min = -50, max = 50, step = 1,
                                        get = function() return db.judIconXOffset end,
                                        set = function(_, v) db.judIconXOffset = v end,
                                    },
                                    judIconYOffset = {
                                        order = 4, type = "range",
                                        name  = "Y Offset",
                                        min = -50, max = 50, step = 1,
                                        get = function() return db.judIconYOffset end,
                                        set = function(_, v) db.judIconYOffset = v end,
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
                                    judgementBarColor = {
                                        order = 2, type = "color",
                                        name  = "Judgment Window Colour",
                                        desc  = "Colour of the bar overlay when Judgment is ready and finisher seal is active.",
                                        hasAlpha = false,
                                        get = function() local c = db.judgementBarColor; return c.r, c.g, c.b end,
                                        set = function(_, r, g, b) db.judgementBarColor.r, db.judgementBarColor.g, db.judgementBarColor.b = r, g, b end,
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
        sealOverlay = nil
        judOverlay = nil
        sealIconFrame = nil
        judIconFrame = nil
        activeSeal = nil
        judgementJustCast = false
        ns._cleuSeal = nil
        ScheduleTimer(0.5, function()
            ScanForBar()
            if not hookInstalled then ScanWithRetry() end
        end)

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not db then return end
        local _, subEvent, _, sourceGUID, _, _, _, _, _, _, _, arg12, arg13 = ...
        if sourceGUID ~= UnitGUID("player") then return end

        if subEvent == "SPELL_CAST_SUCCESS" then
            local spellName = arg13
            if not spellName then return end

            if spellName == db.primarySeal then
                ns._cleuSeal = db.primarySeal
            elseif spellName == db.finisherSeal then
                ns._cleuSeal = db.finisherSeal
            end

            if spellName == "Judgement" then
                judgementJustCast = true
                dbg("Judgment cast → suggest primary seal")
            end
        end
    end
end)
