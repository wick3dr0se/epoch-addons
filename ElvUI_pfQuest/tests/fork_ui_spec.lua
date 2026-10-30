--[[
    Headless check for the fork's rewritten tracker and browser.

    Loads pfQuest-wotlk/tracker.lua and browser_elvui.lua against a WoW mock
    with a fake engine (pfMap, pfDatabase, quest log). The point is the contract
    the engine relies on, not pixels:

      - Reset() seeds tracked quests that have no map node
      - ButtonAdd() adds a row per node, in the right mode, and dedupes
      - rows expand and show objective progress
      - Search() fills tabs from pfDatabase:GetIDByName
      - favourites, tab selection and row clicks work

    Run: lua5.1 tests/fork_ui_spec.lua
]]

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  src = src:gsub("^@", "")
  return src:match("^(.*)[/\\]") .. "/"
end
local FORK = scriptDir() .. "../"

local failures, checks = 0, 0
local function check(name, ok, detail)
  checks = checks + 1
  if ok then
    print(string.format("  ok   %s", name))
  else
    failures = failures + 1
    print(string.format("  FAIL %s %s", name, detail and ("-> " .. tostring(detail)) or ""))
  end
end

local frames = {}
local function makeFrame(kind)
  local f = { __kind = kind or "Frame", height = 20, width = 200, shown = true, events = {} }
  local methods = {
    "SetSize", "SetAllPoints", "SetFrameStrata", "SetClampedToScreen",
    "EnableMouse", "RegisterForClicks", "SetJustifyH", "SetTextColor", "SetID", "SetScrollChild",
    "SetMinMaxValues", "SetValue", "SetThumbTexture", "EnableMouseWheel", "SetOrientation",
    "SetVerticalScroll", "SetAutoFocus", "SetTextInsets", "SetFocus", "ClearFocus", "SetAlpha",
    "SetHitRectInsets", "StartMoving", "StopMovingOrSizing", "UnregisterAllEvents", "SetMovable",
    "SetNormalTexture", "SetPushedTexture", "SetHighlightTexture", "SetDisabledTexture",
  }
  for _, m in ipairs(methods) do f[m] = function() end end

  function f:ClearAllPoints() self.points = {} end
  function f:SetPoint(point, ...) 
    self.points = self.points or {}
    self.points[#self.points + 1] = { point = point, args = { ... } }
  end
  function f:SetHeight(h) self.height = h end
  function f:GetHeight() return self.height end
  function f:SetWidth(w) self.width = w end
  function f:GetWidth() return self.width end
  function f:GetStringWidth() return 120 end
  function f:SetMinMaxValues(minv, maxv) self.minValue, self.maxValue = minv, maxv end
  function f:SetValueStep(step) self.valueStep = step end
  function f:SetValue(v) self.value = v end
  function f:GetValue() return self.value end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:IsShown() return self.shown end
  function f:RegisterEvent(e) self.events[e] = true end
  function f:SetScript(k, fn) self["script_" .. k] = fn end
  function f:GetScript(k) return self["script_" .. k] end
  function f:HookScript(k, fn) self["hook_" .. k] = fn end
  function f:SetBackdrop(t) self.backdrop = t end
  function f:SetBackdropColor(r, g, b, a) self.bgColor = { r, g, b, a } end
  function f:SetBackdropBorderColor(r, g, b, a) self.border = { r, g, b, a } end
  function f:GetFrameLevel() return 1 end
  function f:SetFrameLevel() end
  function f:GetScale() return 1 end
  function f:GetVerticalScroll() return 0 end
  function f:GetVerticalScrollRange() return 0 end
  function f:GetThumbTexture()
    if not self.thumb then self.thumb = self:CreateTexture() end
    return self.thumb
  end
  function f:CreateTexture() local t = makeFrame("Texture")
    t.SetTexture = function(self, ...) self.tex = { ... } end
    t.SetVertexColor = function(self, ...) self.vertex = { ... } end
    t.SetSize = function(self, w, h) self.width, self.height = w, h end
    t.SetAllPoints = function() end
    t.SetPoint = function(self, point, ...)
      self.points = self.points or {}
      self.points[#self.points + 1] = { point = point, args = { ... } }
    end
    return t
  end
  function f:CreateFontString() local t = makeFrame("FontString")
    t.SetFont = function(self, p, s, fl) self.font = { p, s, fl } end
    t.SetText = function(self, text) self.text = text end
    t.GetText = function(self) return self.text end
    t.SetTextColor = function(self, ...) self.textColor = { ... } end
    t.GetTextColor = function(self) return 1, 1, 1, 1 end
    t.SetPoint = function(self, point, ...)
      self.points = self.points or {}
      self.points[#self.points + 1] = { point = point, args = { ... } }
    end
    t.SetJustifyH = function() end
    t.SetString = function() end
    return t
  end
  function f:GetParent()
    if self.parent then return self.parent end
    if not self.parentStub then
      self.parentStub = { UpdateScrollState = function() end, SetScrollChild = function() end }
    end
    return self.parentStub
  end
  function f:GetFontString()
    if not self.textObj then self.textObj = self:CreateFontString() end
    return self.textObj
  end
  function f:SetFontString(t) self.textObj = t end
  function f:SetText(t) self:GetFontString():SetText(t) end
  function f:GetText() return self:GetFontString():GetText() end
  frames[#frames + 1] = f
  return f
end

local env = {}
setmetatable(env, { __index = _G })
env._G = env
env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
env.CreateFrame = function(kind, name, parent)
  local f = makeFrame(kind)
  f.parent = parent
  if name then env[name] = f end
  return f
end
env.UIParent = makeFrame("Frame")
env.WorldMapFrame = makeFrame("Frame")
env.GameTooltip = makeFrame("Frame")
env.MouseIsOver = function() return false end
env.GetScreenWidth, env.GetScreenHeight = function() return 1920 end, function() return 1080 end
env.UnitLevel = function() return 60 end
env.UnitClass = function() return "Warrior", "WARRIOR" end
env.UnitRace = function() return "Human", "Human" end
env.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
env.ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0 } }
env.GetItemInfo = function() return "Item", "link", 2 end
env.IsShiftKeyDown = function() return false end
env.IsControlKeyDown = function() return false end
env.IsQuestWatched = function(id) return id == 1 end
env.floor, env.ceil, env.abs = math.floor, math.ceil, math.abs
env.max, env.min, env.strlen = math.max, math.min, string.len
env.gsub, env.strfind, env.format, env.strlower = string.gsub, string.find, string.format, string.lower
env.tinsert = table.insert
env.UISpecialFrames = {}
env.SetItemRef = function() end
env.GameTooltip_SetDefaultAnchor = function() end
env.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
env.UIErrorsFrame = { AddMessage = function() end }
env.QuestLogFrame = makeFrame("Frame")
env.HideUIPanel, env.ShowUIPanel, env.SelectQuestLogEntry = function() end, function() end, function() end
env.print = function() end

env.pfQuest_config = { showtracker = "1", trackerlevel = "1", trackerexpand = "0", trackerfontsize = "12" }
env.pfQuest_history, env.pfQuest_colors = {}, {}
env.pfQuest_Loc = setmetatable({}, { __index = function(_, k) return k end })
env.pfQuestConfig = { path = "Interface\\AddOns\\pfQuest-epoch" }
env.pfDB = { quests = { loc = {} } }
env.pfBrowser_fav = { quests = {}, units = {}, objects = {}, items = {} }

env.pfQuest = {
  questlog = {
    [1] = { title = "Kobold Vermin", qlogid = 1, level = 4 },
    [2] = { title = "Wolves", qlogid = 2, level = 6 },
  },
  route = {},
}
env.GetNumQuestLogEntries = function() return 2, 2 end
env.GetQuestLogTitle = function(id)
  if id == 1 then return "Kobold Vermin", 4, nil, nil, nil, false end
  if id == 2 then return "Wolves", 6, nil, nil, nil, false end
end
env.GetNumQuestLeaderBoards = function() return 1 end
env.GetQuestLogLeaderBoard = function() return "Kobold Vermin slain: 3/10", nil, false end

env.pfQuestCompat = {
  QuestWatchFrame = makeFrame("Frame"),
  GetQuestLogTitle = env.GetQuestLogTitle,
  GetDifficultyColor = function() return { r = 1, g = 1, b = 0 } end,
  itemsuffix = "0:0:0:0:0:0:0:0",
  InsertQuestLink = function() end,
}
env.pfMap = {
  highlight = nil,
  UpdateNodes = function() end,
  DeleteNode = function() end,
  ShowMapID = function() end,
  str2rgb = function() return 1, 1, 1 end,
  tooltip = { GetColor = function() return 1, 1, 0 end },
}
env.pfDB = {
  quests = { loc = { [1] = { T = "The Killing Fields" }, [2] = { T = "Kobold Vermin" } } },
  units = { loc = { [6] = "Kobold Vermin" } },
  objects = { loc = {} },
  items = { loc = { [2589] = "Linen Cloth" } },
}

env.pfDatabase = {
  FormatQuestText = function(t) return t end,
  GetBestMap = function() return 1 end,
  SearchQuestID = function() return {} end,
  SearchMobID = function() return {} end,
  SearchObjectID = function() return {} end,
  ShowExtendedTooltip = function() end,
  GetIDByName = function(self, name, kind)
    if kind == "quests" then return { [1] = "The Killing Fields" } end
    if kind == "items" then return { [2589] = "Linen Cloth" } end
    return {}
  end,
}
env.ElvUI = { { media = {}, Border = 1, CreateMover = function() end, Libs = {} } }

local function run(file, ...)
  local chunk = assert(loadstring(assert(io.open(FORK .. file):read("*a")), file))
  setfenv(chunk, env)
  return chunk(...)
end

run("elvui.lua", "ElvUI_pfQuest")
env.pfq.font = "ElvUI\\Fonts\\Expressway.ttf"

print("== tracker ==")
run("tracker.lua", "ElvUI_pfQuest")

local tracker = env.pfQuest.tracker
check("tracker registered on pfQuest", tracker ~= nil)
check("mode defaults to quest tracking", tracker.mode == "QUEST_TRACKING")

-- fire the startup handler (font sizes, mover, show)
local ev
for _, f in ipairs(frames) do
  if f.events["PLAYER_ENTERING_WORLD"] and f.script_OnEvent then ev = f end
end
env.this = ev
ev.script_OnEvent(ev, "PLAYER_ENTERING_WORLD")

tracker:Reset()
local titles = {}
for _, row in ipairs(tracker.buttons) do
  if row.title then titles[row.title] = true end
end
check("Reset seeds watched quests", titles["Kobold Vermin"] == true, "rows: " .. tostring(#tracker.buttons))
check("rows show progress text", (function()
  for _, row in ipairs(tracker.buttons) do
    if row.title == "Kobold Vermin" then return (row.text:GetText() or ""):find("Kobold Vermin") ~= nil end
  end
end)() == true)

tracker.ButtonAdd("Kobold Vermin", { addon = "PFQUEST" })
local count = 0
for _, row in ipairs(tracker.buttons) do if row.title == "Kobold Vermin" then count = count + 1 end end
check("duplicate title does not add a second row", count == 1)

tracker.DoLayout()
check("layout sizes the panel", tracker:GetHeight() > 0 and tracker:GetWidth() > 0)

-- quest giver mode filters non-nodes and skips taken quests
tracker.mode = "GIVER_TRACKING"
tracker:Reset()
tracker.ButtonAdd("Fresh Quest", { addon = "PFQUEST", layer = 1, qlvl = 10, qmin = 10 })
local giver
for _, row in ipairs(tracker.buttons) do if row.title == "Fresh Quest" then giver = row end end
check("giver mode adds an available quest", giver ~= nil)
tracker.ButtonAdd("Kobold Vermin", { addon = "PFQUEST", layer = 1 })
check("giver mode skips quests already in the log", (function()
  for _, row in ipairs(tracker.buttons) do if row.title == "Kobold Vermin" then return false end end
  return true
end)())

print("== browser ==")
run("browser_elvui.lua", "ElvUI_pfQuest")
local browser = env.pfBrowser
check("browser created", browser ~= nil)
check("four tabs exist", browser.tabs.quests and browser.tabs.units and browser.tabs.objects and browser.tabs.items)
check("epoch shape: tabs[type].buttons", type(browser.tabs.quests.buttons) == "table")
check("epoch shape: browser.input", browser.input ~= nil)

browser:Search("killing")
local visible = 0
for _, row in ipairs(browser.tabs.quests.buttons) do
  if row.id then visible = visible + 1 end
end
check("search fills the quest tab", visible == 1, visible)
check("row text carries the name", (browser.tabs.quests.buttons[1].text:GetText() or ""):find("The Killing Fields") ~= nil)

browser:Search("")
local favRows = 0
for _, row in ipairs(browser.tabs.quests.buttons) do
  if row.id then favRows = favRows + 1 end
end
check("empty search falls back to favourites", favRows == 0)

browser.tabs.quests.buttons[1]:Reload()
browser.tabs.quests.buttons[1].id = 1
browser.tabs.quests.buttons[1].btype = "quests"
browser.tabs.quests.buttons[1].name = "The Killing Fields"
browser.tabs.quests.buttons[1].fav.script_OnClick()
check("favourite toggles pfBrowser_fav", env.pfBrowser_fav.quests[1] == "The Killing Fields", env.pfBrowser_fav.quests[1])

browser:Select("items")
check("select switches tab", browser.active == "items")
check("only the selected scroll frame is shown", browser.tabs.items.scroll.shown == true and browser.tabs.quests.scroll.shown == false)

browser.input:SetText("linen")
check("typing drives a search", (browser.tabs.items.buttons[1].text:GetText() or ""):find("Linen Cloth") ~= nil)

print("== tracker layout and persistence ==")
check("mode icons pinned to the top", (function()
  for _, entry in ipairs({ "btnquest", "btndatabase", "btngiver" }) do
    local b = tracker[entry]
    local point = b and b.points and b.points[1] and b.points[1].point
    if point ~= "TOPLEFT" then return false, entry .. "=" .. tostring(point) end
  end
  return true
end)())
check("title follows the icon group", (function()
  local points = tracker.title.points
  local last = points and points[#points]
  return last ~= nil and last.point == "LEFT" and last.args[1] == tracker.btngiver,
    "count=" .. tostring(points and #points) .. " point=" .. tostring(last and last.point)
end)())
check("close button pinned to the top", (function()
  local p = tracker.btnclose.points and tracker.btnclose.points[1]
  return p and p.point == "TOPRIGHT"
end)())

tracker:Show()
check("showing the tracker records the preference", env.pfQuest_config.showtracker == "1", env.pfQuest_config.showtracker)
tracker:Hide()
check("logout-style hide does not clear the preference", env.pfQuest_config.showtracker == "1", env.pfQuest_config.showtracker)
tracker:Show()
tracker.btnclose.script_OnClick()
check("closing it explicitly does clear the preference", env.pfQuest_config.showtracker == "0", env.pfQuest_config.showtracker)

print("== route arrow ==")
do
  -- the arrow moved from a private shift-drag to an ElvUI mover; a private
  -- drag coming back would fight the mover for the same frame
  local fh = io.open(scriptDir() .. "../route.lua")
  local src = fh and fh:read("*a") or ""
  if fh then fh:close() end

  check("arrow registers an ElvUI mover",
    src:find('CreateMover(pfQuest.route.arrow', 1, true) ~= nil)
  check("arrow has no private drag handler",
    src:find("OnDragStart", 1, true) == nil)
  check("arrow does not swallow clicks",
    src:find('arrow:EnableMouse(false)', 1, true) ~= nil)
  check("arrow text is anchored to the arrow",
    src:find('arrow.title:SetPoint("TOP", pfQuest.route.arrow.model', 1, true) ~= nil)
end

print("== world map dropdown ==")
do
  env.GetBuildInfo = function() return '3.3.5', '12340' end
  env.StaticPopupDialogs = setmetatable({}, { __index = function() return function() end end })

  local ok, err = pcall(run, "quest.lua", "ElvUI_pfQuest")
  check("quest.lua loads without error", ok, err)

  -- in game the dropdown is built from ADDON_LOADED, so a bare load never runs
  -- it: call it the way the addon does, then click it like a player would
  env.pfQuest_config.trackingmethod = 2
  local built, buildErr = pcall(function() env.pfQuest:AddWorldMapIntegration() end)
  check("AddWorldMapIntegration builds the map button", built, buildErr)

  local button = env.pfQuest.mapButton
  check("map button exists", button ~= nil)
  check("map button is labelled with the current mode",
    button ~= nil and button.label ~= nil and button.label.text == "Tracked Quests",
    button and button.label and button.label.text)

  if button then
    local clicked, clickErr = pcall(button.script_OnClick, button)
    check("clicking it builds the menu without error", clicked, clickErr)
    check("the menu lists all four modes",
      env.pfQuestPopup ~= nil and env.pfQuestPopup.rows ~= nil and #env.pfQuestPopup.rows >= 4,
      env.pfQuestPopup and env.pfQuestPopup.rows and #env.pfQuestPopup.rows)
  end
end

print("== onupdate tickers ==")
local ticked, failed = 0, nil
for _, f in ipairs(frames) do
  if f.script_OnUpdate then
    ticked = ticked + 1
    local ok, err = pcall(f.script_OnUpdate, f, 0.1)
    if not ok and not failed then failed = err end
  end
end
check("every OnUpdate survives a tick", failed == nil, failed)
check("at least one ticker exists", ticked > 0, ticked)

print(string.format("\n%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
