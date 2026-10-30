--[[
    pfQuest / config.lua  (merged addon)

    The settings window is gone: every control lives in the ElvUI panel
    (ElvUI_pfQuest), and `/db config` plus the tracker's settings icon both open
    it through pfq.OpenOptions(). What used to happen inside that window's
    ADDON_LOADED handler still has to happen, though, so it lives here:

      pfQuest_defconfig   declared in defconfig.lua, seeded into pfQuest_config
      pfQuestConfig       path/version holder and a frame, because pfQuest-epoch
                          hooks its OnHide script
      history migration   old name-keyed history -> id-keyed

    The frame stays one pixel wide and is never shown. There is no window left
    to show.
]]

local addonName = ...

pfQuest_history = pfQuest_history or {}
pfQuest_colors = pfQuest_colors or {}
pfQuest_config = pfQuest_config or {}

pfQuestConfig = CreateFrame("Frame", "pfQuestConfig", UIParent)
pfQuestConfig:Hide()
pfQuestConfig:SetSize(1, 1)
pfQuestConfig:SetPoint("CENTER")

local folder = addonName or "ElvUI_pfQuest"
pfQuestConfig.folder = folder
pfQuestConfig.path = "Interface\\AddOns\\" .. folder
pfQuestConfig.version = tostring(GetAddOnMetadata and GetAddOnMetadata(folder, "Version") or "")

function pfQuestConfig:LoadConfig()
  if not pfQuest_config then pfQuest_config = {} end
  for _, data in pairs(pfQuest_defconfig) do
    if data.config and not pfQuest_config[data.config] then
      pfQuest_config[data.config] = data.default
    end
  end
end

function pfQuestConfig:MigrateHistory()
  if not pfQuest_history then return end

  local match = false

  for entry, data in pairs(pfQuest_history) do
    if type(entry) == "string" then
      for id in pairs(pfDatabase:GetIDByName(entry, "quests")) do
        pfQuest_history[id] = { 0, 0 }
        pfQuest_history[entry] = nil
        match = true
      end
    elseif data == true then
      pfQuest_history[entry] = { 0, 0 }
    elseif type(data) == "table" and not data[1] then
      pfQuest_history[entry] = { 0, 0 }
    end
  end

  if match == true then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest|r: " ..
      (pfQuest_Loc["Quest history migration completed."] or "Quest history migrated."))
  end
end

pfQuestConfig:RegisterEvent("ADDON_LOADED")
pfQuestConfig:SetScript("OnEvent", function()
  if arg1 ~= folder then return end

  pfQuestConfig:LoadConfig()
  pfQuestConfig:MigrateHistory()

  pfQuest_questcache = pfQuest_questcache or {}
  pfQuest_history = pfQuest_history or {}
  pfQuest_colors = pfQuest_colors or {}
  pfQuest_config = pfQuest_config or {}
  pfQuest_track = pfQuest_track or {}
  pfBrowser_fav = pfBrowser_fav or { ["units"] = {}, ["objects"] = {}, ["items"] = {}, ["quests"] = {} }

  -- clear quest history on new characters
  if UnitXP("player") == 0 and UnitLevel("player") == 1 then
    pfQuest_history = {}
  end

  if pfBrowserIcon and pfQuest_config["minimapbutton"] == "0" then
    pfBrowserIcon:Hide()
  end
end)
