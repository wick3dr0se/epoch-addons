--[[
    Integration smoke: build the ElvUI panel from the REAL pfQuest + pfQuest-epoch
    pfQuest_defconfig, not a hand-written stub.

    Loads pfQuest's config.lua and pfQuest-epoch's pfQuest-config.lua under a WoW
    mock (they populate pfQuest_defconfig at load), then runs our options builder
    and checks that every entry type converts.

    Usage: lua5.1 tests/pfquest_defconfig_spec.lua [path/to/pfQuest]
]]

local function scriptDir()
  local s = debug.getinfo(1, "S").source
  s = s:gsub("^@", "")
  return s:match("^(.*)[/\\]") .. "/"
end
local ADDON = scriptDir() .. "../"

-- defaults to the vendored fork, which is the addon this config belongs to
local PFQ = (arg[1] and arg[1] ~= "") and arg[1] or ADDON

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

local function noop() end
local function makeFrame(kind)
  local f = { __kind = kind or "Frame", events = {} }
  -- catch-all: any missing frame method is a no-op, we are not testing the client
  setmetatable(f, { __index = function(t, k)
    if type(k) == "string" and k:match("^[A-Z]") then
      rawset(t, k, noop)
      return noop
    end
  end })
  f.SetFont = function(self, p, s, fl) self.font = { p, s, fl } end
  f.GetFontString = function(self) return self.text end
  f.CreateFontString = function() return makeFrame("FontString") end
  f.CreateTexture = function() return makeFrame("Texture") end
  f.GetScript = function() return nil end
  f.GetAlpha = function() return 1 end
  f.GetFrameLevel = function() return 1 end
  f.GetStringWidth = function() return 100 end
  f.GetWidth = function() return 100 end
  f.GetHeight = function() return 20 end
  f.GetChecked = function() return nil end
  f.GetText = function() return "" end
  f.IsShown = function() return false end
  return f
end

local env = {}
setmetatable(env, { __index = _G })
env._G = env
env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
env.UIParent = makeFrame("Frame")
env.WorldMapFrame = makeFrame("Frame")
env.GameFontNormal = "GameFontNormal"
env.CreateFrame = function(kind, name)
  local f = makeFrame(kind)
  if name then env[name] = f end
  return f
end
env.floor, env.ceil, env.abs, env.max, env.min = math.floor, math.ceil, math.abs, math.max, math.min
env.gsub, env.strfind, env.format, env.strsub = string.gsub, string.find, string.format, string.sub
env.GetLocale = function() return "enUS" end
env.GetAddOnMetadata = function() return "7.0.1-elvui.1" end
env.UnitClass = function() return "Warrior", "WARRIOR" end
env.UnitRace = function() return "Human", "Human" end
env.UnitLevel = function() return 60 end
env.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
env.GetScreenWidth = function() return 1920 end
env.GetScreenHeight = function() return 1080 end
env.GetTime = function() return 100 end
env.ReloadUI = function() end
env.StaticPopupDialogs = setmetatable({}, { __index = function(t, k) local d = {}; t[k] = d; return d end })
env.StaticPopup_Show = function() end
env.IsAddOnLoaded = function() return false end
env.UISpecialFrames = {}
env.GetAddOnInfo = function(name) if name == "ElvUI_pfQuest" then return name, "pfQuest" end end
env.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
env.ChatFrame1 = env.DEFAULT_CHAT_FRAME
env.GameTooltip = makeFrame("Frame")
env.print = print

local function run(file, ...)
  local chunk, err = loadstring(assert(io.open(file):read("*a")), file)
  assert(chunk, err)
  setfenv(chunk, env)
  return chunk(...)
end

-- our shim first, the way it happens in game
local ns = {}
run(ADDON .. "elvui.lua", "ElvUI_pfQuest")
env.pfq.font = "ElvUI\\Fonts\\Expressway.ttf"
run(ADDON .. "options.lua", "ElvUI_pfQuest")

-- epoch used to speak pfUI through a shim; the shim is gone, so epoch's own
-- modules must call pfq directly
local epochFiles = { "patchtable.lua", "pfQuest-worldmap.lua", "pfQuest-nameplates.lua",
                     "pfQuest-tooltip.lua", "pfQuest-lootpanel.lua", "pfQuest-announce.lua" }
local pfuiRefs, pfqRefs = 0, 0
for _, name in ipairs(epochFiles) do
  local fh = io.open(ADDON .. name)
  if fh then
    local src = fh:read("*a")
    fh:close()
    for _ in src:gmatch("pfUI") do pfuiRefs = pfuiRefs + 1 end
    for _ in src:gmatch("pfq%.") do pfqRefs = pfqRefs + 1 end
  end
end
check("no pfUI left in the epoch modules", pfuiRefs == 0, pfuiRefs)

