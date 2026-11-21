-- =====================================================================
-- WFAmmoHUD – Stil
--
-- Ermittelt Farben und Schrift des gewählten UI-Stils, damit Menü und
-- HUD gleich aussehen:
--   auto       Naowh Forever, sonst EllesmereUI, sonst Standard
--   naowh      Theme/Skin und Schrift aus Naowh Forever
--   ellesmere  Akzentfarbe, Grundfarben und Schrift aus EllesmereUI
--   forever    Forever-Look (Braun/Gold), ohne weitere Addons
--   standard   dunkel mit blauem Akzent
-- =====================================================================

local ADDON, ns = ...
ns = ns or {}

local FONT_ARIALN = "Fonts\\ARIALN.TTF"
local FONT_FRIZ   = "Fonts\\FRIZQT__.TTF"
local FONT_NAOWH  = "Interface\\AddOns\\NaowhForever\\Core\\Media\\Fonts\\Naowh.ttf"

local function Hex(h)
  return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255,
           tonumber(h:sub(5, 6), 16) / 255 }
end

-- Paletten im Naowh-Schema: Hintergrund, Fläche, Linie, Text, gedämpft, Akzent
local function Pal(name, bg, panel, line, fg, muted, accent)
  return { name = name, bg = Hex(bg), panel = Hex(panel), line = Hex(line),
           fg = Hex(fg), muted = Hex(muted), accent = Hex(accent) }
end
local PAL = {
  naowh       = Pal("Standard",     "191b1d", "1e2022", "373b40", "f0f1f3", "9a9ea6", "0091ed"),
  forever     = Pal("Forever",      "11100e", "1b1916", "6e5126", "e8dab4", "9a8f7a", "ffd100"),
  midnight    = Pal("Midnight",     "0b1020", "151c30", "2a3550", "eef2ff", "9ba7c8", "5b8cff"),
  slate       = Pal("Slate",        "12161c", "1e242d", "36404d", "f0f3f5", "9aa7b4", "2bb8a8"),
  obsidian    = Pal("Obsidian",     "070708", "131417", "2b2d32", "f5f5f4", "a1a1a6", "f5a524"),
  aubergine   = Pal("Aubergine",    "130d18", "1f1626", "3a2c46", "f3eef7", "a89bb8", "b57bff"),
  forest      = Pal("Forest",       "0c1310", "162019", "2c3b31", "eef4ef", "9aae9f", "36c58a"),
  crimson     = Pal("Crimson",      "140a0c", "201316", "3d2429", "f6eff0", "ac9a9e", "ef4b56"),
  rosenoir    = Pal("Rose Noir",    "1a0b14", "27121d", "4a2438", "fdeef5", "c9a3b6", "ff5fa2"),
  cottoncandy = Pal("Cotton Candy", "1c1832", "272245", "463f70", "f8f2ff", "bbb2dc", "f78fc8"),
  classic     = Pal("Classic",      "15100b", "221a12", "4d3c26", "f4e8cc", "a89a7c", "d68e35"),
}
local PAL_KEYS = { "bg", "panel", "line", "fg", "muted", "accent" }

-- Auswahl im Menü
local STYLES = {
  { key = "auto",      name = "Automatisch" },
  { key = "naowh",     name = "Naowh Forever" },
  { key = "ellesmere", name = "EllesmereUI" },
  { key = "forever",   name = "Forever" },
  { key = "standard",  name = "Standard" },
}

local function Loaded(name)
  if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) and true or false end
  return IsAddOnLoaded and IsAddOnLoaded(name) and true or false
end

local function Mix(a, b, f)
  return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f }
end
local WHITE = { 1, 1, 1 }

local function Copy(p)
  local o = {}
  for _, k in ipairs(PAL_KEYS) do o[k] = { p[k][1], p[k][2], p[k][3] } end
  return o
end

local function LSMFont(name)
  if type(name) ~= "string" or name == "" or not LibStub then return nil end
  local LSM = LibStub("LibSharedMedia-3.0", true)
  return LSM and LSM:Fetch("font", name, true) or nil
end

