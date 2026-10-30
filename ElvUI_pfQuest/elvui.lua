--[[
    pfQuest / elvui.lua

    pfQuest was written against pfUI: it called pfUI.api.* for every frame it
    owns, and shipped a fake pfUI table when pfUI was absent. This fork drops
    that entirely. There is no pfUI table anywhere in the addon; every call site
    goes through the `pfq` table below, which draws with ElvUI media.

    Two rules that the rest of the addon depends on:

    - Media is resolved at CALL time, never captured. Addon files run before
      E:Initialize(), so E.media is still nil while this file and the UI files
      execute. Fallbacks match ElvUI's own defaults, and Refresh() repaints
      everything at PLAYER_ENTERING_WORLD once the real media exists.
    - pfq.font is a plain string. Call sites that set a font directly go through
      pfq.Font(), which records the string so Refresh() can re-font it after
      login. :SetFont() called by hand would keep the fallback font forever.

    Layout is pfQuest's. This module owns material and color only.
]]

local pfq = {}
_G.pfq = pfq

local FALLBACK_FONT = STANDARD_TEXT_FONT
local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"

pfq.fontSize = 12
pfq.font = FALLBACK_FONT

-- shape/feature flags the addon asks about. pfUI used to answer these; with
-- ElvUI the minimap shape comes from GetMinimapShape(), resolved at login.
pfq.minimap = false
pfq.uf = false
pfq.chat = nil

local backdrops = setmetatable({}, { __mode = "k" })
local buttons = setmetatable({}, { __mode = "k" })
local fonts = setmetatable({}, { __mode = "k" })
local thumbst = setmetatable({}, { __mode = "k" })
pfq.backdrops = backdrops
pfq.buttons = buttons
pfq.fonts = fonts
pfq.scrollThumbs = thumbst

---------------------------------------------------------------------------
-- media
---------------------------------------------------------------------------

-- ElvUI global is { E, L, V, P, G }; E carries media and Border
function pfq.engine()
  local ui = _G.ElvUI
  if type(ui) == "table" then
    return ui[1] or ui
  end
end

local function blankTex()
  local E = pfq.engine()
  return (E and E.media and E.media.blankTex) or WHITE8X8
end
pfq.blankTex = blankTex

local function edgeSize()
  local E = pfq.engine()
  local n = tonumber(E and (E.Border or E.mult)) or 1
  return n < 1 and 1 or n
end

local function bgColor()
  local E = pfq.engine()
  local c = E and E.media and E.media.backdropfadecolor
  if type(c) == "table" then
    return c[1] or 0.06, c[2] or 0.06, c[3] or 0.06, c[4] or 0.8
  end
  return 0.06, 0.06, 0.06, 0.8
end

local function borderColor()
  local E = pfq.engine()
  local c = E and E.media and E.media.bordercolor
  if type(c) == "table" then
    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 0.25
  end
  return 1, 1, 1, 0.25
end

-- The identity colour is fixed, like every other addon in this repo: one pastel
-- per addon, not a setting. pfQuest uses its own mint.
local ACCENT = { r = 0.2, g = 1, b = 0.8 } -- #33ffcc, pfQuest mint

function pfq.accent()
  return ACCENT.r, ACCENT.g, ACCENT.b
end

local function resolveFrame(f)
  if type(f) == "string" then
    return _G[f]
  end
  return f
end
pfq.resolveFrame = resolveFrame

function pfq.paint(f, alpha)
  if not f or not f.SetBackdropColor then return end
  local r, g, b, a = bgColor()
  f:SetBackdropColor(r, g, b, alpha or a)
  local br, bg, bb, ba = borderColor()
  f:SetBackdropBorderColor(br, bg, bb, ba)
end

---------------------------------------------------------------------------
-- fonts (tracked so they can follow ElvUI after login)
---------------------------------------------------------------------------

function pfq.Font(fontstring, size, flags)
  if not fontstring or not fontstring.SetFont then return end
  size = tonumber(size) or pfq.fontSize
  fontstring:SetFont(pfq.font, size, flags or "OUTLINE")
  fonts[fontstring] = { size = size, flags = flags or "OUTLINE" }