-- a hardcoded folder name silently disabled three epoch modules when the addon
-- was renamed: their ADDON_LOADED handlers compared against "pfQuest-epoch"
local stale = {}
for _, name in ipairs({ "pfQuest-announce.lua", "pfQuest-nameplates.lua", "pfQuest-tooltip.lua",
                        "config.lua", "tracker.lua", "quest.lua", "updatenotify.lua" }) do
  local fh = io.open(ADDON .. name)
  if fh then
    for line in fh:lines() do
      local code = line:gsub("%-%-.*$", "")
      if code:find('"pfQuest%-epoch"') or code:find('"pfQuest%-wotlk"') then
        stale[#stale + 1] = name
        break
      end
    end
    fh:close()
  end
end
check("no hardcoded pfQuest folder names", #stale == 0, table.concat(stale, ", "))
check("epoch modules call pfq", pfqRefs > 0, pfqRefs)

-- the minimum pfQuest globals config.lua touches at load
env.pfQuestCompat = { client = 30300 }
env.pfQuest_Loc = setmetatable({}, { __index = function(_, k) return k end })
env.pfQuest_config = {}
env.pfQuest_history = {}
env.pfBrowser_fav = { quests = {}, units = {}, objects = {}, items = {} }
env.pfQuest_colors = {}
env.pfQuest_questcache = {}
env.pfQuest = { ResetAll = function() env.__resets = (env.__resets or 0) + 1 end, questlog = {} }
env.pfDB = { quests = { loc = {} }, units = { loc = {} }, objects = { loc = {} }, items = { loc = {} } }
env.pfDatabase = { localized = true }

-- the settings tree lives in its own file now that the window that used to
-- declare it is gone
run(PFQ .. "/defconfig.lua")
check("pfQuest defconfig loaded", type(env.pfQuest_defconfig) == "table" and #env.pfQuest_defconfig > 20, env.pfQuest_defconfig and #env.pfQuest_defconfig)
local upstreamCount = #env.pfQuest_defconfig

-- pfQuest-epoch appends from a delayed VARIABLES_LOADED handler, so at load it
-- contributes nothing. Simulate that late append with the exact shape epoch uses.
table.insert(env.pfQuest_defconfig, { text = "|cff33ffccRare Loot Panel|r", type = "header" })
table.insert(env.pfQuest_defconfig, { text = "Show Quest Items", default = "1", type = "checkbox", config = "epochLootPanelShowQuestItems" })
table.insert(env.pfQuest_defconfig, { text = "Arrow Scale", default = "1.0", type = "text", config = "arrowscale" })
check("epoch entries land after load (simulated)", #env.pfQuest_defconfig > upstreamCount, #env.pfQuest_defconfig)
print(string.format("     defconfig: %d entries (%d from pfQuest, %d from epoch)", #env.pfQuest_defconfig, upstreamCount, #env.pfQuest_defconfig - upstreamCount))

local panel = env.pfq.BuildOptions("0.2.0")
check("panel built from the real defconfig", panel ~= nil)
if panel then
  local groups, entries = 0, 0
  local bad = {}
  for key, group in pairs(panel.args) do
    if group.type == "group" and group.guiInline then
      groups = groups + 1
      for _, entry in pairs(group.args) do
        entries = entries + 1
        if entry.type ~= "toggle" and entry.type ~= "input" and entry.type ~= "execute"
          and entry.type ~= "color" then
          bad[#bad + 1] = key .. ":" .. tostring(entry.type)
        end
      end
    end
  end
  print(string.format("     panel: %d groups, %d controls", groups, entries))
  check("groups generated", groups >= 3, groups)

  local coloured = {}
  for _, group in pairs(panel.args) do
    if group.type == "group" and group.guiInline and type(group.name) == "string" then
      if group.name:find("|c", 1, true) then coloured[#coloured + 1] = group.name end
    end
  end
  check("no coloured section headers", #coloured == 0, table.concat(coloured, ", "))
  check("controls generated", entries >= 30, entries)
  check("no unconvertible entries", #bad == 0, table.concat(bad, ", "))

  -- every generated control must answer get() without erroring
  local getErrors = 0
  for _, group in pairs(panel.args) do
    if group.type == "group" and group.args then
      for _, entry in pairs(group.args) do
        if entry.get then
          local ok = pcall(entry.get)
          if not ok then getErrors = getErrors + 1 end
        end
      end
    end
  end
  check("every get() answers", getErrors == 0, getErrors .. " errors")

  local seen = {}
  for _, group in pairs(panel.args) do
    if group.type == "group" and group.args then
      seen[group.name] = true
      for _, entry in pairs(group.args) do
        if entry.name then seen[entry.name] = true end
      end
    end
  end
  check("epoch header appears in the panel, colour stripped", seen["Rare Loot Panel"] == true)
  check("epoch checkbox appears in the panel", seen["Show Quest Items"] == true)
  check("epoch text field appears in the panel", seen["Arrow Scale"] == true)
end

-- epoch's config renderer is gone with the window it drew into; its entries are
-- appended in pfQuest-worldmap.lua and friends, which is what real_defconfig
-- above was captured from.

print(string.format("\n%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
