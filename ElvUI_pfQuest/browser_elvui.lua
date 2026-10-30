--[[
    pfQuest / browser_elvui.lua  (ElvUI rewrite of browser.lua)

    Replaces pfQuest's database browser. The old file built a window, four tab
    frames with their own scrollframes, its own result buttons and its own
    scroll sliders, and a skin addon then restyled all of it. This is the whole
    browser: ElvUI backdrop, ElvUI scroll frame, ElvUI buttons.

    Contract kept, because other files use it:

      pfBrowser:Show() / :Hide()          native frame methods, OnShow does the work
      pfBrowser.input                     search box (slash commands set text,
                                          pfQuest-epoch hooks OnTextChanged)
      pfBrowser.tabs[type].buttons        result buttons (epoch rebinds tooltips)
      pfBrowser.tabs[type].button         the tab button
      pfBrowser_fav[type][id] = name      favourites, unchanged saved variable

    Behaviour kept: four types, live search from three characters, favourites
    listed when the box is empty, `custom:` passthrough, click to pin on the map,
    shift-click quest links, item links through SetItemRef, favourite stars.

    Dropped on purpose: the per-item drop/vendor/reference sub-buttons and the
    alliance/horde icons on every row. Four extra buttons and two textures per
    row for information the tooltip already carries, and the reason the old list
    was expensive to build.
]]

local addonName, ns = ...

local SEARCH_LIMIT = 100
local ROW_HEIGHT = 20
local TYPES = {
  { key = "quests", caption = "Quests" },
  { key = "units", caption = "Units" },
  { key = "objects", caption = "Objects" },
  { key = "items", caption = "Items" },
}

local browser = CreateFrame("Frame", "pfQuestBrowser", UIParent)
pfBrowser = browser
browser:Hide()
browser:SetSize(560, 420)
browser:SetPoint("CENTER")
browser:SetFrameStrata("FULLSCREEN_DIALOG")
browser:SetClampedToScreen(true)
browser:EnableMouse(true)
browser.tabs = {}
browser.active = "quests"

pfq.CreateBackdrop(browser)
tinsert(UISpecialFrames, "pfQuestBrowser")

browser.title = browser:CreateFontString(nil, "OVERLAY")
pfq.Font(browser.title, pfq.fontSize + 2)
browser.title:SetPoint("TOPLEFT", 10, -8)
browser.title:SetText("|cff33ffccpf|cffffffffQuest|r |cffaaaaaa" .. (pfQuest_Loc["Database"] or "Database") .. "|r")

---------------------------------------------------------------------------
-- chrome
---------------------------------------------------------------------------

local function makeButton(text, width, parent, onClick)
  local b = CreateFrame("Button", nil, parent or browser)
  b:SetSize(width, 20)
  pfq.SkinButton(b)

  local label = b:GetFontString()
  if label then
    label:SetText(text)
    label:SetJustifyH("CENTER")
  end

  b:SetScript("OnClick", onClick)
  return b
end

browser.close = makeButton("x", 20, browser, function() browser:Hide() end)
browser.close:SetPoint("TOPRIGHT", -8, -8)

browser.clean = makeButton((pfQuest_Loc["Clean"] or "Clean"), 70, browser, function()
  pfMap:DeleteNode("PFDB")
  pfMap:UpdateNodes()
  if browser.input then browser.input:SetText("") end
end)
browser.clean:SetPoint("TOPRIGHT", browser.close, "TOPLEFT", -4, 0)

browser.journal = makeButton((pfQuest_Loc["Journal"] or "Journal"), 70, browser, function()
  if pfJournal then pfJournal:Show() end
end)
browser.journal:SetPoint("TOPRIGHT", browser.clean, "TOPLEFT", -4, 0)

browser.input = CreateFrame("EditBox", "pfQuestBrowserSearch", browser)
browser.input:SetHeight(20)
browser.input:SetPoint("TOPLEFT", 10, -34)
browser.input:SetPoint("TOPRIGHT", -10, -34)
browser.input:SetAutoFocus(false)
browser.input:SetTextInsets(6, 6, 0, 0)
pfq.Font(browser.input, pfq.fontSize)
pfq.CreateBackdrop(browser.input)

