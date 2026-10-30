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
  -- 3.3.5a frames only accept their own script types; a plain Frame rejects
  -- OnValueChanged, which is a Slider/Edit script. Accepting anything here is
  -- what let a load-time abort pass the suite.
  local FRAME_SCRIPTS = {
    OnClick = true, OnEnter = true, OnLeave = true, OnMouseDown = true, OnMouseUp = true,
    OnMouseWheel = true, OnUpdate = true, OnShow = true, OnHide = true, OnTextChanged = true,
    OnEnterPressed = true, OnEscapePressed = true, OnChar = true, OnKeyDown = true, OnKeyUp = true,
    OnDragStart = true, OnDragStop = true, OnMouseOver = true, OnSizeChanged = true, OnEvent = true,
  }
  function f:SetScript(k, fn)
    assert(FRAME_SCRIPTS[k], "SetScript on a frame with an unsupported script type: " .. tostring(k))
    self["script_" .. k] = fn
  end
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

local function visibleRows(tab)
  local n = 0
  for _, row in ipairs(tab.buttons) do if row.id then n = n + 1 end end
  return n
end

browser:Search("killing")
check("search fills the quest tab", visibleRows(browser.tabs.quests) == 1, visibleRows(browser.tabs.quests))
check("row text carries the name", (browser.tabs.quests.buttons[1].text:GetText() or ""):find("The Killing Fields") ~= nil)

browser:Search("")
check("an empty box browses the table instead of showing nothing", visibleRows(browser.tabs.quests) == 2, visibleRows(browser.tabs.quests))
check("every tab is filled, not just the active one", visibleRows(browser.tabs.items) == 1, visibleRows(browser.tabs.items))

do
  local label = browser.tabs.quests.button:GetFontString()
  check("tab button carries only its caption", label and label:GetText() == "Quests", label and label:GetText())
  local count = (browser.count and browser.count:GetText()) or ""
  check("the count readout shows the visible range", count == "1-2/2", count)
end

do
  -- 150 entries, a 15 row window: the window moves, the list does not shrink
  local big = {}
  for i = 1, 150 do big[i] = { T = "Quest " .. i } end
  local saved = env.pfDB.quests.loc
  env.pfDB.quests.loc = big
  browser:Search("")

  local tab = browser.tabs.quests
  check("the row pool stays at the window size", #tab.buttons == 15, #tab.buttons)
  check("the first window shows 15 of 150", visibleRows(tab) == 15, visibleRows(tab))
  check("the count readout shows the window", (browser.count:GetText()) == "1-15/150", browser.count:GetText())
  check("the slider spans the whole list", tab.slider.maxValue == 135, tab.slider.maxValue)

  local firstId = tab.buttons[1].id
  tab.buttons[1].script_OnMouseWheel(tab.buttons[1], -2)
  check("the wheel moves the window", tab.offset == 4, tab.offset)
  check("the first row now shows a later entry", tab.buttons[1].id ~= firstId, tab.buttons[1].id)
  check("the count readout follows the window", (browser.count:GetText()) == "5-19/150", browser.count:GetText())

  tab.slider:SetValue(135)
  check("the slider can reach the end", tab.offset == 135 and tab.buttons[15].id ~= nil, tab.offset)
  check("the last window ends at 150", (browser.count:GetText()) == "136-150/150", browser.count:GetText())

  -- a Slider frame gets a second thumb from the skin engine, which showed up as
  -- one bar frozen at the top and another that moved
  check("the scrollbar draws its own track and thumb", tab.slider.track ~= nil and tab.slider.thumb ~= nil)

  tab.slider:SetHeight(300)
  tab.slider:SetValue(0)
  check("the thumb spans the visible slice", tab.slider.thumb.height == 30, tab.slider.thumb.height)

  local lastPoint = tab.slider.thumb.points[#tab.slider.thumb.points]
  check("the thumb starts at the top", lastPoint.args[4] == 0, lastPoint.args[4])

  tab.slider:SetValue(135)
  lastPoint = tab.slider.thumb.points[#tab.slider.thumb.points]
  check("the thumb ends at the bottom", lastPoint.args[4] == -270, lastPoint.args[4])

  env.pfDB.quests.loc = saved
  browser:Search("")
end

do
  -- ids are sparse in the real tables, so the readout has to speak in ids: a
  -- position range reads as a bug next to rows numbered 10, 20, 30
  local saved = env.pfDB.quests.loc
  local spaced = {}
  for i = 1, 40 do spaced[i * 10] = { T = "Sparse " .. i } end
  env.pfDB.quests.loc = spaced
  browser:Search("")
  check("the readout reports the visible id range", (browser.count:GetText()) == "10-150/40", browser.count:GetText())
  env.pfDB.quests.loc = saved
  browser:Search("")
end

do
  -- pfQuest-epoch rebinds the unit tab's OnEnter and touches row.tex
  local row = browser.tabs.quests.buttons[1]
  check("rows expose .tex for epoch's rank tooltip", row ~= nil and row.tex ~= nil and row.tex == row.bg)
  check("rows live in the tab view", row:GetParent() == browser.tabs.quests.view)
end

env.pfBrowser_fav = { quests = { [1] = "The Killing Fields" }, units = {}, objects = {}, items = {} }
browser:Search("")
local favRows = 0
for _, row in ipairs(browser.tabs.quests.buttons) do
  if row.id then favRows = favRows + 1 end
end
check("favourites win over browsing when they exist", favRows == 1, favRows)
env.pfBrowser_fav = { quests = {}, units = {}, objects = {}, items = {} }

browser.tabs.quests.buttons[1]:Reload()
browser.tabs.quests.buttons[1].id = 1
browser.tabs.quests.buttons[1].btype = "quests"
browser.tabs.quests.buttons[1].name = "The Killing Fields"
browser.tabs.quests.buttons[1].fav.script_OnClick()
check("favourite toggles pfBrowser_fav", env.pfBrowser_fav.quests[1] == "The Killing Fields", env.pfBrowser_fav.quests[1])

browser:Select("items")
check("select switches tab", browser.active == "items")
check("only the selected tab view is shown", browser.tabs.items.view.shown == true and browser.tabs.quests.view.shown == false)
-- four sliders stacked at the same point read as one bar with a doubled thumb
check("the previous tab slider is hidden", browser.tabs.quests.slider.shown == false, browser.tabs.quests.slider.shown)

do
  -- the earlier blocks shrank the quest table, so give it something to overflow
  local saved = env.pfDB.quests.loc
  local savedFav = env.pfBrowser_fav.quests
  env.pfBrowser_fav.quests = {}
  local pool = {}
  for i = 1, 50 do pool[i] = { T = "Pool " .. i } end
  env.pfDB.quests.loc = pool
  browser.input:SetText("")
  if browser.Search then browser:Search("") end
  browser:Select("quests")
  check("the selected tab slider is shown", browser.tabs.quests.slider.shown == true, browser.tabs.quests.slider.shown)
  check("the items slider hides with its tab", browser.tabs.items.slider.shown == false, browser.tabs.items.slider.shown)
  env.pfDB.quests.loc = saved
  env.pfBrowser_fav.quests = savedFav
  if browser.Search then browser:Search("") end
end

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
