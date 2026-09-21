--[[
    ElvUI Damage Meter -- Minimal damage meter for Project Epoch
    Toggle via /dm or the button in the right chat panel.
]]

local addonName, ns = ...

---------------------------------------------------------------------------
-- ElvUI ref
---------------------------------------------------------------------------
local E


---------------------------------------------------------------------------
-- Defaults
---------------------------------------------------------------------------
local DEFAULTS = {
    rowHeight     = 18,
    showDPS       = true,
    showHits      = true,
    sortBy        = "damage",
    color         = { r = 0.85, g = 0.25, b = 0.25 },
    backdropColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.8 },
    autoHide      = true,
    autoHideDelay = 5,
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local db
local combatData = {}
local fightDamage = 0
local fightStart  = 0
local inCombat    = false
local ui          = nil
local toggleBtn   = nil
local hideTimer   = 0

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

local function ResetData()
    combatData = {}
    fightDamage = 0
    fightStart = 0
end

local function AddDamage(spellName, spellID, amount)
    if not spellName or not amount or amount <= 0 then return end
    if not combatData[spellName] then
        combatData[spellName] = { damage = 0, hits = 0, spellID = spellID }
    end
    local d = combatData[spellName]
    d.damage = d.damage + amount
    d.hits = d.hits + 1
    d.spellID = d.spellID or spellID
    fightDamage = fightDamage + amount
    if fightStart == 0 then fightStart = GetTime() end
end

local function GetFightDuration()
    if fightStart == 0 then return 0 end
    return GetTime() - fightStart
end

local function Fmt(n)
    if n >= 1000000 then return string.format("%.1fM", n / 1000000)
    elseif n >= 1000 then return string.format("%.1fK", n / 1000)
    else return tostring(math.floor(n)) end
end

---------------------------------------------------------------------------
-- CLEU
---------------------------------------------------------------------------

local function HandleCLEU(...)
    if not db then return end
    local playerGUID = UnitGUID("player")
    if not playerGUID then return end

    local subEvent = select(2, ...)
    local sourceGUID = select(3, ...)

    if sourceGUID ~= playerGUID then return end

    if subEvent == "SPELL_DAMAGE" or subEvent == "SPELL_PERIODIC_DAMAGE" then
        local spellID = select(9, ...)
        local spellName = select(10, ...)
        local amount = select(12, ...)
        if spellName and amount then
            AddDamage(spellName, spellID, amount)
        end
    elseif subEvent == "SWING_DAMAGE" then
        local amount = select(9, ...)
        if amount and amount > 0 then
            AddDamage("Melee", nil, amount)
        end
    end
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------

local function GetSortedData()
    local t = {}
    for name, d in pairs(combatData) do
        local dur = GetFightDuration()
        t[#t + 1] = {
            name = name, damage = d.damage, hits = d.hits,
            dps = dur > 0 and d.damage / dur or 0, spellID = d.spellID,
        }
    end
    if db.sortBy == "dps" then
        table.sort(t, function(a, b) return a.dps > b.dps end)
    else
        table.sort(t, function(a, b) return a.damage > b.damage end)
    end
    return t
end

local function GetSpellIcon(name, spellID)
    if name == "Melee" then local _, _, icon = GetSpellInfo(6603); return icon or "Interface\\Icons\\INV_Sword_04" end
    if spellID then
        local _, _, icon = GetSpellInfo(spellID)
        if icon then return icon end
    end
    if name and type(name) == "string" then
        local _, _, icon = GetSpellInfo(name)
        if icon then return icon end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function GetSpellColor(name)
    if not name then return 0.6, 0.6, 0.6 end
    if name == "Melee" then return 1, 1, 1 end
    local _, _, _, _, _, _, _, _, _, _, school = GetSpellInfo(name)
    if not school then return 0.6, 0.6, 0.6 end
    if bit.band(school, 0x04) > 0 then return 1, 0.5, 0.25 end
    if bit.band(school, 0x02) > 0 then return 0.33, 0.6, 1 end
    if bit.band(school, 0x08) > 0 then return 0.15, 0.75, 0.15 end
    if bit.band(school, 0x20) > 0 then return 0.65, 0.15, 0.95 end
    if bit.band(school, 0x40) > 0 then return 1, 1, 0.5 end
    return 0.6, 0.6, 0.6