browser.input.hint = browser.input:CreateFontString(nil, "OVERLAY")
pfq.Font(browser.input.hint, pfq.fontSize)
browser.input.hint:SetPoint("LEFT", 6, 0)
browser.input.hint:SetTextColor(0.5, 0.5, 0.5)
browser.input.hint:SetText((pfQuest_Loc["Search"] or "Search"))

---------------------------------------------------------------------------
-- result rows
---------------------------------------------------------------------------

local function qualityColor(id)
  local _, _, quality = GetItemInfo(id)
  local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
  if not c then return "|cffffffff" end
  return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

local function rowEnter(row)
  local id, kind = row.id, row.btype
  if not id or not kind then return end

  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")

  if kind == "items" then
    GameTooltip:SetHyperlink("item:" .. id .. pfQuestCompat.itemsuffix)
    GameTooltip:Show()
    return
  end

  if pfDatabase.ShowExtendedTooltip then
    local ok = pcall(pfDatabase.ShowExtendedTooltip, pfDatabase, id, GameTooltip, row, "ANCHOR_RIGHT", -10, -5)
    if not ok then
      GameTooltip:SetText(row.name or tostring(id), 1, 1, 1)
      GameTooltip:Show()
    end
  else
    GameTooltip:SetText(row.name or tostring(id), 1, 1, 1)
    GameTooltip:Show()
  end
end

local function rowClick(row, button)
  local meta = { addon = "PFDB" }
  local id, name, kind = row.id, row.name, row.btype
  if not id then return end

  if kind == "items" then
    local link = "item:" .. id .. pfQuestCompat.itemsuffix
    local text = (row.color or "|cffffffff") .. "|H" .. link .. "|h[" .. (name or "?") .. "]|h|r"
    SetItemRef(link, text, button)
    return
  end

  if kind == "quests" then
    if IsShiftKeyDown() and pfQuestCompat.InsertQuestLink then
      pfQuestCompat.InsertQuestLink(id)
      return
    end
    local maps = pfDatabase:SearchQuestID(id, meta)
    pfMap:ShowMapID(pfDatabase:GetBestMap(maps))
  elseif kind == "units" then
    local maps = pfDatabase:SearchMobID(id, meta)
    pfMap:UpdateNodes()
    pfMap:ShowMapID(pfDatabase:GetBestMap(maps))
  elseif kind == "objects" then
    local maps = pfDatabase:SearchObjectID(id, meta)
    pfMap:UpdateNodes()
    pfMap:ShowMapID(pfDatabase:GetBestMap(maps))
  end
end

local function rowFavourite(row)
  local fav = pfBrowser_fav and pfBrowser_fav[row.btype]
  if not fav or not row.id then return end

  if fav[row.id] then
    fav[row.id] = nil
  else
    fav[row.id] = row.name
  end

  row:Reload()
end

local function createRow(tab, index)
  local row = CreateFrame("Button", nil, tab.list)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
  row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
  row:SetID(index)
  row.btype = tab.key

  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetTexture(0, 0, 0, 0)

  row.fav = CreateFrame("Button", nil, row)
  row.fav:SetSize(14, 14)
  row.fav:SetPoint("LEFT", 2, 0)
  row.fav.icon = row.fav:CreateTexture(nil, "ARTWORK")
  row.fav.icon:SetAllPoints()
  row.fav.icon:SetTexture(pfQuestConfig.path .. "\\img\\fav")
  row.fav.icon:SetVertexColor(1, 1, 1, 0.15)
  row.fav:SetScript("OnClick", function() rowFavourite(row) end)

  row.text = row:CreateFontString(nil, "ARTWORK")
  pfq.Font(row.text, pfq.fontSize)
  row.text:SetJustifyH("LEFT")
  row.text:SetPoint("LEFT", row.fav, "RIGHT", 6, 0)
  row.text:SetPoint("RIGHT", -4, 0)

  function row:Reload()
    local fav = pfBrowser_fav and pfBrowser_fav[self.btype] and pfBrowser_fav[self.btype][self.id]

    if self.btype == "items" then
      self.color = qualityColor(self.id)
      self.text:SetText(string.format("%s%s|cffaaaaaa  %d|r", self.color, self.name or "?", self.id or 0))
    else
      self.color = nil
      self.text:SetText(string.format("|cffaaaaaa%d|r  %s", self.id or 0, self.name or "?"))
    end

    if self.fav then
      self.fav.icon:SetVertexColor(1, 1, 1, fav and 1 or 0.15)
    end
  end

  row:SetScript("OnEnter", function(self)
    self.bg:SetTexture(1, 1, 1, 0.06)
    rowEnter(self)
  end)
  row:SetScript("OnLeave", function(self)
    self.bg:SetTexture(0, 0, 0, 0)
    GameTooltip:Hide()
  end)
  row:SetScript("OnClick", function(self, button) rowClick(self, button) end)

  return row
