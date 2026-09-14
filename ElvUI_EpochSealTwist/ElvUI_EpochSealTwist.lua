--[[
    ElvUI Epoch Seal Twist — Paladin seal-twisting helper for Project Epoch
    Single icon + bar color change during the twist window on ElvUI_SwingBar.
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
    barColor        = { r = 1.0, g = 0.2,  b = 0.1 },   -- red during twist window
    iconSize        = 32,     -- next-seal icon size (pixels)
    iconPosition    = "RIGHT", -- icon position: LEFT, RIGHT, TOP, BOTTOM
    iconXOffset     = 8,      -- horizontal offset from bar edge
    iconYOffset     = 0,      -- vertical offset from bar edge
    sequence        = { "Seal of Command", "Seal of Righteousness" },
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local db
local currentSealIndex = 1
local overlay          = nil   -- bar color overlay frame
local iconFrame        = nil   -- the next-seal icon
local hookedBar        = nil
local hookInstalled    = false

---------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------
local DEBUG = false
local function dbg(msg)
    if DEBUG then print("|cfff0a0d0EpochSealTwist|r: " .. msg) end
end

---------------------------------------------------------------------------
-- Seal helpers
---------------------------------------------------------------------------

local function DetectActiveSeal()
    for i = 1, 40 do
        local name = UnitBuff("player", i)
        if not name then break end
        for j, sealName in ipairs(db.sequence) do
            if name == sealName then return j end
        end
    end
    return nil
end

-- Returns the name of the seal to suggest next
local function GetNextSeal()
    local idx = DetectActiveSeal()
    if idx then
        currentSealIndex = idx
        -- Active seal found — suggest the next one in sequence
        local nextIdx = (currentSealIndex % #db.sequence) + 1
        return db.sequence[nextIdx]
    else
        -- No seal active — suggest the first in sequence (default)
        return db.sequence[1]
    end
end

local function GetSealIcon(sealName)
    local _, _, icon = GetSpellInfo(sealName)
    return icon
end

---------------------------------------------------------------------------
-- UI creation
---------------------------------------------------------------------------

local function CreateOverlay(bar)
    -- Bar color overlay — sits on top of the bar fill
    local f = CreateFrame("Frame", nil, bar)
    f:SetFrameLevel(bar:GetFrameLevel() + 5)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints(bar)
    f.tex:SetTexture(1, 1, 1, 1)
    f.tex:SetBlendMode("ADD")
    f:Hide()

    -- Next-seal icon
    local icon = CreateFrame("Frame", nil, bar)
    icon:SetFrameLevel(bar:GetFrameLevel() + 10)
    icon.texture = icon:CreateTexture(nil, "OVERLAY")
    icon.texture:SetAllPoints(icon)
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- crop WoW icon border
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
-- Overlay update
---------------------------------------------------------------------------

local function UpdateOverlay(bar, remaining, total)
    if not overlay or not iconFrame or total <= 0 then return end

    local inTwist = remaining <= db.twistWindow and remaining > 0

    if not inTwist then
        overlay:Hide()
        iconFrame:Hide()
        return
    end

    -- Bar colour overlay
    overlay:Show()
    overlay.tex:ClearAllPoints()
    overlay.tex:SetAllPoints(bar)
    local intensity = 1 - (remaining / db.twistWindow)  -- 0→1 as swing approaches
    local bc = db.barColor
    overlay.tex:SetVertexColor(bc.r, bc.g, bc.b, 0.30 + 0.35 * intensity)

    -- Next-seal icon
    local nextSeal = GetNextSeal()
    local iconTex  = GetSealIcon(nextSeal)
    if iconTex then
        iconFrame:Show()
        iconFrame.texture:SetTexture(iconTex)
        PositionIcon(bar, iconFrame)
        local pulse = 1.0 + 0.15 * math.sin(GetTime() * 8)
        iconFrame:SetScale(pulse)
    else
        iconFrame:Hide()
    end
end

---------------------------------------------------------------------------
-- OnUpdate tick
---------------------------------------------------------------------------

local function SwingTick(bar, elapsed)
    if not bar.min or not bar.max then return end
    local remaining = bar.max - GetTime()
    UpdateOverlay(bar, remaining, bar.speed or 0)
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

f:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            EpochSealTwistDB = EpochSealTwistDB or {}
            for k, v in pairs(DEFAULTS) do
                if EpochSealTwistDB[k] == nil then
                    if type(v) == "table" then
                        EpochSealTwistDB[k] = {}
                        for kk, vv in pairs(v) do
                            EpochSealTwistDB[k][kk] = vv
                        end
                    else
                        EpochSealTwistDB[k] = v
                    end
                end
            end
            db = EpochSealTwistDB

            local E = unpack(ElvUI)
            local EP = E.Libs.EP
            if EP then
                EP:RegisterPlugin(addonName, function()
                    E.Options.args.epochSealTwist = {
                        order = 51,
                        type  = "group",
                        name  = "|cfff0a0d0Epoch Seal Twist|r",
                        args  = {
                            header = {
                                order = 1, type = "header",
                                name  = "|cfff0a0d0Epoch Seal Twist|r",
                            },
                            desc = {
                                order = 2, type = "description",
                                name  = "Swing bar overlay and next-seal icon.\n"
                                      .. "Highlights the twist window on your swing bar and shows\n"
                                      .. "which seal to cast next.",
                            },
                            version = {
                                order = 3, type = "description",
                                name  = "|cfff0a0d0Version 1.0.0|r",
                            },
                            spacer = { order = 4, type = "description", name = "" },

                            -- Timing
                            timingGroup = {
                                order = 10, type = "group", name = "Timing", guiInline = true,
                                args = {
                                    twistWindow = {
                                        order = 1, type = "range",
                                        name  = "Twist Window",
                                        desc  = "Seconds before the swing to show icon + bar colour.\n"
                                              .. "Seal lingers 0.5s — 0.4s is the safe default.\n"
                                              .. "0.6s adds reaction-time padding (you won't cast instantly).",
                                        min = 0.30, max = 0.60, step = 0.05,
                                        get = function() return db.twistWindow end,
                                        set = function(_, v) db.twistWindow = v end,
                                    },
                                },
                            },

                            -- Seal sequence
                            sequence = {
                                order = 20, type = "input",
                                name  = "Seal Sequence",
                                desc  = "Comma-separated seal names.\nDefault: Seal of Command,Seal of Righteousness",
                                get   = function() return table.concat(db.sequence, ",") end,
                                set   = function(_, v)
                                    db.sequence = {}
                                    for word in gmatch(v, "[^,]+") do
                                        tinsert(db.sequence, strtrim(word))
                                    end
                                    currentSealIndex = 1
                                end,
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
                                        desc  = "Colour of the bar overlay and icon pulse during the twist window.",
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
                                    currentSealIndex = 1
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
        ScheduleTimer(0.5, function()
            ScanForBar()
            if not hookInstalled then ScanWithRetry() end
        end)

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not db then return end
        -- 3.3.5: (timestamp, subEvent, hideCaster, sourceGUID, ...)
        if arg2 ~= "SPELL_CAST_SUCCESS" then return end
        if arg4 ~= UnitGUID("player") then return end
        local spellName = arg13
        if not spellName then return end
        for j, sealName in ipairs(db.sequence) do
            if spellName == sealName then
                currentSealIndex = j
                break
            end
        end
    end
end)
