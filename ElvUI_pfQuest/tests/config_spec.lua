
--[[
    Headless check for pfQuest-epoch/config.lua, the file left behind when the
    settings window was deleted.

    The window used to do real work in its ADDON_LOADED handler:
    LoadConfig() seeds pfQuest_config from pfQuest_defconfig defaults,
    MigrateHistory() rewrites name-keyed history, saved tables are initialised
    and new characters get a clean history. All of that survives; this spec is
    what proves it, because none of it is visible in game until something is
    already broken.

    Run: lua5.1 tests/config_spec.lua
]]
local checks, failures = 0, 0
local function check(name, ok, detail)
  checks = checks + 1
  if not ok then failures = failures + 1 end
  print((ok and "  ok   " or "  FAIL ") .. name .. (detail ~= nil and (" -> " .. tostring(detail)) or ""))
end

local env = {}
setmetatable(env, { __index = function(_, k) return _G[k] end })
env._G = env

local frames = {}
local function makeFrame()
  local f = {}
  f.__scripts = {}
  f.SetScript = function(self, n, fn) self.__scripts[n] = fn end
  f.GetScript = function(self, n) return self.__scripts[n] end
  f.Hide = function(self) self.hidden = true end
  f.Show = function(self) self.hidden = false end
  f.RegisterEvent = function(self, e) self.event = e end
  f.SetSize = function() end
  f.SetPoint = function() end
  frames[#frames + 1] = f
  return f
end

env.CreateFrame = function() return makeFrame() end
env.GetLocale = function() return "enUS" end
env.GetAddOnMetadata = function(name, field) return name == "ElvUI_pfQuest" and "8.0.0-elvui.1" or nil end
env.UnitXP = function() return 500 end
env.UnitLevel = function() return 20 end
env.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
env.ReloadUI = function() end
env.StaticPopupDialogs = {}
env.StaticPopup_Show = function() end
env.YES, env.NO = "Yes", "No"
env.pfQuest_Loc = setmetatable({}, { __index = function(_, k) return k end })
env.pfQuestCompat = {}
env.pfDatabase = { GetIDByName = function() return {} end }
env.pfQuest_epochcount = { 1 }
env.pfQuest_CompletedQuestData = {}
env.pfQuest_config = { worldmapmenu = "1" }

local function run(path, addon)
  local chunk, err = loadfile(path)
  assert(chunk, err)
  setfenv(chunk, env)
  chunk(addon)
end

local ROOT = (arg and arg[1]) or (os.getenv("PFQ_ROOT") or (os.getenv("HOME") .. "/src/epoch-addons/ElvUI_pfQuest"))
run(ROOT .. "/locales.lua", "ElvUI_pfQuest")
run(ROOT .. "/defconfig.lua", "ElvUI_pfQuest")
check("defconfig declared", type(env.pfQuest_defconfig) == "table" and #env.pfQuest_defconfig > 20, env.pfQuest_defconfig and #env.pfQuest_defconfig)
run(ROOT .. "/config.lua", "ElvUI_pfQuest")
check("path points at the addon folder", env.pfQuestConfig.path == "Interface\\AddOns\\ElvUI_pfQuest", env.pfQuestConfig.path)
check("folder recorded", env.pfQuestConfig.folder == "ElvUI_pfQuest", env.pfQuestConfig.folder)
check("version read from metadata", env.pfQuestConfig.version == "8.0.0-elvui.1", env.pfQuestConfig.version)
check("reset popup registered", env.StaticPopupDialogs.PFQUEST_RESET ~= nil)

-- drive ADDON_LOADED the way 3.3.5 does
env.arg1 = "ElvUI_pfQuest"
env.event = "ADDON_LOADED"
local handler = env.pfQuestConfig:GetScript("OnEvent")
check("OnEvent registered", type(handler) == "function")
local ok, err = pcall(handler)
check("handler runs for our addon name", ok, err)

local missing = {}
for _, data in pairs(env.pfQuest_defconfig) do
  if data.config and env.pfQuest_config[data.config] == nil then missing[#missing + 1] = data.config end
end
check("every config key seeded from defconfig defaults", #missing == 0, table.concat(missing, ","))
check("existing value not overwritten", env.pfQuest_config.worldmapmenu == "1", env.pfQuest_config.worldmapmenu)
check("saved tables initialised", type(env.pfQuest_questcache) == "table" and type(env.pfBrowser_fav) == "table")

env.arg1 = "SomeOtherAddon"
local ok2 = pcall(handler)
check("handler ignores other addons", ok2)
print(string.format("\n%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
