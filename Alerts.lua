-- =====================================================================
-- WFAmmoHUD – Meldungen
--
-- Zeigt Warnungen (Munition knapp / aufgebraucht) und im Ruhebereich
-- (Gasthaus, Hauptstadt) den aktuellen Vorrat als Meldung an – nicht
-- im Chat.
--
-- Ist Naowh Forever geladen, hängt sich die Meldung in dessen
-- Meldungsbereich ("Alerts"), also dorthin, wo auch die Auffüll-
-- Erinnerung, der Begleiter-Tracker, Haltbarkeit usw. erscheinen, und
-- übernimmt deren Schrift und Hintergrund. Verschieben dann über den
-- HUD-Editor von Naowh Forever.
-- Ohne Naowh Forever erscheint die Meldung an derselben Stelle
-- (Bildschirmmitte, etwas oberhalb) im gewählten UI-Stil.
-- =====================================================================

local ADDON, ns = ...
ns = ns or {}

local TITLE_SIZE, TEXT_SIZE, TITLE_GROW = 22, 16, 6
local TITLE_TOP, TEXT_GAP = 4, 4
local PAD_W, PAD_H = 16, 12
local FLASH_LOOPS, FLASH_ALPHA, FLASH_TIME = 6, 0.35, 0.6
local STACK_ORDER = 4.5 -- direkt über Naowhs Auffüll-Erinnerung (4)
local LABEL = "WFAmmoHUD – Munition"
local NAOWH_PAGE = "QoL/Loot & Items"
local NAOWH_CARD = NAOWH_PAGE .. ":restock"

local ORANGE = { 1, 0.66, 0.20 }
local RED    = { 1, 0.30, 0.30 }

local alert, flash
local viaNaowh = false
local ready = false        -- erst nach dem Einloggen bauen (Naowh muss fertig sein)
local holdUntil = 0        -- Test-/Kurzmeldung bleibt bis hierhin stehen
local noneSince            -- seit wann keine Munition gefunden wird
local NONE_DELAY = 8       -- Sekunden, bevor "keine Munition" erscheint
local playerClass = select(2, UnitClass("player"))

local function NF()
  local nf = _G.NaowhForever
  if type(nf) == "table" and type(nf.AlertStack) == "function" then return nf end
end

local function OnFlashLoop(self)
  self.loops = (self.loops or 0) + 1
  if self.loops >= FLASH_LOOPS then self:Stop() end
end

local function Build()
  alert = CreateFrame("Frame", "WFAmmoHUDAlert", UIParent)
  alert:SetMovable(true)
  alert:SetClampedToScreen(true)
  alert:SetSize(300, 50)
  alert:Hide()

  alert.title = alert:CreateFontString(nil, "OVERLAY")
  alert.title:SetFontObject(GameFontNormalLarge)
  alert.title:SetPoint("TOP", 0, -TITLE_TOP)
  alert.text = alert:CreateFontString(nil, "OVERLAY")
  alert.text:SetFontObject(GameFontHighlight)
  alert.text:SetPoint("TOP", alert.title, "BOTTOM", 0, -TEXT_GAP)
  alert.text:SetJustifyH("CENTER")

  flash = alert:CreateAnimationGroup()
  flash:SetLooping("BOUNCE")
  flash:SetScript("OnLoop", OnFlashLoop)
  local pulse = flash:CreateAnimation("Alpha")
  pulse:SetFromAlpha(1)
  pulse:SetToAlpha(FLASH_ALPHA)
  pulse:SetDuration(FLASH_TIME)

  local nf = NF()
  if nf then
    viaNaowh = pcall(function()
      local Parts = nf.Shared and nf.Shared.Parts
      if Parts and Parts.HudBackdrop then
        alert.backdrop = Parts.HudBackdrop(alert, { mode = "none" })
      end
      nf.AlertStack(alert, STACK_ORDER, LABEL, NAOWH_PAGE, NAOWH_CARD)
    end)
  end
  if not viaNaowh then
    alert:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
  end