end

local function CreateRow(parent, index)
    local rh = db.rowHeight
    local font = E.media.normFont

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(rh)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * rh)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(index - 1) * rh)

    -- Row bg
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetTexture(E.media.blankTex)
    local br, bg, bb, ba = db.backdropColor.r, db.backdropColor.g, db.backdropColor.b, db.backdropColor.a
    row.bg:SetVertexColor(br, bg, bb, index % 2 == 0 and ba * 0.6 or ba * 0.4)

    -- Icon (20x20)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Status bar (right of icon, not covering it)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 2, -1)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -150, 1)
    row.bar:SetStatusBarTexture(E.media.normTex)
    row.bar:SetMinMaxValues(0, 1)
    row.bar:SetValue(0)

    row.barBg = row.bar:CreateTexture(nil, "BACKGROUND")
    row.barBg:SetAllPoints(row.bar)
    row.barBg:SetTexture(E.media.blankTex)
    row.barBg:SetVertexColor(0, 0, 0, 0.3)

    -- Text (OVERLAY = above everything)
    row.nameText = row:CreateFontString(nil, "OVERLAY")
    row.nameText:SetFont(font, 10)
    row.nameText:SetTextColor(0.85, 0.85, 0.85)
    row.nameText:SetPoint("LEFT", row.bar, "LEFT", 4, 0)
    row.nameText:SetPoint("RIGHT", row.bar, "RIGHT", -4, 0)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row.dmgText = row:CreateFontString(nil, "OVERLAY")
    row.dmgText:SetFont(font, 10)
    row.dmgText:SetTextColor(1, 1, 1)
    row.dmgText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.dmgText:SetWidth(55)
    row.dmgText:SetJustifyH("RIGHT")

    row.dpsText = row:CreateFontString(nil, "OVERLAY")
    row.dpsText:SetFont(font, 9)
    row.dpsText:SetTextColor(0.5, 0.7, 1.0)
    row.dpsText:SetPoint("RIGHT", row.dmgText, "LEFT", -4, 0)
    row.dpsText:SetWidth(50)
    row.dpsText:SetJustifyH("RIGHT")

    row.hitsText = row:CreateFontString(nil, "OVERLAY")
    row.hitsText:SetFont(font, 9)
    row.hitsText:SetTextColor(0.6, 0.6, 0.6)
    row.hitsText:SetPoint("RIGHT", row.dpsText, "LEFT", -2, 0)
    row.hitsText:SetWidth(35)
    row.hitsText:SetJustifyH("RIGHT")

    row.pctText = row:CreateFontString(nil, "OVERLAY")
    row.pctText:SetFont(font, 9)
    row.pctText:SetTextColor(0.5, 0.5, 0.5)
    row.pctText:SetPoint("RIGHT", row.hitsText, "LEFT", -2, 0)
    row.pctText:SetWidth(35)
    row.pctText:SetJustifyH("RIGHT")

    return row
end

