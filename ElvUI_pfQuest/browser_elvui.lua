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

local ROW_HEIGHT = 20
-- rows are a fixed window that moves over the list, the way a scroll viewport
-- would, but owned here: a ScrollFrame child anchored to its parent does not
-- move when the scroll offset changes, which is what made the wheel and slider
-- do nothing while the thumb still travelled
local VISIBLE_ROWS = 15
local TYPES = {
  { key = "quests", caption = "Quests" },
  { key = "units", caption = "Units" },
  { key = "objects", caption = "Objects" },
  { key = "items", caption = "Items" },
}

local render, move, layoutThumb

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
browser.input:SetTextInsets(6, 64, 0, 0)

-- shown/total for the active tab, kept off the tab buttons: "Quests (100/7058)"
-- does not fit a 110 pixel button and every tab truncates to the same string
browser.count = browser.input:CreateFontString(nil, "OVERLAY")
pfq.Font(browser.count, pfq.fontSize)
browser.count:SetPoint("RIGHT", browser.input, "RIGHT", -6, 0)
browser.count:SetJustifyH("RIGHT")
browser.count:SetTextColor(0.6, 0.6, 0.6)

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
  local row = CreateFrame("Button", nil, tab.view)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
  row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
  row:SetID(index)
  row.btype = tab.key

  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetTexture(0, 0, 0, 0)

  -- pfQuest-epoch replaces OnEnter on the unit tab and touches row.tex, which
  -- is the field name upstream used for the row highlight texture
  row.tex = row.bg

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
  row:SetScript("OnMouseWheel", function(_, delta)
    move(tab, -(delta or 0) * 2)
  end)

  return row
end

---------------------------------------------------------------------------
-- tabs and search
---------------------------------------------------------------------------

local updateCount

function browser:Select(key)
  self.active = key
  if updateCount then updateCount(self) end

  local r, g, b = pfq.accent()
  for _, entry in ipairs(TYPES) do
    local tab = self.tabs[entry.key]
    if tab then
      if entry.key == key then
        tab.view:Show()
        render(tab)
        pfq.SetButtonFontColor(tab.button, r, g, b, 1)
      else
        tab.view:Hide()
        if tab.slider then tab.slider:Hide() end
        pfq.SetButtonFontColor(tab.button, 1, 1, 1, 0.7)
      end
    end
  end
end

