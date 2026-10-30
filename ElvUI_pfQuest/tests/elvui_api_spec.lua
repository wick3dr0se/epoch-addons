--[[
    Headless check for the fork's ElvUI backend (pfQuest-epoch/elvui.lua).

    This is the module that replaced pfUI. It must install no pfUI table at all,
    draw with ElvUI media once ElvUI is initialised, and repaint everything that
    was created before that point.

    Run: lua5.1 tests/elvui_api_spec.lua
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
  local f = { __kind = kind or "Frame", events = {} }
  function f:SetBackdrop(t) self.backdrop = t end
  function f:SetBackdropColor(r, g, b, a) self.bgColor = { r, g, b, a } end
  function f:SetBackdropBorderColor(r, g, b, a) self.border = { r, g, b, a } end
  function f:GetFrameLevel() return 3 end
  function f:SetFrameLevel() end
  function f:CreateTexture() local t = makeFrame("Texture"); t.SetAllPoints = function() end; return t end
  function f:CreateFontString() local t = makeFrame("FontString")
    t.SetFont = function(self, p, s, fl) self.font = { p, s, fl } end
    t.SetPoint = function() end
    return t
  end
  -- 3.3.5 Buttons have no SetFont; only font strings do
  if kind == "FontString" then
    function f:SetFont(p, s, fl) self.font = { p, s, fl } end
  end
  function f:SetPoint() end
  function f:SetAllPoints() end
  function f:SetWidth() end
  function f:SetHeight() end
  function f:SetAlpha(a) self.alpha = a end
  function f:GetAlpha() return self.alpha or 1 end
  function f:SetTexture(...) self.tex = { ... } end
  function f:SetVertexColor(...) self.vertex = { ... } end
  function f:SetText() end
  function f:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a } end
  function f:SetNormalTexture() end
  function f:SetHighlightTexture() end
  function f:SetPushedTexture() end
  function f:SetDisabledTexture() end
  function f:GetScript(k) return self["script_" .. k] end
  function f:SetScript(k, fn) self["script_" .. k] = fn end
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterAllEvents() self.events = {} end
  function f:GetFontString()
    if not self.text then self.text = makeFrame("FontString") end
    return self.text
  end
  function f:SetFontString(t) self.text = t end
  function f:GetThumbTexture()
    if not self.thumb then self.thumb = makeFrame("Texture") end
    return self.thumb
  end
  function f:GetHeight() return self.height or 100 end
  function f:GetVerticalScroll() return self.scroll or 0 end
  function f:GetVerticalScrollRange() return self.range or 0 end
  function f:SetVerticalScroll(v) self.scroll = v end
  function f:SetMinMaxValues(a, b) self.min, self.max = a, b end
  function f:SetValue(v) self.value = v end
  function f:SetThumbTexture(t) self.thumbTex = t end
  function f:EnableMouseWheel() end
  function f:SetOrientation() end
  function f:SetScrollChild(c) self.child = c end
  function f:GetScale() return 1 end
  function f:GetCenter() return 100, 100 end
  function f:GetLeft() return 50 end
  function f:GetRight() return 150 end
  function f:GetTop() return 150 end
  function f:GetBottom() return 50 end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  frames[#frames + 1] = f
  return f
end

local env = {}
setmetatable(env, { __index = _G })
env._G = env
env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
env.GetScreenWidth = function() return 1920 end
env.GetScreenHeight = function() return 1080 end
env.UnitClass = function() return "Warrior", "WARRIOR" end
env.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
env.CreateFrame = function(kind) return makeFrame(kind) end
env.floor, env.ceil, env.abs = math.floor, math.ceil, math.abs
env.gsub, env.strfind, env.format = string.gsub, string.find, string.format
env.GetMinimapShape = function() return "SQUARE" end
env.print = function() end

-- ElvUI present, but not initialised yet: media exists only after login, which
-- is exactly the situation the addon has to survive
-- ElvUI's table exists at load but media is only set during E:Initialize()
env.ElvUI = { { Border = 1 } }
local ELVUI_MEDIA = {
  blankTex = "ElvUI\\Media\\Textures\\Blank",
  normFont = "ElvUI\\Fonts\\Expressway.ttf",
  bordercolor = { 1, 1, 1, 0.35 },
  backdropfadecolor = { 0.06, 0.06, 0.06, 0.8 },
}

local chunk = assert(loadstring(assert(io.open(FORK .. "elvui.lua"):read("*a"))))
setfenv(chunk, env)
chunk("ElvUI_pfQuest")

local pfq = env.pfq
check("pfq module installed", type(pfq) == "table")
check("no pfUI table created", env.pfUI == nil)

print("== before login (fallbacks) ==")
check("font falls back before ElvUI inits", pfq.font == "Fonts\\FRIZQT__.TTF", pfq.font)
local early = env.CreateFrame("Frame")
pfq.CreateBackdrop(early)
check("early backdrop uses the fallback texture", early.backdrop.bgFile == "Interface\\Buttons\\WHITE8X8", early.backdrop.bgFile)

print("== login repaints what already exists ==")
-- the module's own PLAYER_ENTERING_WORLD handler
local ev
for _, f in ipairs(frames) do
  if f.events["PLAYER_ENTERING_WORLD"] then ev = f end
end
check("module listens for PLAYER_ENTERING_WORLD", ev ~= nil)
env.ElvUI[1].media = ELVUI_MEDIA
env.event = "PLAYER_ENTERING_WORLD"
env.this = ev
ev.script_OnEvent()
check("font switched to the ElvUI font", pfq.font == "ElvUI\\Fonts\\Expressway.ttf", pfq.font)
check("early backdrop repainted with ElvUI texture", early.backdrop.bgFile == "ElvUI\\Media\\Textures\\Blank", early.backdrop.bgFile)
check("minimap shape read from ElvUI", pfq.minimap == true)

print("== contracts the addon calls ==")
local frame = env.CreateFrame("Frame")
pfq.CreateBackdrop(frame)
check("backdrop bg color from ElvUI", math.abs(frame.bgColor[1] - 0.06) < 0.001)
check("backdrop border color from ElvUI", math.abs(frame.border[4] - 0.35) < 0.001)

local btn = env.CreateFrame("Button")
pfq.SkinButton(btn)
check("button font applied", btn.text.font[1] == "ElvUI\\Fonts\\Expressway.ttf")
check("hover scripts installed", type(btn.script_OnEnter) == "function" and type(btn.script_OnLeave) == "function")
btn.script_OnEnter()
check("hover border uses pfQuest mint", math.abs(btn.border[1] - 0.2) < 0.01 and math.abs(btn.border[3] - 0.8) < 0.01, btn.border and btn.border[1])

-- pfQuest's teal is swapped for the accent, everything else passes through
local teal = env.CreateFrame("Button")
pfq.SetButtonFontColor(teal, 0.2, 1, 0.8, 1)
check("teal maps to the same mint", math.abs(teal.textColor[1] - 0.2) < 0.01, teal.textColor[1])
local plain = env.CreateFrame("Button")
pfq.SetButtonFontColor(plain, 1, 1, 1, 1)
check("other colors pass through", plain.textColor[1] == 1)

-- font tracking: a font set at load must follow a later pfq.font change
local label = env.CreateFrame("FontString")
pfq.Font(label, 14)
check("tracked font applied", label.font[2] == 14)
pfq.font = "ElvUI\\Fonts\\Other.ttf"
pfq.Refresh()
check("refresh re-applies the new font", label.font[1] == "ElvUI\\Fonts\\Other.ttf", label.font[1])

-- scroll frame answers both call styles pfQuest uses
-- the scroll helpers were removed when the browser grew its own row window,
-- so there is nothing left to exercise here

local pattern = pfq.SanitizePattern("fire %s")
check("pattern escaped", type(pattern) == "string" and pattern ~= "fire %s")
check("pattern cached", pfq.SanitizePattern("fire %s") == pattern)
local r, g, b, hex = pfq.GetColorGradient(0)
check("gradient returns four values", type(hex) == "string" and hex:sub(1, 2) == "|c")
check("rgbhex", pfq.rgbhex(1, 0, 0) == "|cffff0000")
check("anchor answers", type(pfq.GetBestAnchor(frame)) == "string")
local anchor, x, y = pfq.ConvertFrameAnchor(frame, "CENTER")
check("convert anchor returns anchor,x,y", anchor == "CENTER" and type(x) == "number")

print(string.format("\n%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