local function UpdateUI()
    if not ui or not ui:IsShown() then return end

    local sorted = GetSortedData()
    local maxDmg = sorted[1] and sorted[1].damage or 1
    local dur = GetFightDuration()

    ui.titleText:SetText("Damage Meter")
    local s = Fmt(fightDamage) .. " total"
    if dur > 0 then s = s .. "  |  " .. Fmt(fightDamage / dur) .. "/s" end
    s = s .. "  |  " .. string.format("%.1fs", dur)
    ui.summaryText:SetText(s)

    local panelHeight = ui:GetHeight() or 200
    local visibleRows = math.min(#sorted, math.floor((panelHeight - 46) / db.rowHeight))

    for i = 1, visibleRows do
        local data = sorted[i]
        local row = ui.rows[i]
        if not row then
            row = CreateRow(ui.scrollChild, i)
            ui.rows[i] = row
        end
        row:Show()

        row.icon:SetTexture(GetSpellIcon(data.name, data.spellID))

        local nameStr = tostring(data.name)
        if #nameStr > 20 then nameStr = string.sub(nameStr, 1, 18) .. ".." end
        row.nameText:SetText(nameStr)

        local r, g, b = GetSpellColor(data.name)
        row.bar:SetStatusBarColor(r, g, b, 0.5)
        row.bar:SetValue(data.damage / maxDmg)

        row.dmgText:SetText(Fmt(data.damage))

        if db.showDPS then
            row.dpsText:SetText(Fmt(data.dps) .. "/s")
            row.dpsText:Show()
        else
            row.dpsText:Hide()
        end

        if db.showHits then
            row.hitsText:SetText(data.hits .. "x")
            row.hitsText:Show()
        else
            row.hitsText:Hide()
        end

        if fightDamage > 0 then
            row.pctText:SetText(string.format("%.0f%%", data.damage / fightDamage * 100))
        else
            row.pctText:SetText("0%")
        end
    end

    for i = visibleRows + 1, #ui.rows do
        ui.rows[i]:Hide()
    end

    if ui.scrollChild then
        ui.scrollChild:SetSize(ui:GetWidth() or 250, visibleRows * db.rowHeight)
    end
end

---------------------------------------------------------------------------
-- UI creation
---------------------------------------------------------------------------

local function BuildContent(parent)
    local f = CreateFrame("Frame", "ElvUI_DamageMeter", parent)
    f:SetAllPoints(parent)
    f:SetFrameStrata("HIGH")

    f:CreateBackdrop("Default")
    f.backdrop:SetBackdropColor(db.backdropColor.r, db.backdropColor.g, db.backdropColor.b, db.backdropColor.a)

    f.titleBar = CreateFrame("Frame", nil, f)
    f.titleBar:SetHeight(20)
    f.titleBar:SetPoint("TOPLEFT", f.backdrop, "TOPLEFT", E.Border, -E.Border)
    f.titleBar:SetPoint("TOPRIGHT", f.backdrop, "TOPRIGHT", -E.Border, -E.Border)
    f.titleBar:EnableMouse(true)

    f.titleBar.bg = f.titleBar:CreateTexture(nil, "BACKGROUND")
    f.titleBar.bg:SetAllPoints(f.titleBar)
    f.titleBar.bg:SetTexture(E.media.blankTex)
    local br, bg, bb, ba = db.backdropColor.r, db.backdropColor.g, db.backdropColor.b, db.backdropColor.a
    f.titleBar.bg:SetVertexColor(br * 1.5, bg * 1.5, bb * 1.5, ba * 1.5)

    f.titleText = f.titleBar:CreateFontString(nil, "OVERLAY")
    f.titleText:SetFont(E.media.normFont, 10)
    f.titleText:SetTextColor(1, 1, 1)
    f.titleText:SetPoint("LEFT", f.titleBar, "LEFT", 4, 0)

    f.summaryText = f.titleBar:CreateFontString(nil, "OVERLAY")
    f.summaryText:SetFont(E.media.normFont, 9)
    f.summaryText:SetTextColor(0.8, 0.8, 0.8)
    f.summaryText:SetPoint("RIGHT", f.titleBar, "RIGHT", -22, 0)

    f.closeBtn = CreateFrame("Button", nil, f.titleBar)
    f.closeBtn:SetSize(16, 16)
    f.closeBtn:SetPoint("RIGHT", f.titleBar, "RIGHT", -2, 0)
    f.closeBtn:SetScript("OnClick", function() ResetData(); UpdateUI() end)
    f.closeBtn.text = f.closeBtn:CreateFontString(nil, "OVERLAY")
    f.closeBtn.text:SetFont(E.media.normFont, 11, "OUTLINE")
    f.closeBtn.text:SetText("X")
    f.closeBtn.text:SetPoint("CENTER")
    f.closeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Reset data")
        GameTooltip:Show()
    end)
    f.closeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.scroll = CreateFrame("ScrollFrame", nil, f)
    f.scroll:SetPoint("TOPLEFT", f.titleBar, "BOTTOMLEFT", 0, -1)
    f.scroll:SetPoint("BOTTOMRIGHT", f.backdrop, "BOTTOMRIGHT", -E.Border, E.Border)

    f.scrollChild = CreateFrame("Frame", nil, f.scroll)
    f.scrollChild:SetSize(1, 1)
    f.scroll:SetScrollChild(f.scrollChild)

    f.rows = {}
    f:Hide()
    ui = f
    return f
