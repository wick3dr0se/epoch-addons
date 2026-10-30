--[[
    pfQuest / tracker.lua  (ElvUI rewrite)

    Replaces the old tracker wholesale. The previous file built a panel, an icon
    strip and row buttons of its own, which a skin addon then had to restyle.
    This one is the tracker: ElvUI backdrop, ElvUI font, ElvUI mover, one hover
    wash. Nothing outside this file restyles it.

    Contract kept, because the engine calls these:

      pfQuest.tracker.Reset()                 before the node walk
      pfQuest.tracker.ButtonAdd(title, node)  per node
      pfQuest.tracker.ButtonEvent(row)        row refresh
      pfQuest.tracker.mode                    QUEST_TRACKING / GIVER_TRACKING / DATABASE_TRACKING
      tracker:Show() / :Hide()

    Behaviour kept from the old file: tracked quests are seeded even when they
    have no map node, a node icon outranks a cluster icon for the same title,
    rows refresh on quest events, the panel fades with trackeralpha, the tracker
    raises its strata while the world map is open, and Blizzard's WatchFrame
    stays hidden.

    Changed: position is owned by an ElvUI mover instead of a private drag, so
    `/db lock` no longer applies to it. One shared 10Hz ticker drives the
    highlight instead of an OnUpdate per row.
]]

local compat = pfQuestCompat

local tracker = CreateFrame("Frame", "pfQuestTracker", UIParent)
tracker:Hide()
tracker:SetPoint("RIGHT", UIParent, "RIGHT", -20, 90)
tracker:SetSize(200, 20)
tracker.buttons = {}
tracker.mode = "QUEST_TRACKING"
pfQuest.tracker = tracker

local PANEL_HEIGHT = 18
local expandStates = {}

local fontsize, entryheight = 12, 20

pfq.CreateBackdrop(tracker)

---------------------------------------------------------------------------
-- header: title plus an icon strip built from ElvUI buttons
---------------------------------------------------------------------------

tracker.title = tracker:CreateFontString(nil, "OVERLAY")
pfq.Font(tracker.title, pfq.fontSize)
tracker.title:SetPoint("LEFT", 6, 0)
tracker.title:SetText("|cff33ffccpf|cffffffffQuest|r")