end

---------------------------------------------------------------------------
-- frames and buttons
---------------------------------------------------------------------------

function pfq.CreateBackdrop(f, inset, legacy, transp)
  f = resolveFrame(f)
  if not f or not f.SetBackdrop then return end

  local tex = blankTex()
  f:SetBackdrop({
    bgFile = tex,
    edgeFile = tex,
    edgeSize = edgeSize(),
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  pfq.paint(f, transp)
  -- remember the alpha so Refresh() can rebuild the backdrop (texture included)
  -- without losing per-frame transparency
  backdrops[f] = transp or false
end

function pfq.SetButtonFont(button, font, size, flags)
  button = resolveFrame(button)
  if not button then return end
  size = tonumber(size) or pfq.fontSize
  flags = flags or "OUTLINE"

  if button.SetFont then
    -- vanilla/tbc style button, font lives on the button itself
    button:SetFont(pfq.font, size, flags)
  else
    local text = button.GetFontString and button:GetFontString()
    if not text and button.CreateFontString then
      text = button:CreateFontString(nil, "OVERLAY")
      text:SetPoint("CENTER", button, "CENTER", 0, 0)
      if button.SetFontString then
        button:SetFontString(text)
      end
    end
    if text then
      pfq.Font(text, size, flags)
    end
  end

  buttons[button] = { size = size, flags = flags }
end

function pfq.SkinButton(button, cr, cg, cb)
  button = resolveFrame(button)
  if not button then return end

  if not (cr and cg and cb) then
    local _, class = UnitClass("player")
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then
      cr, cg, cb = c.r, c.g, c.b
    end
  end

  pfq.CreateBackdrop(button, nil, true)
  button:SetNormalTexture(nil)
  button:SetHighlightTexture(nil)
  button:SetPushedTexture(nil)
  button:SetDisabledTexture(nil)

  -- pfQuest's handlers read the 3.3.5 globals (this/arg1), so call them with no
  -- arguments, the way pfUI did
  local enter = button:GetScript("OnEnter")
  local leave = button:GetScript("OnLeave")

  button:SetScript("OnEnter", function()
    if enter then enter() end
    local ar, ag, ab = pfq.accent()
    button:SetBackdropBorderColor(ar, ag, ab, 1)
  end)
  button:SetScript("OnLeave", function()
    if leave then leave() end
    pfq.paint(button)
  end)

  pfq.SetButtonFont(button, pfq.font, pfq.fontSize, "OUTLINE")
end

function pfq.SetButtonFontColor(button, r, g, b, a)
  button = resolveFrame(button)
  if not button then return end

  -- pfQuest paints its "active" state with its own teal (.2,1,.8) in several
  -- places. Swap that exact colour for the accent so there is one identity
  -- colour instead of two.
  if r and g and b and math.abs(r - 0.2) < 0.01 and math.abs(g - 1) < 0.01 and math.abs(b - 0.8) < 0.01 then
    r, g, b = pfq.accent()
  end

  if button.SetTextColor then
    button:SetTextColor(r, g, b, a)
  else
    local text = button.GetFontString and button:GetFontString()
    if text then
      text:SetTextColor(r, g, b, a)
    end
  end
end

---------------------------------------------------------------------------
-- small helpers pfQuest calls
---------------------------------------------------------------------------

local sanitizeCache = {}
function pfq.SanitizePattern(pattern, dbg)
  if not pattern then return nil end
  local cached = sanitizeCache[pattern]
  if cached then return cached end

  local ret = pattern
  ret = gsub(ret, "([%+%-%*%(%)%?%[%]%^])", "%%%1")
  ret = gsub(ret, "%d%$", "")
  ret = gsub(ret, "(%%%a)", "%(%1+%)")
  ret = gsub(ret, "%%s%+", ".+")
  ret = gsub(ret, "%(.%+%)%(%%d%+%)", "%(.-%)%(%%d%+%)")

  sanitizeCache[pattern] = ret
  return ret
end

function pfq.round(input, places)
  places = places or 0
  if type(input) == "number" and type(places) == "number" then
    local pow = 1
    for _ = 1, places do
      pow = pow * 10
    end
    return floor(input * pow + 0.5) / pow
  end
end

local hexCache = {}
function pfq.rgbhex(r, g, b, a)
  local key
  if type(r) == "table" then
    local tr, tg, tb, ta
    if r.r then
      tr, tg, tb, ta = r.r, r.g, r.b, r.a or 1
    elseif #r >= 3 then
      tr, tg, tb, ta = r[1], r[2], r[3], r[4] or 1
    end
    if tr and tg and tb and ta then
      key = string.format("%s%s%s%s", tr, tg, tb, ta)
      if hexCache[key] == nil then
        hexCache[key] = string.format("|c%02x%02x%02x%02x", ta * 255, tr * 255, tg * 255, tb * 255)
      end
    end
  elseif tonumber(r) and g and b then
    a = a or 1
    key = string.format("%s%s%s%s", r, g, b, a)
    if hexCache[key] == nil then
      hexCache[key] = string.format("|c%02x%02x%02x%02x", a * 255, r * 255, g * 255, b * 255)
    end
  end
  return hexCache[key] or ""
end

-- route arrow color by direction: a signal colour, not chrome, so the accent
-- must not touch it
local gradients = {}
function pfq.GetColorGradient(perc)
  perc = perc > 1 and 1 or perc
  perc = perc < 0 and 0 or perc
  perc = floor(perc * 100) / 100

  local cached = gradients[perc]
  if not cached then
    local r1, g1, b1, r2, g2, b2
    local p = perc
    if p <= 0.5 then
      p = p * 2
      r1, g1, b1 = 1, 0, 0
      r2, g2, b2 = 1, 1, 0
    else
      p = p * 2 - 1
      r1, g1, b1 = 1, 1, 0
      r2, g2, b2 = 0, 1, 0
    end
    cached = {
      r = pfq.round(r1 + (r2 - r1) * p, 4),
      g = pfq.round(g1 + (g2 - g1) * p, 4),
      b = pfq.round(b1 + (b2 - b1) * p, 4),
    }
    cached.h = pfq.rgbhex(cached.r, cached.g, cached.b)
    gradients[perc] = cached
  end
  return cached.r, cached.g, cached.b, cached.h
end

-- the tracker saves its position as "anchor, x, y" relative to the nearest
-- screen edge; same math the addon has always used so saved positions hold
function pfq.GetBestAnchor(frame)
  local scale = frame:GetScale()
  local x, y = frame:GetCenter()
  if not x or not y then return end

  local a = GetScreenWidth() / scale / 3
  local b = GetScreenWidth() / scale / 3 * 2
  local c = GetScreenHeight() / scale / 3 * 2
  local d = GetScreenHeight() / scale / 3

  if x < a and y > c then
    return "TOPLEFT"
  elseif x > a and x < b and y > c then
    return "TOP"
  elseif x > b and y > c then
    return "TOPRIGHT"
  elseif x < a and y > d and y < c then
    return "LEFT"
  elseif x > a and x < b and y > d and y < c then
    return "CENTER"
  elseif x > b and y > d and y < c then
    return "RIGHT"
  elseif x < a and y < d then
    return "BOTTOMLEFT"
  elseif x > a and x < b and y < d then
    return "BOTTOM"
  elseif x > b and y < d then
    return "BOTTOMRIGHT"
  end
end

function pfq.ConvertFrameAnchor(frame, anchor)
  local scale = frame:GetScale()
  local x, y

  if anchor == "CENTER" then
    x, y = frame:GetCenter()
    x, y = x - GetScreenWidth() / 2 / scale, y - GetScreenHeight() / 2 / scale
  elseif anchor == "TOPLEFT" then
    x, y = frame:GetLeft(), frame:GetTop() - GetScreenHeight() / scale
  elseif anchor == "TOP" then
    x = frame:GetCenter()
    x, y = x - GetScreenWidth() / 2 / scale, frame:GetTop() - GetScreenHeight() / scale
  elseif anchor == "TOPRIGHT" then
    x, y = frame:GetRight() - GetScreenWidth() / scale, frame:GetTop() - GetScreenHeight() / scale
  elseif anchor == "RIGHT" then
    _, y = frame:GetCenter()
    x, y = frame:GetRight() - GetScreenWidth() / scale, y - GetScreenHeight() / 2 / scale
  elseif anchor == "BOTTOMRIGHT" then
    x, y = frame:GetRight() - GetScreenWidth() / scale, frame:GetBottom()
  elseif anchor == "BOTTOM" then
    x = frame:GetCenter()
    x, y = x - GetScreenWidth() / 2 / scale, frame:GetBottom()
  elseif anchor == "BOTTOMLEFT" then
    x, y = frame:GetLeft(), frame:GetBottom()
  elseif anchor == "LEFT" then
    _, y = frame:GetCenter()
    x, y = frame:GetLeft(), y - GetScreenHeight() / 2 / scale
  end

  return anchor, pfq.round(x, 2), pfq.round(y, 2)
end

---------------------------------------------------------------------------
-- scroll frame (browser result list)
---------------------------------------------------------------------------

local function tintThumb(thumb)
  if not thumb then return end
  local r, g, b = pfq.accent()
  thumb:SetTexture(r, g, b, 0.6)
end

function pfq.tintScrollThumbs()
  for thumb in pairs(thumbst) do
    tintThumb(thumb)
  end
end

function pfq.CreateScrollFrame(name, parent)
  local f = CreateFrame("ScrollFrame", name, parent)

  local slider = CreateFrame("Slider", nil, f)
  slider:SetOrientation("VERTICAL")
  slider:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 0)
  slider:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, 0)
  slider:SetWidth(4)
  slider:SetThumbTexture(blankTex())

  local thumb = slider:GetThumbTexture()
  thumb:SetWidth(4)
  thumb:SetHeight(48)
  thumbst[thumb] = true
  tintThumb(thumb)

  f.slider = slider
  f.slider.thumb = thumb

  local wiring = false
  slider:SetScript("OnValueChanged", function(self, value)
    if wiring then return end
    wiring = true
    f:SetVerticalScroll(value)
    f.UpdateScrollState()
    wiring = false
  end)

  -- called both as f.UpdateScrollState() and f:UpdateScrollState()
  f.UpdateScrollState = function(self)
    self = self or f
    local range = self:GetVerticalScrollRange()
    slider:SetMinMaxValues(0, range)
    slider:SetValue(self:GetVerticalScroll())

    local height = self:GetHeight()
    local ratio = height / (height + range)

    if ratio < 1 then
      local size = floor(height * ratio)
      thumb:SetHeight(size > 12 and size or 12)
      slider:Show()
    else
      slider:Hide()
    end
  end

  f.Scroll = function(self, step)
    self = self or f
    local current = self:GetVerticalScroll()
    local maximum = self:GetVerticalScrollRange()
    local target = current - (step or 0)

    if target >= maximum then
      self:SetVerticalScroll(maximum)
    elseif target <= 0 then
      self:SetVerticalScroll(0)
    else
      self:SetVerticalScroll(target)
    end

    self:UpdateScrollState()
  end

  f:EnableMouseWheel(1)
  f:SetScript("OnMouseWheel", function(self, delta)
    self:Scroll((delta or 0) * 10)
  end)

  return f