end

-- Schrift/Hintergrund: im Naowh-Bereich wie Naowhs Auffüll-Erinnerung,
-- sonst Schrift des gewählten UI-Stils
local function Restyle(DB)
  local done = false
  if viaNaowh then
    local nf = NF()
    done = pcall(function()
      local S, Parts = nf.QoLSettings, nf.Shared.Parts
      local font, size, outline = S.Get("restockFont"), S.Get("restockFontSize"), S.Get("restockOutline")
      local mode = alert.backdrop and alert.backdrop:SetMode(S.Get("restockBackground"))
      Parts.HudFont(alert.title, font, size + TITLE_GROW, outline, mode)
      Parts.HudFont(alert.text, font, size, outline, mode)
    end)
  end
  if not done then
    local _, font = ns.GetStyle(DB.menuStil)
    alert.title:SetFont(font, TITLE_SIZE, "OUTLINE")
    alert.text:SetFont(font, TEXT_SIZE, "OUTLINE")
  end
end

local function Show(kind, title, text)
  local DB = ns.GetDB()
  if not alert then Build() end
  Restyle(DB)
  local p = ns.GetStyle(DB.menuStil)
  local tc = (kind == "empty" and RED) or (kind == "low" and ORANGE) or p.accent
  alert.title:SetTextColor(tc[1], tc[2], tc[3], 1)
  alert.title:SetText(title)
  alert.text:SetTextColor(p.fg[1], p.fg[2], p.fg[3], 1)
  alert.text:SetText(text)
  alert:SetSize(
    math.max(alert.title:GetStringWidth(), alert.text:GetStringWidth()) + PAD_W,
    alert.title:GetStringHeight() + alert.text:GetStringHeight() + PAD_H)
  local isNew = not alert:IsShown() or alert.kind ~= kind
  alert.kind = kind
  if not alert:IsShown() then alert:Show() end
  -- Warnungen blinken beim Erscheinen kurz (wie Naowhs Auffüll-Erinnerung)
  if isNew and kind ~= "info" then
    flash.loops = 0
    flash:Stop()
    flash:Play()
  end
end

local function Hide()
  if alert then
    flash:Stop()
    alert:Hide()
    alert.kind = nil
  end
end
ns.HideAlert = Hide

local function Resting()
  return IsResting() and not UnitAffectingCombat("player") and not IsInInstance()
end

-- Wird vom HUD bei jeder Aktualisierung (ca. 1x pro Sekunde) aufgerufen
-- isFull: Köcher/Beutel voll (ohne Köcher: Vorrat auf Höchststand)
-- room:   wie viel dieser Munition noch in den Köcher passt (nil = kein Köcher)
function ns.UpdateAlert(state, count, full, name, isFull, room)
  if not ready then return end
  if GetTime() < holdUntil then return end
  local DB = ns.GetDB()
  name = name or "Munition"

  if DB.meldungen and (state == "low" or state == "empty") then
    if state == "empty" then
      Show("empty", "Munition aufgebraucht!", name .. " – jetzt nachkaufen")
    elseif Resting() then
      Show("low", "Munition knapp", ("Nur noch %d %s (voll: %d) – hier nachkaufen"):format(count, name, full))
    else
      Show("low", "Munition knapp", ("Nur noch %d %s (voll: %d)"):format(count, name, full))
    end
    return
  end

  if state == "none" then
    noneSince = noneSince or GetTime()
  else
    noneSince = nil
  end

  if DB.ruheInfo and Resting() then
    if state ~= "none" then
      -- Ist der Köcher/Beutel voll, verschwindet die Ruhebereich-Meldung
      if not isFull then
        if room and room > 0 then
          Show("info", "Munition", ("%d %s  ·  Köcher: Platz für %d"):format(count, name, room))
        else
          Show("info", "Munition", ("%d %s"):format(count, name))
        end
        return
      end
    elseif playerClass == "HUNTER" and GetTime() - noneSince >= NONE_DELAY then
      -- erst nach ein paar Sekunden ohne Munition (Taschen laden nach dem Einloggen kurz nach)
      Show("low", "Munition", "Keine Pfeile oder Kugeln dabei – hier nachkaufen")
      return
    end
  end

  Hide()