end

local function CreateUI()
    if ui then return ui end
    if not RightChatPanel then return nil end

    ui = BuildContent(RightChatPanel)
    return ui
end

local function ToggleMeter()
    if not ui then CreateUI() end
    if not ui then return end
    if db.autoHide then return end  -- Combat Tracking controls the meter

    if ui:IsShown() then
        ui:Hide()
    else
        ui:Show()
        UpdateUI()
    end
    if toggleBtn then
        toggleBtn:SetAlpha(ui:IsShown() and 1 or 0.5)
    end
end

local function CreateToggleButton()
    if toggleBtn then return end
    if not RightChatDataPanel then return end

    local btn = CreateFrame("Button", "ElvUI_DamageMeterToggle", RightChatDataPanel)
    btn:SetSize(24, 24)
    btn:SetPoint("BOTTOMLEFT", RightChatPanel, "BOTTOMLEFT", -30, 4)
    btn:SetFrameStrata("HIGH")

    btn.icon = btn:CreateTexture(nil, "OVERLAY")
    btn.icon:SetAllPoints()
    btn.icon:SetTexture("Interface\\Icons\\Ability_Warrior_Innerrage")
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn:SetScript("OnClick", function() ToggleMeter() end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Toggle Damage Meter")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetAlpha(0.5)
    toggleBtn = btn
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")

f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        ElvUI_DamageMeterDB = ElvUI_DamageMeterDB or {}
        for k, v in pairs(DEFAULTS) do
            if ElvUI_DamageMeterDB[k] == nil then
                if type(v) == "table" then
                    ElvUI_DamageMeterDB[k] = {}
                    for kk, vv in pairs(v) do ElvUI_DamageMeterDB[k][kk] = vv end
                else
                    ElvUI_DamageMeterDB[k] = v
                end
            end
        end
        db = ElvUI_DamageMeterDB

        E = unpack(ElvUI)

        -- CLEU
        local cleuFrame = CreateFrame("Frame")
        cleuFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        cleuFrame:SetScript("OnEvent", function(_, ev, ...)
            if ev == "COMBAT_LOG_EVENT_UNFILTERED" then HandleCLEU(...) end
        end)

        -- Combat tracking
        local cf = CreateFrame("Frame")
        cf:RegisterEvent("PLAYER_REGEN_ENABLED")
        cf:RegisterEvent("PLAYER_REGEN_DISABLED")
        cf:RegisterEvent("PLAYER_ENTERING_WORLD")
        cf:SetScript("OnEvent", function(_, ev)
            if ev == "PLAYER_REGEN_DISABLED" then
                inCombat = true
                hideTimer = 0
                if db.autoHide and ui then
                    ui:Show()
                    UpdateUI()
                end
                if fightStart == 0 then ResetData(); fightStart = GetTime() end
            elseif ev == "PLAYER_REGEN_ENABLED" then
                inCombat = false
                if ui and ui:IsShown() then UpdateUI() end
                if db.autoHide and ui and ui:IsShown() then
                    hideTimer = db.autoHideDelay
                end
            elseif ev == "PLAYER_ENTERING_WORLD" then
                ResetData()
                hideTimer = 0
            end
        end)

        -- OnUpdate: refresh combat data + auto-hide timer
        CreateFrame("Frame"):SetScript("OnUpdate", function(_, elapsed)
            if inCombat and ui and ui:IsShown() then UpdateUI() end
            if db.autoHide and not inCombat and hideTimer > 0 and ui and ui:IsShown() then
                hideTimer = hideTimer - elapsed
                if hideTimer <= 0 then
                    ui:Hide()
                    hideTimer = 0
                end
            end
        end)

        -- Create UI and toggle button after a delay
        CreateFrame("Frame"):SetScript("OnUpdate", function(self)
            if RightChatPanel and RightChatPanel:GetWidth() > 0 then
                self:SetScript("OnUpdate", nil)
                CreateUI()
                if not db.autoHide then CreateToggleButton() end
                UpdateUI()
            end
        end)

        -- ElvUI plugin
        local EP = E.Libs.EP
        if EP then
            EP:RegisterPlugin(addonName, function()
                E.Options.args.damageMeter = {
                    order = 52, type = "group",
                    name = "|cffd94545Damage Meter|r",
                    args = {
                        header = { order = 1, type = "header", name = "|cffd94545Damage Meter|r" },
                        desc = { order = 2, type = "description",
                            name = "Minimal damage meter.\\nTracks damage per spell with DPS, hit count, and averages." },
                        version = { order = 3, type = "description", name = "|cffd94545Version 1.2.0|r" },
                        spacer = { order = 4, type = "description", name = "" },

                        rowHeight = {
                            order = 12, type = "range", name = "Row Height",
                            min = 14, max = 28, step = 1,
                            get = function() return db.rowHeight end,
                            set = function(_, v) db.rowHeight = v; if ui then UpdateUI() end end,
                        },
                        spacer2 = { order = 13, type = "description", name = "" },

                        backdropColor = {
                            order = 21, type = "color", name = "Backdrop Color",
                            hasAlpha = true,
                            get = function() local c = db.backdropColor; return c.r, c.g, c.b, c.a end,
                            set = function(_, r, g, b, a) db.backdropColor.r, db.backdropColor.g, db.backdropColor.b, db.backdropColor.a = r, g, b, a end,
                        },
                        spacer3 = { order = 22, type = "description", name = "" },

                        showDPS = {
                            order = 30, type = "toggle", name = "Show DPS",
                            get = function() return db.showDPS end,
                            set = function(_, v) db.showDPS = v end,
                        },
                        showHits = {
                            order = 31, type = "toggle", name = "Show Hits",
                            get = function() return db.showHits end,
                            set = function(_, v) db.showHits = v end,
                        },
                        sortBy = {
                            order = 32, type = "select", name = "Sort By",
                            values = { damage = "Total Damage", dps = "DPS" },
                            get = function() return db.sortBy end,
                            set = function(_, v) db.sortBy = v end,
                        },
                        spacer4 = { order = 33, type = "description", name = "" },

                        autoHide = {
                            order = 40, type = "toggle", name = "Combat Tracking",
                            desc = "Show meter during combat, hide after leaving combat.\nShows again when entering combat.",
                            get = function() return db.autoHide end,
                            set = function(_, v)
                                db.autoHide = v
                                hideTimer = 0
                                if v then
                                    if toggleBtn then toggleBtn:Hide() end
                                    if ui then ui:Hide() end
                                else
                                    if not toggleBtn then CreateToggleButton() end
                                    if toggleBtn then toggleBtn:Show(); toggleBtn:SetAlpha(0.5) end
                                    if ui then ui:Show(); UpdateUI() end
                                end
                            end,
                        },
                        autoHideDelay = {
                            order = 41, type = "range",
                            name  = "Hide Delay",
                            desc  = "Seconds after leaving combat before hiding.",
                            min = 5, max = 60, step = 5,
                            get = function() return db.autoHideDelay end,
                            set = function(_, v) db.autoHideDelay = v end,
                        },
                        restore = { order = 60, type = "execute", name = "Restore Defaults",
                            func = function()
                                for k, v in pairs(DEFAULTS) do
                                    if type(v) == "table" then
                                        db[k] = {}
                                        for kk, vv in pairs(v) do db[k][kk] = vv end
                                    else
                                        db[k] = v
                                    end
                                end
                                if ui then UpdateUI() end
                            end },
                    } }
            end)
        end

        SLASH_DM1 = "/dm"
        SlashCmdList["DM"] = function() ToggleMeter() end

    end
end)
