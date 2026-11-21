-- =====================================================================
-- WFAmmoHUD – Einstellungsmenü
--
-- Flaches Fenster im Stil von Naowh Forever: Seitenleiste links,
-- Kopfzeile oben, Einstellungen in Abschnitten mit Schaltern und
-- Schiebereglern. Farben und Schrift werden von Naowh Forever bzw.
-- EllesmereUI übernommen (Seite "Darstellung").
-- Öffnen mit /wfhud (oder /munition), über das Addon-Menü an der
-- Minimap oder unter Optionen > AddOns.
-- =====================================================================

local ADDON, ns = ...
ns = ns or {}

-- Stil (Farben/Schrift) kommt aus Style.lua
local STYLES, Loaded, Mix = ns.STYLES, ns.Loaded, ns.Mix
local WHITE = { 1, 1, 1 }
local FONT = "Fonts\\ARIALN.TTF"
local C = {}             -- aktive Farben (wird von ApplyPalette gefüllt)
local ACCENT_HEX = "|cFF0091ED"
local styleInfo = ""     -- Beschreibung des aktiven Stils fürs Menü
local lastSig

local function ApplyPalette(p, font)
  local function A(c, a) return { c[1], c[2], c[3], a or 1 } end
  C.bg      = A(p.bg, 0.97)
  C.sidebar = A(p.panel)
  C.header  = A(p.panel)
  C.card    = A(p.panel)
  C.field   = A(p.bg)
  C.border  = A(p.line)
  C.hover   = A(Mix(p.panel, p.fg, 0.06))
  C.select  = A(p.accent, 0.16)
  C.accent  = A(p.accent)
  C.soft    = A(Mix(p.accent, WHITE, 0.33))
  C.text    = A(p.fg)
  C.muted   = A(p.muted)
  C.off     = A(Mix(p.line, WHITE, 0.03))
  C.knob    = { 1, 1, 1, 1 }
  local function B(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
  ACCENT_HEX = ("|cFF%02X%02X%02X"):format(B(p.accent[1]), B(p.accent[2]), B(p.accent[3]))
  FONT = font
end

-- Liest den gewählten Stil neu ein; hat er sich geändert, zieht das HUD mit.
local function UpdateStyle()
  local DB = ns.GetDB()
  local p, font, info, sig = ns.GetStyle(DB and DB.menuStil or "auto")
  ApplyPalette(p, font)
  styleInfo = info
  if sig ~= lastSig then
    lastSig = sig
    if ns.ApplyHUDStyle then pcall(ns.ApplyHUDStyle) end
  end
  return sig
end
UpdateStyle() -- Startwerte, bis das Menü zum ersten Mal gebaut wird

-- ---------- Bausteine ----------
local function Tex(parent, layer, col)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(col[1], col[2], col[3], col[4] or 1)
  return t
end

local function Border(f, col)
  col = col or C.border
  local top = Tex(f, "BORDER", col)
  top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
  local bottom = Tex(f, "BORDER", col)
  bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(1)
  local left = Tex(f, "BORDER", col)
  left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(1)
  local right = Tex(f, "BORDER", col)
  right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(1)
end

local function Font(parent, size, col)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(GameFontHighlightSmall) -- Rückfall, falls die Schrift fehlt
  fs:SetFont(FONT, size, "")
  col = col or C.text
  fs:SetTextColor(col[1], col[2], col[3], col[4] or 1)
  fs:SetJustifyH("LEFT")
  return fs
end

local function FlatButton(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h or 22)
  b.bg = Tex(b, "BACKGROUND", C.field)
  b.bg:SetAllPoints()
  Border(b)
  b.label = Font(b, 12)
  b.label:SetPoint("CENTER")
  b.label:SetJustifyH("CENTER")
  b.label:SetText(text)
  b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(unpack(C.hover)) end)
  b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(unpack(C.field)) end)
  b:SetScript("OnClick", onClick)
  return b
end