end

function pfq.CreateScrollChild(name, parent)
  local f = CreateFrame("Frame", name, parent)
  f:SetWidth(1)
  f:SetHeight(1)
  f:SetAllPoints(parent)
  parent:SetScrollChild(f)

  -- pfUI re-synced the scrollbar every frame. Rows only change on search, so
  -- 10Hz is invisible and saves a per-frame full scroll update while open.
  local elapsed = 0
  f:SetScript("OnUpdate", function(self, delta)
    elapsed = elapsed + (delta or 0)
    if elapsed < 0.1 then return end
    elapsed = 0
    local scroll = self:GetParent()
    if scroll and scroll.UpdateScrollState then
      scroll:UpdateScrollState()
    end
  end)

  return f
end

---------------------------------------------------------------------------
-- repaint after ElvUI media exists
---------------------------------------------------------------------------

function pfq.Refresh()
  -- rebuild, not just recolor: backdrops created before E:Initialize() are
  -- holding the fallback texture
  for f, transp in pairs(backdrops) do
    pfq.CreateBackdrop(f, nil, nil, transp or nil)
  end

  for fs, data in pairs(fonts) do
    if fs.SetFont then
      fs:SetFont(pfq.font, data.size or pfq.fontSize, data.flags or "OUTLINE")
    end
  end

  for button in pairs(buttons) do
    if type(button) == "table" then
      pfq.SetButtonFont(button, pfq.font, (buttons[button] or {}).size, (buttons[button] or {}).flags)
    end
  end

  pfq.tintScrollThumbs()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function()
  local E = pfq.engine()
  if E and E.media then
    pfq.font = E.media.normFont or FALLBACK_FONT
  end

  -- ElvUI defines GetMinimapShape; pfQuest used to ask pfUI whether the
  -- minimap was square
  if _G.GetMinimapShape then
    pfq.minimap = (_G.GetMinimapShape() == "SQUARE") and true or false
  end

  pfq.Refresh()
  this:UnregisterAllEvents()
