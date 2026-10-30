--[[
    pfQuest / settings.lua

    The ElvUI settings page for this addon. It used to be a separate addon
    (ElvUI_pfQuest) because pfQuest and its ElvUI layer loaded as different
    addons; now that they are one addon there is nothing to bridge, so this file
    only does the lifecycle:

      /db config        wrapped so it opens the ElvUI page
      /pfq              the same page, plus `status`

    options.lua next door builds the page itself from pfQuest_defconfig.
]]

local addonName = ...

local function version()
  return tostring(GetAddOnMetadata(addonName, "Version") or "8.0.0-elvui.1")
end

-- `/db config` and the /pfquest, /shagu, /pfdb aliases all reach PFDB
local function wrapConfigSlash()
  local list = SlashCmdList
  if pfq.slashWrapped or not list or type(list.PFDB) ~= "function" then return end
  pfq.slashWrapped = true

  local original = list.PFDB
  list.PFDB = function(input)
    if (input or ""):lower():gsub("%s+", "") == "config" then
      pfq.OpenOptions()
      return
    end
    return original(input)
  end
end

local function buildOptions()
  local E = pfq.engine()
  if not E or not E.Libs or not E.Libs.EP then return false end
  if pfq.optionsBuilt then return true end
  pfq.optionsBuilt = true

  -- built when the page opens, never at login: pfQuest-epoch appends its own
  -- entries to pfQuest_defconfig from a delayed handler after
  -- PLAYER_ENTERING_WORLD, so a login-time tree misses every one of them
  E.Libs.EP:RegisterPlugin(addonName, function()
    local args = pfq.BuildOptions(version())
    if args then
      E.Options.args.pfQuest = args
    end
  end)
  return true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function()
  wrapConfigSlash()

  if not buildOptions() then
    -- ElvUI may still be initialising; retry briefly
    local retry, waited = CreateFrame("Frame"), 0
    retry:SetScript("OnUpdate", function(self, elapsed)
      waited = waited + (elapsed or 0)
      if buildOptions() or waited > 15 then
        self:SetScript("OnUpdate", nil)
      end
    end)
  end
end)

SLASH_PFRESKIN1 = "/pfq"
SlashCmdList["PFRESKIN"] = function(input)
  input = (input or ""):lower():gsub("%s+", "")

  if input == "status" then
    print("|cff33ffccpf|cffffffffQuest|r " .. version() ..
      ", ElvUI " .. (pfq.engine() and "present" or "missing") ..
      ", pfQuest " .. (pfQuest and "loaded" or "missing"))
  else
    pfq.OpenOptions()
  end
end
