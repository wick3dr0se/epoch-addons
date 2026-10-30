--[[
    pfQuest / options.lua

    All settings land in the ElvUI panel. pfQuest's own configuration window is
    gone (/db config opens this page), so there is one place to configure the
    addon instead of two.

    pfQuest already describes its whole option set as data: pfQuest_defconfig is
    a dense array of { text, type, config, default, func } built in its
    config.lua, and pfQuest-epoch appends its own entries to the same table with
    table.insert. Walking that array gives the union of both addons' options
    without hardcoding a single label, and it survives upstream updates because
    the shape is what pfQuest's own window consumes.

    Value semantics are pfQuest's, not ElvUI's: checkbox state is the string
    "1" or "0" in pfQuest_config, text fields are strings, and any change is
    applied by pfQuest:ResetAll() which rebuilds the map and tracker.
]]

local addonName = ...

local function cfg()
  return _G.pfQuest_config
end

local function isOn(key)
  local v = cfg()[key]
  return v == "1" or v == 1 or v == true
end

local function apply()
  local pfQuest = _G.pfQuest
  if pfQuest and pfQuest.ResetAll then
    pfQuest:ResetAll()
  end
end

local function setOn(key, value)
  cfg()[key] = value
  apply()
end

-- one group per pfQuest header, in the order pfQuest lists them
-- pfQuest-epoch embeds |cff33ffcc...|r in its header labels, so those sections
-- rendered mint while pfQuest's own headers used AceConfig's default. Strip the
-- codes so every header looks the same.
local function plain(text)
  if type(text) ~= "string" then return text end
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function pfQuestArgs(startOrder)
  local def = _G.pfQuest_defconfig
  if type(def) ~= "table" then return nil, startOrder end

  local groups = {}
  local groupCount = 0
  local order = startOrder or 0
  local current

  local function newGroup(name)
    groupCount = groupCount + 1
    current = { order = groupCount, type = "group", name = name, guiInline = true, args = {} }
    groups["group" .. groupCount] = current
  end

  for _, data in ipairs(def) do
    if data.type then
      if data.type == "header" then
        newGroup(plain(data.text))
      else
        if not current then
          newGroup("pfQuest")
        end

        order = order + 1
        local key = "opt" .. order
        local entry

        if data.type == "checkbox" and data.config then
          entry = {
            order = order,
            type = "toggle",
            name = data.text,
            get = function() return isOn(data.config) end,
            set = function(_, value) setOn(data.config, value and "1" or "0") end,
          }
        elseif data.type == "text" and data.config then
          entry = {
            order = order,
            type = "input",
            name = data.text,
            get = function()
              local value = cfg()[data.config]
              if value == nil then return "" end
              return tostring(value)
            end,
            set = function(_, value) setOn(data.config, tostring(value)) end,
          }
        elseif data.type == "button" and data.func then
          entry = {
            order = order,
            type = "execute",
            name = data.text,
            func = data.func,
          }
        end

        if entry then
          current.args[key] = entry
        end
      end
    end
  end

  return groups, groupCount
end

-- returns a full AceConfig group, or nil when pfQuest is not installed
function pfq.BuildOptions(version)
  if not _G.pfQuest or type(_G.pfQuest_defconfig) ~= "table" then
    return nil
  end

  local args = {
    header = { order = 1, type = "header", name = "|cff33ffccpfQuest|r" },
    desc = {
      order = 2,
      type = "description",
      name = "Quest helper and database for Project Epoch. Every option it has is on this page.\n",
    },
    version = { order = 3, type = "description", name = "|cff33ffccVersion " .. tostring(version) .. "|r" },
    spacer = { order = 4, type = "description", name = "" },
  }

  local groups, count = pfQuestArgs(12)
  if groups then
    for key, group in pairs(groups) do
      group.order = (group.order or 1) + 11
      args[key] = group
    end
  end

  return {
    order = 53,
    type = "group",
    name = "|cff33ffccpfQuest|r",
    args = args,
  }
end

function pfq.OpenOptions()
  local E = pfq.engine()
  if not E then return false end

  if E.ToggleOptionsUI then
    E:ToggleOptionsUI("pfQuest")
  else
    if E.ToggleOptions then E:ToggleOptions() end
    if E.Libs and E.Libs.ACD then
      E.Libs.ACD:SelectGroup("ElvUI", "pfQuest")
    end
  end

  return true
end