end)

---------------------------------------------------------------------------
-- popup menu (shared by the world map dropdown and the quest log language button)
---------------------------------------------------------------------------

-- One list widget for every menu in the addon, so no Blizzard
-- UIDropDownMenuTemplate is left anywhere. items are
--   { text = , selected = function() return bool end, click = function() end }
function pfq.Popup(anchor, items, width)
  local menu = _G.pfQuestPopup
  if not menu then
    menu = CreateFrame("Frame", "pfQuestPopup", UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:Hide()
    pfq.CreateBackdrop(menu)
    menu.rows = {}

    -- clicking anywhere else closes it
    menu:SetScript("OnShow", function(self)
      if not self.catcher then
        local catcher = CreateFrame("Frame", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:EnableMouse(true)
        catcher:SetFrameStrata("FULLSCREEN")
        catcher:SetScript("OnMouseDown", function() menu:Hide() end)
        self.catcher = catcher
      end
      self.catcher:Show()
    end)
    menu:SetScript("OnHide", function(self)
      if self.catcher then self.catcher:Hide() end
    end)
  end

  width = width or 170
  menu:SetWidth(width)
  menu:SetHeight(#items * 20 + 8)

  local accentR, accentG, accentB = pfq.accent()

  for index, item in ipairs(items) do
    local row = menu.rows[index]
    if not row then
      row = CreateFrame("Button", nil, menu)
      row:SetHeight(20)
      row:SetPoint("TOPLEFT", 4, -4 - (index - 1) * 20)
      row:SetPoint("TOPRIGHT", -4, -4 - (index - 1) * 20)

      row.bg = row:CreateTexture(nil, "BACKGROUND")
      row.bg:SetAllPoints()
      row.bg:SetTexture(0, 0, 0, 0)

      row.label = row:CreateFontString(nil, "OVERLAY")
      pfq.Font(row.label, pfq.fontSize)
      row.label:SetPoint("LEFT", 6, 0)

      row:SetScript("OnEnter", function(self)
        local r, g, b = pfq.accent()
        self.bg:SetTexture(r, g, b, 0.15)
      end)
      row:SetScript("OnLeave", function(self)
        self.bg:SetTexture(0, 0, 0, 0)
      end)

      menu.rows[index] = row
    end

    row.label:SetText(item.text or "")
    if item.selected and item.selected() then
      row.label:SetTextColor(accentR, accentG, accentB, 1)
    else
      row.label:SetTextColor(1, 1, 1, 0.8)
    end

    row:SetScript("OnClick", function()
      menu:Hide()
      if item.click then item.click() end
    end)

    row:Show()
  end

  for index = #items + 1, #menu.rows do
    menu.rows[index]:Hide()
  end

  menu:ClearAllPoints()
  menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
  menu:Show()

  return menu
end