end

---------------------------------------------------------------------------
-- tabs and search
---------------------------------------------------------------------------

function browser:Select(key)
  self.active = key

  local r, g, b = pfq.accent()
  for _, entry in ipairs(TYPES) do
    local tab = self.tabs[entry.key]
    if tab then
      if entry.key == key then
        tab.scroll:Show()
        pfq.SetButtonFontColor(tab.button, r, g, b, 1)
      else
        tab.scroll:Hide()
        pfq.SetButtonFontColor(tab.button, 1, 1, 1, 0.7)
      end
    end
  end
end

function browser:Search(text)
  text = text or ""
  local custom = string.find(text, "^custom:")
  local query = string.gsub(text, "^custom:", "")

  for _, entry in ipairs(TYPES) do
    local kind = entry.key
    local tab = self.tabs[kind]
    local data = (strlen(query) >= 3 or custom)
      and pfDatabase:GetIDByName(query, kind, true, custom)
      or (pfBrowser_fav and pfBrowser_fav[kind])

    local count = 0
    if data then
      for id, name in pairs(data) do
        count = count + 1
        if count >= SEARCH_LIMIT then break end
        if not tab.buttons[count] then
          tab.buttons[count] = createRow(tab, count)
        end
        local row = tab.buttons[count]
        row.btype = kind
        row.id = id
        row.name = name
        row:Reload()
        row:Show()
      end
    end

    for i = count + 1, #tab.buttons do
      tab.buttons[i].id = nil
      tab.buttons[i]:Hide()
    end

    tab.list:SetHeight(max(count, 1) * ROW_HEIGHT)

    local label = tab.button:GetFontString()
    if label then
      label:SetText(entry.caption .. " |cffaaaaaa(" .. (count >= SEARCH_LIMIT and "*" or count) .. ")|r")
    end
  end
end

---------------------------------------------------------------------------
-- construction of the tabs
---------------------------------------------------------------------------

for index, entry in ipairs(TYPES) do
  local tab = browser.tabs[entry.key] or {}
  tab.key = entry.key
  browser.tabs[entry.key] = tab

  tab.button = makeButton(entry.caption, 110, browser, function()
    browser:Select(entry.key)
  end)
  tab.button:SetPoint("TOPLEFT", 10 + (index - 1) * 114, -60)

  tab.scroll = pfq.CreateScrollFrame("pfQuestBrowser" .. entry.key, browser)
  tab.scroll:SetPoint("TOPLEFT", 10, -84)
  tab.scroll:SetPoint("BOTTOMRIGHT", -10, 10)

  tab.list = pfq.CreateScrollChild("pfQuestBrowser" .. entry.key .. "Scroll", tab.scroll)
  tab.list:SetWidth(1)
  tab.list:SetHeight(1)
  tab.buttons = {}
end

browser.input:SetScript("OnTextChanged", function(self)
  local text = self:GetText() or ""
  if text == "" then
    self.hint:Show()
  else
    self.hint:Hide()
  end
  browser:Search(text)
end)

browser.input:SetScript("OnEscapePressed", function(self)
  self:ClearFocus()
end)

---------------------------------------------------------------------------
-- show / hide
---------------------------------------------------------------------------

browser:SetScript("OnShow", function(self)
  -- ElvUI owns the position, same as the tracker
  local E = pfq.engine()
  if E and E.CreateMover and not self.mover then
    self.mover = true
    E:CreateMover(self, "pfQuestBrowserMover", "pfQuest Browser", nil, nil, nil, "ALL,GENERAL")
  end

  self:Select(self.active or "quests")
  self:Search(self.input and self.input:GetText() or "")

  if self.input then
    self.input:SetFocus()
  end
end)

browser:SetScript("OnHide", function(self)
  if self.input then
    self.input:ClearFocus()
  end
  GameTooltip:Hide()
end)