-- Schalter im Pillen-Stil (an = blau, Knopf rechts)
local function Toggle(parent, getter, setter)
  local tg = CreateFrame("Button", nil, parent)
  tg:SetSize(40, 20)
  tg.track = Tex(tg, "BACKGROUND", C.off)
  tg.track:SetAllPoints()
  tg.knob = Tex(tg, "ARTWORK", C.knob)
  tg.knob:SetSize(16, 16)
  function tg:Update()
    self.knob:ClearAllPoints()
    if getter() then
      self.track:SetColorTexture(unpack(C.accent))
      self.knob:SetPoint("RIGHT", self, "RIGHT", -2, 0)
    else
      self.track:SetColorTexture(unpack(C.off))
      self.knob:SetPoint("LEFT", self, "LEFT", 2, 0)
    end
  end
  tg:SetScript("OnClick", function(self)
    setter(not getter())
    self:Update()
  end)
  tg:Update()
  return tg
end

-- Schieberegler mit Zahlenfeld rechts daneben (Feld ist editierbar)
local function Slider(parent, minV, maxV, step, getter, setter)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(230, 20)

  local box = CreateFrame("EditBox", nil, holder)
  box:SetSize(40, 22)
  box:SetPoint("RIGHT")
  box:SetAutoFocus(false)
  box:SetNumeric(true)
  box:SetMaxLetters(#tostring(maxV))
  box:SetFontObject(GameFontHighlightSmall)
  box:SetFont(FONT, 12, "")
  box:SetTextColor(unpack(C.text))
  box:SetJustifyH("CENTER")
  local boxBg = Tex(box, "BACKGROUND", C.field)
  boxBg:SetAllPoints()
  Border(box)

  local s = CreateFrame("Slider", nil, holder)
  s:SetOrientation("HORIZONTAL")
  s:SetPoint("LEFT")
  s:SetPoint("RIGHT", box, "LEFT", -12, 0)
  s:SetHeight(16)
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(step)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  s:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
  local thumb = s:GetThumbTexture()
  thumb:SetSize(12, 12)
  thumb:SetVertexColor(unpack(C.knob))

  local track = Tex(s, "BACKGROUND", C.off)
  track:SetPoint("LEFT")
  track:SetPoint("RIGHT")
  track:SetHeight(4)
  local fill = Tex(s, "ARTWORK", C.accent)
  fill:SetPoint("LEFT", track, "LEFT")
  fill:SetPoint("RIGHT", thumb, "CENTER")
  fill:SetHeight(4)

  local function Clamp(v)
    v = math.floor(v / step + 0.5) * step
    return math.max(minV, math.min(maxV, v))
  end

  s:EnableMouseWheel(true)
  s:SetScript("OnMouseWheel", function(self, delta)
    self:SetValue(Clamp(self:GetValue() + delta * step))
  end)
  s:SetScript("OnValueChanged", function(self, v)
    v = Clamp(v)
    if not box:HasFocus() then box:SetText(tostring(v)) end
    if not holder.loading and v ~= getter() then setter(v) end
  end)

  local function ResetBox(self)
    self:SetText(tostring(getter()))
    self:ClearFocus()
  end
  box:SetScript("OnEnterPressed", function(self)
    local v = tonumber(self:GetText())
    if v then
      v = Clamp(v)
      s:SetValue(v)
      if v ~= getter() then setter(v) end
    end
    ResetBox(self)
  end)
  box:SetScript("OnEscapePressed", ResetBox)
  box:SetScript("OnEditFocusLost", function(self) self:SetText(tostring(getter())) end)

  function holder:Update()
    self.loading = true
    s:SetValue(getter())
    box:SetText(tostring(getter()))
    self.loading = false
  end
  holder:Update()
  return holder
end

-- Auswahl mit Pfeilen: ‹ Wert ›
local function Cycler(parent, options, getter, setter)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(230, 22)
  local function Index()
    local cur = getter()
    for i, o in ipairs(options) do
      if o.key == cur then return i end
    end
    return 1
  end
  local function Step(d)
    local i = (Index() - 1 + d) % #options + 1
    setter(options[i].key)
    if f.Update then f:Update() end
  end
  local prev = FlatButton(f, "<", 22, 22, function() Step(-1) end)
  prev:SetPoint("LEFT")
  local nxt = FlatButton(f, ">", 22, 22, function() Step(1) end)
  nxt:SetPoint("RIGHT")
  local mid = CreateFrame("Button", nil, f)
  mid:SetPoint("LEFT", prev, "RIGHT", 4, 0)
  mid:SetPoint("RIGHT", nxt, "LEFT", -4, 0)
  mid:SetHeight(22)
  Tex(mid, "BACKGROUND", C.field):SetAllPoints()
  Border(mid)
  mid:SetScript("OnClick", function() Step(1) end)
  local label = Font(mid, 12)
  label:SetPoint("CENTER")
  label:SetJustifyH("CENTER")
  function f:Update()
    label:SetText(options[Index()].name)
  end
  f:Update()
  return f
end

-- Rechtsbündiger Text als "Bedienelement" einer Zeile
local function ValueText(parent, fn)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(260, 20)
  f.text = Font(f, 13)
  f.text:SetPoint("RIGHT")
  f.text:SetJustifyH("RIGHT")
  function f:Update() self.text:SetText(fn()) end
  f:Update()
  return f
end

-- ---------- Seiten ----------
local function NewPage(parent, crumb, title, desc)
  local p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints()
  p:Hide()
  p.controls = {}

  local bc = Font(p, 11, C.muted)
  bc:SetPoint("TOPLEFT", 20, -14)
  bc:SetText("WFAmmoHUD / " .. crumb)
  local tt = Font(p, 20, C.text)
  tt:SetPoint("TOPLEFT", bc, "BOTTOMLEFT", 0, -6)
  tt:SetText(title)
  local d = Font(p, 12, C.muted)
  d:SetPoint("TOPLEFT", tt, "BOTTOMLEFT", 0, -6)
  d:SetWidth(420)
  d:SetText(desc)

  local card = CreateFrame("Frame", nil, p)
  card:SetPoint("TOPLEFT", 16, -100)
  card:SetPoint("BOTTOMRIGHT", -16, 16)
  local cbg = Tex(card, "BACKGROUND", C.card)
  cbg:SetAllPoints()
  Border(card)
  p.card = card
  p.y = -8

  function p:Track(control)
    if control.Update then table.insert(self.controls, control) end
    return control
  end

  function p:Section(text)
    local fs = Font(card, 10, C.accent)
    fs:SetPoint("TOPLEFT", 12, self.y - 6)
    fs:SetText(text)
    self.y = self.y - 22
  end

  function p:Row(label, control)
    local row = CreateFrame("Frame", nil, card)
    row:SetPoint("TOPLEFT", card, "TOPLEFT", 0, self.y)
    row:SetPoint("RIGHT", card, "RIGHT")
    row:SetHeight(28)
    local dot = Tex(row, "ARTWORK", C.accent)
    dot:SetSize(3, 3)
    dot:SetPoint("LEFT", 10, 0)
    local l = Font(row, 13)
    l:SetPoint("LEFT", 18, 0)
    l:SetText(label)
    if control then
      control:SetParent(row)
      control:ClearAllPoints()
      control:SetPoint("RIGHT", row, "RIGHT", -12, 0)
      self:Track(control)
    end
    self.y = self.y - 28
    return row
  end

  function p:Note(text)
    local fs = Font(card, 11, C.muted)
    fs:SetPoint("TOPLEFT", 18, self.y - 2)
    fs:SetPoint("RIGHT", card, "RIGHT", -12, 0)
    fs:SetText(text)
    self.y = self.y - 20
    return fs
  end

  p:SetScript("OnShow", function(self)
    for _, c in ipairs(self.controls) do c:Update() end
  end)
  return p
end

-- ---------- Hauptfenster ----------
local menu
local menuPage = 1
local menuSig          -- Stil, mit dem das aktuelle Menü gebaut wurde
local specialRegistered = false
local BuildMenu

-- Stil wechseln: Menü mit den neuen Farben neu aufbauen (gleiche Stelle, gleiche Seite)
local function RebuildMenu()
  local point, x, y
  if menu then
    local p, _, _, px, py = menu:GetPoint(1)
    point, x, y = p, px, py
    menu:Hide()
    menu = nil
  end
  UpdateStyle()
  BuildMenu(menuPage)
  if point then
    menu:ClearAllPoints()
    menu:SetPoint(point, UIParent, point, x, y)
  end
  menu:Show()
end

function BuildMenu(startPage)
  local DB = ns.GetDB()
  menuSig = UpdateStyle()

  menu = CreateFrame("Frame", "WFAmmoHUDMenu", UIParent)
  menu:SetSize(640, 490)
  menu:SetPoint("CENTER")
  menu:SetFrameStrata("DIALOG")
  menu:SetToplevel(true)
  menu:SetMovable(true)
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  menu:Hide()
  Tex(menu, "BACKGROUND", C.bg):SetAllPoints()
  Border(menu)
  if not specialRegistered then
    table.insert(UISpecialFrames, "WFAmmoHUDMenu") -- Escape schließt das Fenster
    specialRegistered = true
  end

  local function StartMove() menu:StartMoving() end
  local function StopMove() menu:StopMovingOrSizing() end

  -- Seitenleiste
  local sidebar = CreateFrame("Frame", nil, menu)
  sidebar:SetPoint("TOPLEFT", 1, -1)
  sidebar:SetPoint("BOTTOMLEFT", 1, 1)
  sidebar:SetWidth(170)
  Tex(sidebar, "BACKGROUND", C.sidebar):SetAllPoints()
  local sep = Tex(sidebar, "BORDER", C.border)
  sep:SetPoint("TOPRIGHT"); sep:SetPoint("BOTTOMRIGHT"); sep:SetWidth(1)
  sidebar:EnableMouse(true)
  sidebar:RegisterForDrag("LeftButton")
  sidebar:SetScript("OnDragStart", StartMove)
  sidebar:SetScript("OnDragStop", StopMove)

  local logo = Font(sidebar, 22)
  logo:SetPoint("TOPLEFT", 16, -16)
  logo:SetText("WFAmmo" .. ACCENT_HEX .. "HUD|r")
  local sub = Font(sidebar, 11, C.muted)
  sub:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -4)
  sub:SetText("Munitions-HUD für Jäger")

  local navLabel = Font(sidebar, 10, C.muted)
  navLabel:SetPoint("TOPLEFT", 16, -80)
  navLabel:SetText("EINSTELLUNGEN")

  local version = Font(sidebar, 10, C.muted)
  version:SetPoint("BOTTOMLEFT", 16, 12)
  local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local v = getMeta and getMeta(ADDON, "Version")
  version:SetText("v" .. (v or "?"))

  -- Inhalt rechts
  local content = CreateFrame("Frame", nil, menu)
  content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT")
  content:SetPoint("BOTTOMRIGHT", -1, 1)

  local header = CreateFrame("Frame", nil, content)
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  header:SetHeight(40)
  Tex(header, "BACKGROUND", C.header):SetAllPoints()
  local hsep = Tex(header, "BORDER", C.border)
  hsep:SetPoint("BOTTOMLEFT"); hsep:SetPoint("BOTTOMRIGHT"); hsep:SetHeight(1)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", StartMove)
  header:SetScript("OnDragStop", StopMove)

  local pages = {}

  local close = FlatButton(header, "X", 24, 22, function() menu:Hide() end)
  close:SetPoint("RIGHT", -10, 0)
  local defaults = FlatButton(header, "Standardwerte", 110, 22, function()
    for _, key in ipairs({ "absGrenze", "anteil", "groesse", "schrift", "sound",
                           "meldungen", "ruheInfo", "chatWarnung", "ammoWahl",
                           "raidCheck", "raidDauer", "raidBedarf20", "raidBedarf40" }) do
      DB[key] = ns.DEFAULTS[key]
    end
    ns.ApplyLayout()
    for _, p in ipairs(pages) do
      if p:IsShown() then p:GetScript("OnShow")(p) end
    end
    ns.Print("Einstellungen auf Standard zurückgesetzt.")
  end)
  defaults:SetPoint("RIGHT", close, "LEFT", -8, 0)
  local test = FlatButton(header, "Warnung testen", 120, 22, function() ns.TestAlert() end)
  test:SetPoint("RIGHT", defaults, "LEFT", -8, 0)

  local body = CreateFrame("Frame", nil, content)
  body:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
  body:SetPoint("BOTTOMRIGHT")

  -- ===== Seite: HUD =====
  local hud = NewPage(body, "HUD", "HUD",
    "Größe, Schrift und Position der Munitionsanzeige.")
  local enLabel = Font(hud, 13)
  local en = hud:Track(Toggle(hud,
    function() return DB.enabled end,
    function(on) ns.SetEnabled(on) end))
  en:SetPoint("TOPRIGHT", -20, -44)
  enLabel:SetPoint("RIGHT", en, "LEFT", -10, 0)
  enLabel:SetText("HUD aktiv")

  hud:Section("GRÖSSE")
  hud:Row("Icon-Größe", Slider(hud.card, 24, 96, 1,
    function() return DB.groesse end,
    function(n) DB.groesse = n; ns.ApplyLayout() end))
  hud:Row("Schriftgröße", Slider(hud.card, 10, 36, 1,
    function() return DB.schrift end,
    function(n) DB.schrift = n; ns.ApplyLayout() end))
  hud:Row("Schriftart", ValueText(hud.card, function()
    -- Dateiname der Schrift des UI-Stils (ohne Pfad und Endung)
    local name = (FONT or ""):match("([^\\/]+)$") or FONT
    return (name:gsub("%.[Tt][Tt][Ff]$", "")) .. "  ·  " .. ACCENT_HEX .. "UI-Stil|r"
  end))
  hud:Section("MUNITIONSWECHSEL")
  hud:Row("Andere Munition anzeigen", Toggle(hud.card,
    function() return DB.ammoWahl end,
    function(on) DB.ammoWahl = on; ns.Refresh() end))
  hud:Note("Weitere Pfeil-/Kugelsorten erscheinen unter dem HUD – Klick legt sie an, auch im Kampf.")
  hud:Section("POSITION")
  hud:Row("Position zurücksetzen", FlatButton(hud.card, "Zurücksetzen", 110, 22, function()
    ns.ResetPosition()
  end))
  hud:Note("Zum Verschieben das HUD einfach mit der linken Maustaste ziehen.")

  -- ===== Seite: Warnung =====
  local warn = NewPage(body, "Warnung", "Warnung",
    "Wann und wo vor knapper Munition gewarnt wird.")
  warn:Section("SCHWELLE")
  warn:Row("Absoluter Grenzwert", Slider(warn.card, 0, 500, 1,
    function() return DB.absGrenze end,
    function(n) DB.absGrenze = n; ns.Refresh() end))
  warn:Row("Anteil vom Vorrat (%)", Slider(warn.card, 0, 95, 1,
    function() return DB.anteil end,
    function(n) DB.anteil = n; ns.Refresh() end))
  warn:Note("Warnt ab: max(min(Grenzwert, voll), Anteil % von voll)")

  warn:Section("AKTUELL")
  local status = CreateFrame("Frame", nil, warn.card)
  status:SetSize(260, 20)
  status.text = Font(status, 13)
  status.text:SetPoint("RIGHT")
  status.text:SetJustifyH("RIGHT")
  function status:Update()
    local id, count, full = ns.GetStatus()
    if id then
      self.text:SetText(("%d / %d  ·  warnt ab %s%d|r"):format(
        count, full, ACCENT_HEX, ns.ComputeWarnPoint(full)))
    else
      self.text:SetText("Keine Munition ausgerüstet")
    end
  end
  warn:Row("Vorrat", status)

  warn:Section("MELDUNGEN")
  warn:Row("Im Meldungsbereich", Toggle(warn.card,
    function() return DB.meldungen end,
    function(on) DB.meldungen = on; if ns.HideAlert then ns.HideAlert() end; ns.Refresh() end))
  warn:Row("Vorrat im Ruhebereich", Toggle(warn.card,
    function() return DB.ruheInfo end,
    function(on) DB.ruheInfo = on; if ns.HideAlert then ns.HideAlert() end; ns.Refresh() end))
  warn:Row("Zusätzlich im Chat", Toggle(warn.card,
    function() return DB.chatWarnung end,
    function(on) DB.chatWarnung = on end))
  warn:Row("Warnton", Toggle(warn.card,
    function() return DB.sound end,
    function(on) DB.sound = on end))
  warn:Row("Meldungen erscheinen in", ValueText(warn.card, function()
    return ACCENT_HEX .. (ns.AlertTarget and ns.AlertTarget() or "Chat") .. "|r"
  end))

  -- ===== Seite: Raid =====
  local raid = NewPage(body, "Raid", "Raid",
    "Vorrat beim Raid-Beitritt prüfen und als Meldung anzeigen.")
  raid:Section("RAID-CHECK")
  raid:Row("Bei Raid-Beitritt prüfen", Toggle(raid.card,
    function() return DB.raidCheck end,
    function(on) DB.raidCheck = on end))
  raid:Row("Meldung sichtbar (Sek.)", Slider(raid.card, 10, 300, 5,
    function() return DB.raidDauer end,
    function(n) DB.raidDauer = n end))
  raid:Note("Auch beim Betreten einer Raid-Instanz. Nur für Jäger.")
  raid:Section("EMPFOHLENER MINDESTVORRAT")
  raid:Row("20er-Raid", Slider(raid.card, 0, 6000, 50,
    function() return DB.raidBedarf20 end,
    function(n) DB.raidBedarf20 = n end))
  raid:Row("40er-Raid", Slider(raid.card, 0, 6000, 50,
    function() return DB.raidBedarf40 end,
    function(n) DB.raidBedarf40 = n end))
  raid:Note("20er: ZG, AQ20 (8 Stapel)  ·  40er: MC, BWL, AQ40, Naxx (voller 16er-Köcher)")
  raid:Section("TEST")
  raid:Row("Raid-Check jetzt ausführen", FlatButton(raid.card, "Prüfen", 110, 22, function()
    ns.RaidCheck(true)
  end))
  raid:Note("Außerhalb einer Raid-Instanz wird mit dem 40er-Wert verglichen.")

  -- ===== Seite: Darstellung =====
  local look = NewPage(body, "Darstellung", "Darstellung",
    "Menü und HUD übernehmen Farben und Schrift von Naowh Forever oder EllesmereUI.")
  look:Section("UI-STIL (MENÜ + HUD)")
  look:Row("Stil", Cycler(look.card, STYLES,
    function() return DB.menuStil or "auto" end,
    function(key) DB.menuStil = key; RebuildMenu() end))
  look:Row("Aktiv", ValueText(look.card, function() return ACCENT_HEX .. styleInfo .. "|r" end))
  look:Note("Automatisch: Naowh Forever, sonst EllesmereUI, sonst Standard.")
  look:Section("ERKANNTE ADDONS")
  local function LoadedText(name)
    return function()
      if Loaded(name) then return ACCENT_HEX .. "geladen|r" end
      return "nicht geladen"
    end
  end
  look:Row("Naowh Forever", ValueText(look.card, LoadedText("NaowhForever")))
  look:Row("EllesmereUI", ValueText(look.card, LoadedText("EllesmereUI")))
  look:Note("Änderst du dort Theme oder Schrift, ziehen Menü und HUD beim nächsten Öffnen nach.")

  -- Status regelmäßig aktualisieren, solange das Fenster offen ist
  local acc = 0
  menu:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc >= 0.5 then
      acc = 0
      if warn:IsShown() then pcall(status.Update, status) end
    end
  end)

  -- ===== Navigation =====
  pages = { hud, warn, raid, look }
  local navButtons = {}
  local function Select(index)
    menuPage = index
    for i, p in ipairs(pages) do
      p:SetShown(i == index)
      navButtons[i]:SetSelected(i == index)
    end
  end

  local function NavButton(text, index)
    local y = -96 - (index - 1) * 26
    local b = CreateFrame("Button", nil, sidebar)
    b:SetPoint("TOPLEFT", 8, y)
    b:SetPoint("TOPRIGHT", -8, y)
    b:SetHeight(24)
    b.bg = Tex(b, "BACKGROUND", C.select)
    b.bg:SetAllPoints()
    b.hl = Tex(b, "HIGHLIGHT", { C.hover[1], C.hover[2], C.hover[3], 0.6 })
    b.hl:SetAllPoints()
    b.bar = Tex(b, "ARTWORK", C.accent)
    b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetWidth(3)
    b.label = Font(b, 13)
    b.label:SetPoint("LEFT", 12, 0)
    b.label:SetText(text)
    function b:SetSelected(sel)
      self.bg:SetShown(sel)
      self.bar:SetShown(sel)
      local col = sel and C.text or C.muted
      self.label:SetTextColor(col[1], col[2], col[3], 1)
    end
    b:SetScript("OnClick", function() Select(index) end)
    navButtons[index] = b
  end
  NavButton("HUD", 1)
  NavButton("Warnung", 2)
  NavButton("Raid", 3)
  NavButton("Darstellung", 4)

  -- Beim Öffnen die aktuelle Seite neu einlesen (Werte evtl. per Chatbefehl geändert)
  menu:SetScript("OnShow", function()
    for _, p in ipairs(pages) do
      if p:IsShown() then p:GetScript("OnShow")(p) end
    end
  end)
  Select(startPage or 1)