local function headerButton(icon, tooltip, onClick)
  local b = CreateFrame("Button", nil, tracker)
  b:SetSize(14, 14)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexture(pfQuestConfig.path .. "\\img\\tracker_" .. icon)

  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(tooltip, 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", onClick)

  return b
end

local modeButtons = {}

local function addMode(key, icon, tooltip, mode)
  local b = headerButton(icon, tooltip, function()
    tracker.mode = mode
    paintModes()
    pfMap:UpdateNodes()
  end)
  b:SetPoint("TOPLEFT", 4 + #modeButtons * 16, -3)
  tracker[key] = b
  modeButtons[#modeButtons + 1] = { button = b, mode = mode }
end

function paintModes()
  local r, g, b = pfq.accent()
  for _, entry in ipairs(modeButtons) do
    if tracker.mode == entry.mode then
      entry.button.icon:SetVertexColor(r, g, b)
    else
      entry.button.icon:SetVertexColor(1, 1, 1, 0.65)
    end
  end
end

addMode("btnquest", "quests", pfQuest_Loc["Show Current Quests"], "QUEST_TRACKING")
addMode("btndatabase", "database", pfQuest_Loc["Show Database Results"], "DATABASE_TRACKING")
addMode("btngiver", "giver", pfQuest_Loc["Show Quest Givers"], "GIVER_TRACKING")

-- the title follows the icon group instead of sitting at a fixed offset, so the
-- left side reads as one block the way the right side does
tracker.title:ClearAllPoints()
tracker.title:SetPoint("LEFT", tracker.btngiver, "RIGHT", 6, 0)

tracker.btnclose = headerButton("close", pfQuest_Loc["Close Tracker"], function()
  DEFAULT_CHAT_FRAME:AddMessage(pfQuest_Loc["|cff33ffccpf|cffffffffQuest: Tracker is now hidden. Type `/db tracker` to show."])
  -- only an explicit close writes the preference. OnHide cannot: the client
  -- hides every frame during logout, which would overwrite "1" with "0" on
  -- every session and the tracker would never come back on its own.
  pfQuest_config["showtracker"] = "0"
  tracker:Hide()
end)
tracker.btnclose:SetPoint("TOPRIGHT", -6, -3)

tracker.btnsearch = headerButton("search", pfQuest_Loc["Open Database Browser"], function()
  if pfBrowser then pfBrowser:Show() end
end)
tracker.btnsearch:SetPoint("TOPRIGHT", tracker.btnclose, "TOPLEFT", -2, 0)

tracker.btnclean = headerButton("clean", pfQuest_Loc["Clean Database Results"], function()
  pfMap:DeleteNode("PFDB")
  pfMap:UpdateNodes()
end)
tracker.btnclean:SetPoint("TOPRIGHT", tracker.btnsearch, "TOPLEFT", -2, 0)

tracker.btnsettings = headerButton("settings", pfQuest_Loc["Open Settings"], function()
  -- the fork's own window is retired; this opens the ElvUI panel
  pfq.OpenOptions()
end)
tracker.btnsettings:SetPoint("TOPRIGHT", tracker.btnclean, "TOPLEFT", -2, 0)

---------------------------------------------------------------------------
-- tooltips and row content
---------------------------------------------------------------------------

local function HideTooltip()
  GameTooltip:Hide()
end

local function ShowTooltip(row)
  if not row.tooltip then return end

  GameTooltip:ClearLines()
  GameTooltip_SetDefaultAnchor(GameTooltip, row)
  GameTooltip:SetText(row.text:GetText() or "", row.text:GetTextColor())

  if row.node and row.node.questid then
    if pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][row.node.questid] and pfDB["quests"]["loc"][row.node.questid]["O"] then
      GameTooltip:AddLine(pfDatabase:FormatQuestText(pfDB["quests"]["loc"][row.node.questid]["O"]), 1, 1, 1, 1)
      GameTooltip:AddLine(" ")
    end

    local qlogid = pfQuest.questlog[row.node.questid] and pfQuest.questlog[row.node.questid].qlogid
    if qlogid then
      local objectives = GetNumQuestLeaderBoards(qlogid)
      for i = 1, objectives or 0 do
        local text, _, done = GetQuestLogLeaderBoard(i, qlogid)
        local _, _, obj, cur, req = strfind(gsub(text, "\239\188\154", ":"), "(.*):%s*([%d]+)%s*/%s*([%d]+)")
        if done then
          GameTooltip:AddLine(" - " .. text, 0, 1, 0)
        elseif cur and req then
          local r, g, b = pfMap.tooltip:GetColor(cur, req)
          GameTooltip:AddLine(" - " .. text, r, g, b)
        else
          GameTooltip:AddLine(" - " .. text, 1, 0, 0)
        end
      end
      GameTooltip:AddLine(" ")
    end
  end

  GameTooltip:AddLine(row.tooltip, 1, 1, 1)
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- rows
---------------------------------------------------------------------------

local function rowIcon(row, title, node)
  if node.texture then
    row.icon:SetTexture(node.texture)
    local vertex = node.vertex or { 0, 0, 0 }
    if vertex[1] > 0 or vertex[2] > 0 or vertex[3] > 0 then
      row.icon:SetVertexColor(vertex[1], vertex[2], vertex[3])
    else
      row.icon:SetVertexColor(1, 1, 1, 1)
    end
  elseif pfQuest_config["spawncolors"] == "1" then
    row.icon:SetTexture(pfQuestConfig.path .. "\\img\\available_c")
    row.icon:SetVertexColor(1, 1, 1, 1)
  else
    row.icon:SetTexture(pfQuestConfig.path .. "\\img\\node")
    row.icon:SetVertexColor(pfMap.str2rgb(title))
  end
end

local function rowClick(row, button)
  if button == "RightButton" then
    for questid, data in pairs(pfQuest.questlog) do
      if data.title == row.title then
        HideUIPanel(QuestLogFrame)
        SelectQuestLogEntry(data.qlogid)
        ShowUIPanel(QuestLogFrame)
        break
      end
    end
    return
  end

  if IsShiftKeyDown() then
    if row.node and row.node.questid and not row.node.qlogid then
      pfQuest_history[row.node.questid] = { time(), UnitLevel("player") }
      UIErrorsFrame:AddMessage(string.format("The Quest |cffffcc00[%s]|r (id:%s) is now marked as done.", row.title, row.node.questid), 1, 1, 1)
    end
    if row.node then
      pfMap:DeleteNode(row.node.addon, row.title)
      pfMap:UpdateNodes()
      pfQuest.updateQuestGivers = true
    end
  elseif IsControlKeyDown() and not WorldMapFrame:IsShown() then
    if ToggleWorldMap then
      ToggleWorldMap()
    else
      WorldMapFrame:Show()
    end
  elseif IsControlKeyDown() and pfQuest_config["spawncolors"] == "0" then
    pfQuest_colors[row.title] = { pfMap.str2rgb(row.title .. GetTime()) }
    pfMap:UpdateNodes()
  elseif expandStates[row.title] == 0 then
    expandStates[row.title] = 1
    tracker.ButtonEvent(row)
  elseif expandStates[row.title] == 1 then
    expandStates[row.title] = 0
    tracker.ButtonEvent(row)
  end
end

local function createRow(id)
  local row = CreateFrame("Button", "pfQuestTrackerRow" .. id, tracker)
  row:SetHeight(entryheight)
  row:SetID(id)
  row.objectives = {}

  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetTexture(0, 0, 0, 0)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(12, 12)
  row.icon:SetPoint("TOPLEFT", 2, -4)

  row.text = row:CreateFontString(nil, "ARTWORK")
  pfq.Font(row.text, fontsize)
  row.text:SetJustifyH("LEFT")
  row.text:SetPoint("TOPLEFT", 18, -4)
  row.text:SetPoint("TOPRIGHT", -6, -4)

  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  -- rows carry their own quest events, exactly like the old file: progress has
  -- to update without waiting for a full node rebuild
  row:RegisterEvent("QUEST_WATCH_UPDATE")
  row:RegisterEvent("QUEST_LOG_UPDATE")
  row:RegisterEvent("QUEST_FINISHED")
  row:SetScript("OnEvent", function(self) tracker.ButtonEvent(self) end)

  row:SetScript("OnEnter", function(self)
    pfMap.highlight = self.title
    ShowTooltip(self)
  end)
  row:SetScript("OnLeave", function()
    pfMap.highlight = nil
    HideTooltip()
  end)
  row:SetScript("OnClick", function(self, button) rowClick(self, button) end)

  return row
end

function tracker.ButtonEvent(row)
  row = row or this
  local title, node = row and row.title, row and row.node
  if not title then return end

  row:SetHeight(entryheight)
  for _, objective in pairs(row.objectives) do
    objective:Hide()
  end

  rowIcon(row, title, node)

  if tracker.mode == "QUEST_TRACKING" then
    local qid = row.questid
    local qlogid = pfQuest.questlog[qid] and pfQuest.questlog[qid].qlogid or 0
    local qtitle, level, tag, header, collapsed, complete = compat.GetQuestLogTitle(qlogid)
    if not qlogid or not qtitle then return end

    local objectives = GetNumQuestLeaderBoards(qlogid)
    local watched = IsQuestWatched(qlogid)
    local color = pfQuestCompat.GetDifficultyColor(level)
    local cur, max = 0, 0

    if not expandStates[title] then
      expandStates[title] = pfQuest_config["trackerexpand"] == "1" and 1 or 0
    end
    local expanded = expandStates[title] == 1 and true or nil

    for i = 1, objectives or 0 do
      local text, _, done = GetQuestLogLeaderBoard(i, qlogid)
      local _, _, obj, current, needed = strfind(gsub(text, "\239\188\154", ":"), "(.*):%s*([%d]+)%s*/%s*([%d]+)")
      if current and needed then
        max = max + tonumber(needed)
        cur = cur + tonumber(current)
      elseif not done then
        max = max + 1
      end
    end

    local percent
    if cur == max or complete or max == 0 then
      percent = 100
      cur, max = 1, 1
    else
      percent = cur / max * 100
    end

    if objectives and objectives > 0 and (expanded or (percent > 0 and percent < 100)) then
      row:SetHeight(entryheight + objectives * fontsize)

      for i = 1, objectives do
        local text, _, done = GetQuestLogLeaderBoard(i, qlogid)
        local _, _, objective, current, needed = strfind(gsub(text, "\239\188\154", ":"), "(.*):%s*([%d]+)%s*/%s*([%d]+)")

        if not row.objectives[i] then
          row.objectives[i] = row:CreateFontString(nil, "ARTWORK")
          pfq.Font(row.objectives[i], fontsize)
          row.objectives[i]:SetJustifyH("LEFT")
          row.objectives[i]:SetPoint("TOPLEFT", 18, -fontsize * i - 8)
          row.objectives[i]:SetPoint("TOPRIGHT", -6, -fontsize * i - 8)
        end

        if current and needed then
          local r, g, b = pfMap.tooltip:GetColor(current, needed)
          row.objectives[i]:SetTextColor(r + 0.2, g + 0.2, b + 0.2)
          row.objectives[i]:SetText(string.format("|cffffffff- %s:|r %s/%s", objective, current, needed))
        else
          row.objectives[i]:SetTextColor(0.8, 0.8, 0.8)
          row.objectives[i]:SetText("|cffffffff- " .. text)
        end
        row.objectives[i]:Show()
      end
    end

    local r, g, b = pfMap.tooltip:GetColor(cur, max)
    local levelText = pfQuest_config["trackerlevel"] == "1" and ("[" .. (level or "??") .. (tag and "+" or "") .. "] ") or ""
    row.text:SetText(string.format("%s%s |cffaaaaaa(%d%%|cffaaaaaa)|r", levelText, title, ceil(percent)))
    row.text:SetTextColor(color.r, color.g, color.b)
    row.tooltip = pfQuest_Loc["|cff33ffcc<Click>|r Unfold/Fold Objectives\n|cff33ffcc<Right-Click>|r Show In QuestLog\n|cff33ffcc<Ctrl-Click>|r Show Map / Toggle Color\n|cff33ffcc<Shift-Click>|r Hide Nodes"]
    row.tracked = watched and true or nil
    row.perc = percent
  elseif tracker.mode == "GIVER_TRACKING" then
    local level = node.qlvl or node.level or UnitLevel("player")
    local color = pfQuestCompat.GetDifficultyColor(level)

    if node.qmin and node.qmin > UnitLevel("player") then
      color = { r = 1, g = 0, b = 0 }
    end
    if node.qmin and node.qlvl and math.abs(node.qmin - node.qlvl) >= 30 then
      level, color = 0, { r = 0.2, g = 0.8, b = 1 }
    end

    local levelText = pfQuest_config["trackerlevel"] == "1" and ("[" .. (level or "??") .. "] ") or ""
    row.text:SetTextColor(color.r, color.g, color.b)
    row.text:SetText(levelText .. title)
    row.level = tonumber(level)
    row.tooltip = pfQuest_Loc["|cff33ffcc<Ctrl-Click>|r Show Map / Toggle Color\n|cff33ffcc<Shift-Click>|r Mark As Done"]
  else
    row.text:SetText(title)
    row.text:SetTextColor(pfMap.str2rgb(title))
    row.tooltip = pfQuest_Loc["|cff33ffcc<Ctrl-Click>|r Show Map / Toggle Color\n|cff33ffcc<Shift-Click>|r Hide Nodes"]
  end

  row:Show()
  tracker.DoLayout()
end

---------------------------------------------------------------------------
-- layout
---------------------------------------------------------------------------

local function sortRows(a, b)
  if a.empty then return false end
  if (a.tracked and 1 or -1) ~= (b.tracked and 1 or -1) then
    return (a.tracked and 1 or -1) > (b.tracked and 1 or -1)
  elseif (a.level or -1) ~= (b.level or -1) then
    return (a.level or -1) > (b.level or -1)
  elseif (a.perc or -1) ~= (b.perc or -1) then
    return (a.perc or -1) > (b.perc or -1)
  end
  return (a.title or "") < (b.title or "")
end

function tracker.DoLayout()
  table.sort(tracker.buttons, sortRows)

  local height = PANEL_HEIGHT
  local width = 100

  for _, row in pairs(tracker.buttons) do
    row:ClearAllPoints()
    row:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", 0, -height)
    row:SetPoint("TOPLEFT", tracker, "TOPLEFT", 0, -height)

    if not row.empty and row:IsShown() then
      height = height + row:GetHeight()

      if row.text:GetStringWidth() > width then
        width = row.text:GetStringWidth()
      end

      for _, objective in pairs(row.objectives) do
        if objective:IsShown() and objective:GetStringWidth() > width then
          width = objective:GetStringWidth()
        end
      end
    end
  end

  width = min(width, 300) + 30
  tracker:SetHeight(height)
  tracker:SetWidth(width)
end

---------------------------------------------------------------------------
-- node intake
---------------------------------------------------------------------------

function tracker.ButtonAdd(title, node)
  if not title or not node then return end

  local questid = title
  for qid, data in pairs(pfQuest.questlog) do
    if data.title == title then
      questid = qid
      break
    end
  end

  if tracker.mode == "QUEST_TRACKING" then
    if node.addon ~= "PFQUEST" then return end
    if not pfQuest.questlog or not pfQuest.questlog[questid] then return end
  elseif tracker.mode == "GIVER_TRACKING" then
    if node.addon ~= "PFQUEST" then return end
    if not pfQuest.questlog or pfQuest.questlog[questid] then return end
    if not node.layer or node.layer > 2 then return end
  elseif tracker.mode == "DATABASE_TRACKING" then
    if node.addon ~= "PFDB" then return end
  end

  local id

  -- a node icon outranks a cluster icon for the same title
  for bid, button in pairs(tracker.buttons) do
    if button.title and button.title == title then
      if node.dummy or not node.texture then
        id = bid
        break
      elseif node.cluster and (not button.node or button.node.texture) then
        id = bid
      else
        return
      end
    end
  end

  if not id then
    id = #tracker.buttons + 1
    for bid, button in pairs(tracker.buttons) do
      if button.empty then
        id = bid
        break
      end
    end
  end

  if id > 25 then return end

  if not tracker.buttons[id] then
    tracker.buttons[id] = createRow(id)
  end

  local row = tracker.buttons[id]
  row.empty = nil
  row.title = title
  row.node = node
  row.questid = questid

  tracker.ButtonEvent(row)
end

function tracker.Reset()
  tracker:SetHeight(PANEL_HEIGHT)

  for _, button in pairs(tracker.buttons) do
    button.level = nil
    button.title = nil
    button.perc = nil
    button.empty = true
    button:SetHeight(0)
    button:Hide()
  end

  -- tracked quests appear even when they have no map node in this zone
  local _, numQuests = GetNumQuestLogEntries()
  local found = 0

  for qlogid = 1, 40 do
    local title, level, tag, header, collapsed, complete = compat.GetQuestLogTitle(qlogid)
    if title and not header then
      if IsQuestWatched(qlogid) then
        local img = complete and pfQuestConfig.path .. "\\img\\complete_c" or pfQuestConfig.path .. "\\img\\complete"
        tracker.ButtonAdd(title, { dummy = true, addon = "PFQUEST", texture = img })
      end

      found = found + 1
      if found >= numQuests then break end
    end
  end
end

---------------------------------------------------------------------------
-- fade, strata, WatchFrame
---------------------------------------------------------------------------

tracker:SetScript("OnUpdate", function(self)
  if WorldMapFrame:IsShown() then
    if self.strata ~= "FULLSCREEN_DIALOG" then
      self:SetFrameStrata("FULLSCREEN_DIALOG")
      self.strata = "FULLSCREEN_DIALOG"
    end
  else
    if self.strata ~= "BACKGROUND" then
      self:SetFrameStrata("BACKGROUND")
      self.strata = "BACKGROUND"
    end
  end

  local content = tracker.buttons[1] and not tracker.buttons[1].empty and true or nil
  local goal = (content and not MouseIsOver(self)) and 0 or not content and not MouseIsOver(self) and 0.5 or 1
  local alpha = self.fade or 1
  if ceil(alpha * 10) ~= ceil(goal * 10) then
    alpha = alpha + ((goal - alpha) > 0 and 0.1 or -0.1)
    self.fade = alpha
    pfq.paint(self, alpha * 0.8)
  end

  if pfQuestCompat.QuestWatchFrame:IsShown() then
    pfQuestCompat.QuestWatchFrame:Hide()
  end
end)

tracker:SetScript("OnShow", function()
  pfQuest_config["showtracker"] = "1"
  paintModes()
  tracker.DoLayout()
end)

---------------------------------------------------------------------------
-- startup
---------------------------------------------------------------------------

local startup = CreateFrame("Frame")
startup:RegisterEvent("PLAYER_ENTERING_WORLD")
startup:SetScript("OnEvent", function(self)
  fontsize = tonumber(pfQuest_config["trackerfontsize"]) or 12
  entryheight = ceil(fontsize * 1.6)

  -- position belongs to ElvUI now
  local E = pfq.engine()
  if E and E.CreateMover then
    E:CreateMover(tracker, "pfQuestTrackerMover", "pfQuest Tracker", nil, nil, nil, "ALL,GENERAL")
  end

  if pfQuest_config["showtracker"] == "0" then
    tracker:Hide()
  else
    tracker:Show()
  end

  self:UnregisterAllEvents()
end)

-- single highlight ticker for every row, instead of an OnUpdate per row
local highlight = CreateFrame("Frame")
local elapsed, last = 0, nil
highlight:SetScript("OnUpdate", function(self, delta)
  elapsed = elapsed + (delta or 0)
  if elapsed < 0.1 then return end
  elapsed = 0

  if not tracker:IsShown() then return end

  local current = pfMap and pfMap.highlight
  if current == last then return end
  last = current

  local r, g, b = pfq.accent()
  for _, row in pairs(tracker.buttons) do
    if row.bg then
      if current and current == row.title then
        row.bg:SetTexture(r, g, b, 0.22)
      else
        row.bg:SetTexture(0, 0, 0, 0)
      end
    end
  end
end)