end

-- Kurzmeldung, die ein paar Sekunden stehen bleibt (z. B. "aufgefüllt")
function ns.ShowTimedAlert(kind, title, text, seconds)
  if not ready then return end
  Show(kind, title, text)
  holdUntil = GetTime() + (seconds or 4)
end

-- ---------- Raid-Check ----------
-- Beim Beitritt zu einem Raid (bzw. Umwandlung der Gruppe in einen Raid)
-- und beim Betreten einer Raid-Instanz: Vorrat mit dem empfohlenen
-- Mindestbedarf vergleichen und als Meldung zeigen (raidDauer Sekunden).
-- Richtwerte (Classic-Mechanik, Stapel 200): 20er ca. 1600, 40er ca. 3200.
local function RaidSize()
  local inInst, iType = IsInInstance()
  if inInst and iType == "raid" then
    local maxPlayers = select(5, GetInstanceInfo())
    if maxPlayers and maxPlayers > 0 then return maxPlayers end
  end
end

function ns.RaidCheck(test)
  if not ready then return end
  local DB = ns.GetDB()
  if not test and (not DB.raidCheck or playerClass ~= "HUNTER") then return end
  local size = RaidSize()
  local need, label
  if size and size <= 20 then
    need, label = DB.raidBedarf20, "20er"
  else
    need, label = DB.raidBedarf40, "40er"
  end
  local id, count = ns.GetStatus()
  local name = (id and ns.GetAmmoName and ns.GetAmmoName(id)) or "Munition"
  local kind, title, text
  if not id then
    kind, title = "empty", "Raid-Check: keine Munition!"
    text = ("Empfohlen für %s-Raid: mind. %d"):format(label, need)
  elseif count >= need then
    kind, title = "info", "Raid-Check: Munition reicht"
    text = ("%d %s  ·  empfohlen %s-Raid: %d"):format(count, name, label, need)
  else
    kind = (count < need / 2) and "empty" or "low"
    title = "Raid-Check: zu wenig Munition"
    text = ("%d von %d %s (%s-Raid) – es fehlen %d"):format(count, need, name, label, need - count)
  end
  if kind ~= "info" and DB.sound and ns.PlayAlertSound then ns.PlayAlertSound() end
  if DB.chatWarnung then ns.Print(title .. " – " .. text) end
  ns.ShowTimedAlert(kind, title, text, DB.raidDauer or 60)
end

local wasInRaid = false
local lastRaidInstance

local function Later(sec, fn)
  if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end
end

-- Wohin gehen die Meldungen? (fürs Menü)
function ns.AlertTarget()
  if alert then return viaNaowh and "Naowh Forever" or "eigener Bereich" end
  return NF() and "Naowh Forever" or "eigener Bereich"
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
pcall(loader.RegisterEvent, loader, "GROUP_ROSTER_UPDATE")
pcall(loader.RegisterEvent, loader, "PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    ready = true
    playerClass = select(2, UnitClass("player"))
    wasInRaid = IsInRaid() -- nach /reload im Raid nicht erneut melden
    return
  end
  if not ready then return end
  if event == "GROUP_ROSTER_UPDATE" then
    local inRaid = IsInRaid()
    if inRaid and not wasInRaid then
      Later(2, function() pcall(ns.RaidCheck) end)
    end
    wasInRaid = inRaid
  elseif event == "PLAYER_ENTERING_WORLD" then
    local inInst, iType = IsInInstance()
    if inInst and iType == "raid" then
      local instId = select(8, GetInstanceInfo())
      if instId ~= lastRaidInstance then
        lastRaidInstance = instId
        Later(3, function() pcall(ns.RaidCheck) end)
      end
    else
      lastRaidInstance = nil
    end
  end
end)