end

-- ---------- Öffnen / Schließen ----------
function ns.ToggleMenu()
  if not ns.GetDB() then
    ns.Print("noch nicht fertig geladen – versuch es in einem Moment erneut.")
    return
  end
  if menu and menu:IsShown() then
    menu:Hide()
    return
  end
  if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
  -- Neu bauen, wenn sich Theme/Schrift in Naowh Forever oder EllesmereUI
  -- seit dem letzten Öffnen geändert hat; sonst einfach anzeigen.
  if menu and UpdateStyle() == menuSig then
    menu:Show()
  else
    RebuildMenu()
  end
end

-- Addon-Menü an der Minimap (## AddonCompartmentFunc in der TOC)
function WFAmmoHUD_OpenMenu()
  ns.ToggleMenu()
end

-- Eintrag unter Optionen > AddOns mit Knopf zum Öffnen
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
  if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
  pcall(function()
    UpdateStyle()
    local panel = CreateFrame("Frame")
    local title = Font(panel, 20)
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("WFAmmo" .. ACCENT_HEX .. "HUD|r")
    local btn = FlatButton(panel, "Einstellungen öffnen", 160, 26, function() ns.ToggleMenu() end)
    btn:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
    local hint = Font(panel, 12, C.muted)
    hint:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -10)
    hint:SetText("Oder im Chat: /wfhud")
    local cat = Settings.RegisterCanvasLayoutCategory(panel, "WFAmmoHUD")
    Settings.RegisterAddOnCategory(cat)
  end)
end)
