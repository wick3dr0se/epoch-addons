--[[
    pfQuest / wizard.lua  (ElvUI rewrite)

    First-run window: pick a marker mode and whether the arrow shows. The old
    one lived at the bottom of config.lua, built a Blizzard checkbox and left its
    mode cards on GameFontWhite. This is the window: ElvUI backdrop, ElvUI font,
    a flat check box, and the chosen card marked with the accent border instead
    of "the other two are grey".

    Shows once: it sets pfQuest_config["welcome"] = "1" on save or dismiss.
]]

local addonName, ns = ...

local CARD_WIDTH, CARD_HEIGHT = 120, 160

local modes = {
  { caption = "Simple Markers", texture = "\\img\\init\\simple",
    tooltip = "Only show cluster icons with summarized objective locations",
    spawn = "0", cluster = "1", spawnmini = "0", clustermini = "1" },
  { caption = "Combined", texture = "\\img\\init\\combined",
    tooltip = "Show cluster icons and every spawn point",
    spawn = "1", cluster = "1", spawnmini = "1", clustermini = "0" },
  { caption = "Spawn Points", texture = "\\img\\init\\spawns",
    tooltip = "Show every spawn point and hide cluster icons",
    spawn = "1", cluster = "0", spawnmini = "1", clustermini = "0" },
}

local wizard = CreateFrame("Frame", "pfQuestInit", UIParent)
pfQuestInit = wizard
wizard:Hide()
wizard:SetSize(400, 270)
wizard:SetPoint("CENTER")
wizard:SetFrameStrata("FULLSCREEN_DIALOG")
wizard:EnableMouse(true)
wizard:SetMovable(true)
wizard:RegisterForDrag("LeftButton")
wizard:SetScript("OnDragStart", function(self) self:StartMoving() end)
wizard:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

pfq.CreateBackdrop(wizard)
tinsert(UISpecialFrames, "pfQuestInit")

wizard.title = wizard:CreateFontString(nil, "OVERLAY")
pfq.Font(wizard.title, pfq.fontSize + 1)
wizard.title:SetPoint("TOP", 0, -12)
wizard.title:SetText("Select your |cff33ffccpf|cffffffffQuest|r mode")

local selected = 2

local function paintCards()
  local r, g, b = pfq.accent()
  for i, card in ipairs(wizard.cards) do
    if i == selected then
      card:SetBackdropBorderColor(r, g, b, 1)
    else
      pfq.paint(card)
    end
  end
end

wizard.cards = {}
for i, mode in ipairs(modes) do
  local card = CreateFrame("Button", nil, wizard)
  card:SetSize(CARD_WIDTH, CARD_HEIGHT)
  card:SetPoint("TOP", wizard, "TOP", (i - 2) * (CARD_WIDTH + 10), -40)

  card.art = card:CreateTexture(nil, "ARTWORK")
  card.art:SetAllPoints()
  card.art:SetTexture(pfQuestConfig.path .. mode.texture)

  pfq.SkinButton(card)

  card.caption = wizard:CreateFontString(nil, "OVERLAY")
  pfq.Font(card.caption, pfq.fontSize)
  card.caption:SetPoint("TOP", card, "BOTTOM", 0, -4)
  card.caption:SetText(mode.caption)

  card:SetScript("OnClick", function()
    selected = i
    paintCards()
  end)
  card:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(mode.caption, 1, 1, 1)
    GameTooltip:AddLine(mode.tooltip, 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  card:HookScript("OnLeave", function() GameTooltip:Hide() end)

  wizard.cards[i] = card
end

-- flat accent check box instead of UICheckButtonTemplate's art
local arrowBox = CreateFrame("CheckButton", nil, wizard)
arrowBox:SetSize(18, 18)
arrowBox:SetPoint("BOTTOMLEFT", 14, 14)
pfq.CreateBackdrop(arrowBox)

arrowBox.fill = arrowBox:CreateTexture(nil, "ARTWORK")
arrowBox.fill:SetPoint("TOPLEFT", 3, -3)
arrowBox.fill:SetPoint("BOTTOMRIGHT", -3, 3)
arrowBox.fill:SetTexture(pfq.blankTex())
arrowBox.fill:SetAlpha(0)
arrowBox:SetScript("OnClick", function(self)
  if self:GetChecked() then
    self.fill:SetAlpha(1)
  else
    self.fill:SetAlpha(0)
  end
end)

local arrowLabel = wizard:CreateFontString(nil, "OVERLAY")
pfq.Font(arrowLabel, pfq.fontSize)
arrowLabel:SetPoint("LEFT", arrowBox, "RIGHT", 6, 0)
arrowLabel:SetText("Show navigation arrow")

local save = CreateFrame("Button", nil, wizard)
save:SetSize(110, 22)
save:SetPoint("BOTTOMRIGHT", -14, 12)
pfq.SkinButton(save)
save.label = save:GetFontString()
save.label:SetText("Save & Close")

save:SetScript("OnClick", function()
  local mode = modes[selected]
  pfQuest_config["showspawn"] = mode.spawn
  pfQuest_config["showcluster"] = mode.cluster
  pfQuest_config["showspawnmini"] = mode.spawnmini
  pfQuest_config["showclustermini"] = mode.clustermini
  pfQuest_config["arrow"] = arrowBox:GetChecked() and "1" or "0"
  pfQuest_config["welcome"] = "1"

  pfQuest:ResetAll()
  wizard:Hide()
end)

wizard.close = CreateFrame("Button", nil, wizard)
wizard.close:SetSize(20, 20)
wizard.close:SetPoint("TOPRIGHT", -6, -6)
pfq.SkinButton(wizard.close)
wizard.close.label = wizard.close:GetFontString()
wizard.close.label:SetText("x")
wizard.close:SetScript("OnClick", function()
  pfQuest_config["welcome"] = "1"
  wizard:Hide()
end)

---------------------------------------------------------------------------
-- show once
---------------------------------------------------------------------------

local function refresh()
  -- preselect whatever the character is already configured with
  if pfQuest_config["showspawn"] == "0" and pfQuest_config["showcluster"] == "1" then
    selected = 1
  elseif pfQuest_config["showspawn"] == "1" and pfQuest_config["showcluster"] == "0" then
    selected = 3
  else
    selected = 2
  end

  if pfQuest_config["arrow"] == "0" then
    arrowBox:SetChecked(nil)
    arrowBox.fill:SetAlpha(0)
  else
    arrowBox:SetChecked(1)
    arrowBox.fill:SetAlpha(1)
  end

  local r, g, b = pfq.accent()
  arrowBox.fill:SetVertexColor(r, g, b, 1)
  paintCards()
end

local startup = CreateFrame("Frame")
startup:RegisterEvent("PLAYER_ENTERING_WORLD")
startup:SetScript("OnEvent", function(self)
  if pfQuest_config["welcome"] ~= "1" then
    refresh()
    wizard:Show()
  end
  self:UnregisterAllEvents()
end)