-- An empty search box browses instead of searching: list the table from the top
-- so the window is not blank until the player types. Favourites win when the
-- player has any, since that is what the tab used to show.
local function listedEntries(kind)
  local pool = pfDB and pfDB[kind] and pfDB[kind]["loc"]
  if not pool then return nil end

  local ids = {}
  for id in pairs(pool) do ids[#ids + 1] = id end
  table.sort(ids)

  local ret = {}
  for i = 1, #ids do
    local id = ids[i]
    local loc = pool[id]
    if kind == "quests" and type(loc) == "table" then loc = loc["T"] end
    if loc and loc ~= "" then ret[id] = loc end
  end
  return ret
end

updateCount = function(self)
  if not self.count then return end
  local tab = self.tabs and self.tabs[self.active or "quests"]
  if not tab then
    self.count:SetText("")
    return
  end
  -- the readout speaks in ids, because ids are what the rows show. Positions
  -- would be a second numbering scheme that never matches what is on screen.
  local data = tab.data or {}
  local total = #data
  if total == 0 then
    self.count:SetText("0")
    return
  end

  local offset = tab.offset or 0
  local firstItem = data[offset + 1]
  local lastItem = data[math.min(offset + VISIBLE_ROWS, total)]
  if not firstItem then
    self.count:SetText(tostring(total))
    return
  end

  local firstId = tostring(firstItem.id)
  local lastId = lastItem and tostring(lastItem.id) or firstId
  if firstId == lastId then
    self.count:SetText(string.format("%s/%d", firstId, total))
  else
    self.count:SetText(string.format("%s-%s/%d", firstId, lastId, total))
  end
end

-- draw the window of rows that the current offset points at
render = function(tab)
  local data = tab.data or {}
  local total = #data
  local maxOffset = math.max(0, total - VISIBLE_ROWS)

  if tab.offset > maxOffset then tab.offset = maxOffset end
  if tab.offset < 0 then tab.offset = 0 end

  for i = 1, VISIBLE_ROWS do
    if not tab.buttons[i] then
      tab.buttons[i] = createRow(tab, i)
    end

    local row = tab.buttons[i]
    local item = data[tab.offset + i]

    if item then
      local made, err = pcall(function()
        row.btype = tab.key
        row.id = item.id
        row.name = item.name or tostring(item.id)
        row:Reload()
        row:Show()
      end)
      if not made then
        row.id = nil
        row:Hide()
        tab.failure = tab.failure or err
      end
    else
      row.id = nil
      row:Hide()
    end
  end

  if tab.slider then
    tab.slider.maxValue = maxOffset
    tab.slider.value = tab.offset
    if maxOffset > 0 then tab.slider:Show() else tab.slider:Hide() end
    layoutThumb(tab)
  end
end

move = function(tab, delta)
  tab.offset = (tab.offset or 0) + delta
  render(tab)
  updateCount(browser)
end

-- the thumb spans the slice of the list on screen and slides over the track;
-- a fixed 40 pixel bar told you nothing about how much was left
layoutThumb = function(tab)
  local slider = tab.slider
  if not slider or not slider.thumb then return end

  local trackHeight = slider:GetHeight() or 0
  if trackHeight <= 0 then return end

  local total = #(tab.data or {})
  local share = VISIBLE_ROWS / math.max(total, VISIBLE_ROWS)
  local height = trackHeight * share
  if height < 24 then height = 24 end
  if height > trackHeight then height = trackHeight end

  local max = slider.maxValue or 0
  local fraction = 0
  if max > 0 then fraction = (tab.offset or 0) / max end
  if fraction < 0 then fraction = 0 elseif fraction > 1 then fraction = 1 end

  slider.thumb:SetHeight(height)
  slider.thumb:SetPoint("TOP", slider, "TOP", 0, -fraction * (trackHeight - height))
end

function browser:Search(text)
  text = text or ""
  local custom = string.find(text, "^custom:")
  local query = string.gsub(text, "^custom:", "")

  for _, entry in ipairs(TYPES) do
    local kind = entry.key
    local tab = self.tabs[kind]
    local data

    if custom or strlen(query) >= 3 then
      data = pfDatabase:GetIDByName(query, kind, true, custom)
    elseif strlen(query) == 0 then
      local fav = pfBrowser_fav and pfBrowser_fav[kind]
      data = (fav and next(fav)) and fav or listedEntries(kind)
    else
      data = pfBrowser_fav and pfBrowser_fav[kind]
    end

    local list = {}
    if data then
      for id, name in pairs(data) do
        list[#list + 1] = { id = id, name = name }
      end
      table.sort(list, function(a, b) return a.id < b.id end)
    end

    tab.data = list
    tab.offset = 0
    tab.failure = nil
    render(tab)
  end

  updateCount(self)
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

  tab.data = {}
  tab.offset = 0
  tab.buttons = {}

  tab.view = CreateFrame("Frame", nil, browser)
  tab.view:SetPoint("TOPLEFT", 10, -84)
  tab.view:SetPoint("BOTTOMRIGHT", -22, 10)
  tab.view:EnableMouseWheel(1)
  tab.view:SetScript("OnMouseWheel", function(_, delta) move(tab, -(delta or 0) * 2) end)

  -- Two frames of our own rather than a Slider: a real Slider gets a second
  -- thumb texture from the skin engine, which reads as one bar frozen at the
  -- top and another that moves. A track plus a bar cannot do that.
  local slider = CreateFrame("Frame", nil, tab.view)
  tab.slider = slider
  slider:SetPoint("TOPLEFT", tab.view, "TOPRIGHT", 12, 0)
  slider:SetPoint("BOTTOMLEFT", tab.view, "BOTTOMRIGHT", 12, 0)
  slider:SetWidth(12)
  slider:EnableMouse(true)
  slider.maxValue = 0
  slider.value = 0

  slider.track = slider:CreateTexture(nil, "BACKGROUND")
  slider.track:SetAllPoints()
  slider.track:SetTexture(pfq.blankTex())
  slider.track:SetVertexColor(1, 1, 1, 0.08)

  slider.thumb = slider:CreateTexture(nil, "OVERLAY")
  slider.thumb:SetWidth(10)
  slider.thumb:SetTexture(pfq.blankTex())
  do
    local r, g, b = pfq.accent()
    slider.thumb:SetVertexColor(r, g, b, 0.85)
  end

  slider.SetMinMaxValues = function(self, min, max) self.maxValue = max or 0 end
  slider.GetMinMaxValues = function(self) return 0, self.maxValue or 0 end
  slider.GetValue = function(self) return self.value or 0 end
  slider.SetValue = function(self, value)
    local max = self.maxValue or 0
    value = math.max(0, math.min(max, math.floor((value or 0) + 0.5)))
    if value == (self.value or 0) then return end
    self.value = value
    tab.offset = value
    render(tab)
    updateCount(browser)
  end

  -- no OnValueChanged here on purpose: that script type belongs to Sliders and
  -- Edits, and a plain Frame rejects it, which aborted the whole file at load
  -- and left one tab built and nothing wired

  -- follow the cursor while the button is held, the way a scrollbar should
  slider:SetScript("OnMouseDown", function(self) self.dragging = true end)
  slider:SetScript("OnMouseUp", function(self) self.dragging = false end)
  slider:SetScript("OnUpdate", function(self)
    if not self.dragging then return end
    if not IsMouseButtonDown("LeftButton") then
      self.dragging = false
      return
    end

    local max = self.maxValue or 0
    if max <= 0 then return end

    local _, cursorY = GetCursorPosition()
    local scale = self:GetEffectiveScale() or 1
    if scale == 0 then scale = 1 end
    local top = self:GetTop() or 0
    local height = self:GetHeight() or 0
    if height <= 0 then return end

    local fraction = (top - (cursorY / scale)) / height
    if fraction < 0 then fraction = 0 elseif fraction > 1 then fraction = 1 end
    self:SetValue(fraction * max)
  end)

  slider:SetScript("OnMouseWheel", function(_, delta) move(tab, -(delta or 0) * 2) end)
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