-- Naowh Forever: Theme/Skin aus NaowhForeverDB.account (wie Naowh selbst)
local function NaowhStyle()
  local sv = _G.NaowhForeverDB
  local acc = type(sv) == "table" and type(sv.account) == "table" and sv.account or {}
  local isForever = acc.skin == "forever" or acc.skin == "classic"
  local p, label
  if isForever then
    p, label = Copy(PAL.forever), "Forever-Skin"
  elseif acc.themePreset == "custom" and type(acc.themeColors) == "table" then
    p, label = Copy(PAL.naowh), "eigene Farben"
    for _, k in ipairs(PAL_KEYS) do
      local c = acc.themeColors[k]
      if type(c) == "table" and tonumber(c.r) and tonumber(c.g) and tonumber(c.b) then
        p[k] = { tonumber(c.r), tonumber(c.g), tonumber(c.b) }
      end
    end
  elseif type(acc.themePreset) == "string" and PAL[acc.themePreset] then
    p, label = Copy(PAL[acc.themePreset]), "Theme " .. PAL[acc.themePreset].name
  else
    p, label = Copy(PAL.naowh), "Standard-Theme"
  end
  local font = LSMFont(acc.uiFont) or (isForever and FONT_FRIZ or FONT_NAOWH)
  return p, font, "Naowh Forever – " .. label
end

-- EllesmereUI: Akzentfarbe, Grundfarben und globale Schrift
local function EllesmereStyle()
  local E = _G.EllesmereUI or {}
  local bg = { 0.069, 0.058, 0.047 }
  if type(E.DARK_BG) == "table" and E.DARK_BG.r then bg = { E.DARK_BG.r, E.DARK_BG.g, E.DARK_BG.b } end
  local function Col(t, default) -- Farbe mit Alpha auf den Hintergrund mischen
    if type(t) ~= "table" or not t.r then return default end
    return Mix(bg, { t.r, t.g, t.b }, t.a or 1)
  end
  local accent = { 220 / 255, 167 / 255, 127 / 255 }
  if E.GetAccentColor then
    local ok, r, g, b = pcall(E.GetAccentColor)
    if ok and r then accent = { r, g, b } end
  end
  local p = {
    bg = bg,
    panel = Mix(bg, WHITE, 0.03),
    line = Mix(bg, WHITE, 0.10),
    fg = Col(E.TEXT_WHITE, { 1, 1, 1 }),
    muted = Col(E.TEXT_DIM, { 0.62, 0.62, 0.62 }),
    accent = accent,
  }
  local font
  if E.GetFontPath then
    local ok, path = pcall(E.GetFontPath)
    if ok and type(path) == "string" then font = path end
  end
  local theme
  if E.GetActiveTheme then
    local ok, th = pcall(E.GetActiveTheme)
    if ok then theme = th end
  end
  return p, font or FONT_ARIALN,
    "EllesmereUI" .. (type(theme) == "string" and (" – " .. theme) or "")
end

local function ResolveStyle(key)
  if key == "auto" then
    if Loaded("NaowhForever") then key = "naowh"
    elseif Loaded("EllesmereUI") then key = "ellesmere"
    else key = "standard" end
  end
  if key == "naowh" then
    if Loaded("NaowhForever") then return NaowhStyle() end
    return Copy(PAL.naowh), FONT_ARIALN, "Naowh Forever ist nicht geladen – Standard"
  elseif key == "ellesmere" then
    if Loaded("EllesmereUI") then return EllesmereStyle() end
    return Copy(PAL.naowh), FONT_ARIALN, "EllesmereUI ist nicht geladen – Standard"
  elseif key == "forever" then
    return Copy(PAL.forever), FONT_FRIZ, "Forever (Gold)"
  end
  return Copy(PAL.naowh), FONT_ARIALN, "Standard"
end

-- Liefert: Palette {bg, panel, line, fg, muted, accent}, Schriftpfad,
-- Beschreibung und eine Kennung (ändert sich, wenn Farben/Schrift wechseln)
function ns.GetStyle(key)
  local ok, p, font, info = pcall(ResolveStyle, key or "auto")
  if not ok or not p then
    p, font, info = Copy(PAL.naowh), FONT_ARIALN, "Standard"
  end
  font = font or FONT_ARIALN
  info = info or ""
  local parts = { font, info }
  for _, k in ipairs(PAL_KEYS) do
    parts[#parts + 1] = ("%.3f,%.3f,%.3f"):format(p[k][1], p[k][2], p[k][3])
  end
  return p, font, info, table.concat(parts, "|")
end

ns.STYLES = STYLES
ns.PAL_KEYS = PAL_KEYS
ns.Loaded = Loaded
ns.Mix = Mix
