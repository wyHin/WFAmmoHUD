-- =====================================================================
-- WFAmmoHUD – kleines HUD für deinen Jäger-Munitionsvorrat
--
-- Zeigt die ausgerüstete Munition (Pfeile/Kugeln) als kleines,
-- verschiebbares HUD mit Icon, Restbestand und Fortschrittsbalken
-- und warnt rechtzeitig, wenn der Vorrat zur Neige geht:
-- pulsierendes HUD, Warnton und Chat-Nachricht (alle 2 Minuten,
-- solange der Vorrat knapp ist).
--
-- Gebaut für World of Warcraft: Forever
-- (Interface 16001, moderne Mainline-Addon-API, Lua 5.1).
--
-- Befehle (Alias: /munition):
--   /wfhud              Status + Hilfe
--   /wfhud ein | aus    HUD ein- bzw. ausblenden
--   /wfhud grenz <n>    warnen ab n Schuss (0–3200, Standard 400)
--   /wfhud groesse <n>  Icon-Größe (24–96, Standard 44)
--   /wfhud schrift <n>  Schriftgröße (10–36, Standard 16)
--   /wfhud sound ein|aus  Warnton an/aus
--   /wfhud reset        HUD-Position zurücksetzen
-- =====================================================================

local ADDON, ns = ...
ADDON = ADDON or "WFAmmoHUD"
ns = ns or {}
local DB_NAME = "WFAmmoHUDDB"

-- ---------- Einstellungen ----------
local DEFAULTS = {
  enabled   = true,
  warnAb    = 400, -- warnen, sobald der Vorrat auf diesen Wert fällt
  groesse   = 44,  -- Icon-Größe in Pixeln
  schrift   = 16,  -- Schriftgröße der Zahl
  sound     = true,
  meldungen   = true,  -- Warnungen im Meldungsbereich (Naowh Forever) statt im Chat
  ruheInfo    = true,  -- im Ruhebereich (Gasthaus/Stadt) den Vorrat als Meldung zeigen
  chatWarnung = false, -- Warnungen zusätzlich im Chat
  ammoWahl     = true, -- andere Munition aus den Taschen unter dem HUD zum Anlegen zeigen
  raidCheck    = true, -- beim Beitritt zu einem Raid / Betreten einer Raid-Instanz Vorrat prüfen
  raidDauer    = 60,   -- Sekunden, die die Raid-Meldung stehen bleibt
  raidBedarf20 = 1600, -- empfohlener Mindestvorrat 20er-Raid (8 Stapel)
  raidBedarf40 = 3200, -- empfohlener Mindestvorrat 40er-Raid (16er-Köcher voll)
  menuStil  = "auto", -- UI-Stil für Menü + HUD: auto | naowh | ellesmere | forever | standard
  relX      = nil, -- nil = Standardposition (rechts oben unter der Minimap)
  relY      = nil,
}

local DEFAULT_ICON = "Interface\\Icons\\INV_Ammo_Arrow_02"
local PREFIX = "|cFF999999WFAmmoHUD:|r "

local DB
local AMMO_SLOT = 0 -- Inventarslot "Munition" (wird beim Laden per API ermittelt)

-- ---------- Zustand ----------
local t = 0
local checkT = 0
local lastW, lastH = 0, 0
local lastErrT = -1e9
local curItemId
local state = "none" -- "ok" | "low" | "empty" | "none"
local warned = false
local lastWarnT = -1e9
local lastCount, lastFull = 0, 0
local refillAt -- Zeitpunkt, ab dem "aufgefüllt" in den Chat geht (nach dem letzten Kauf)
local testUntil = -1 -- HUD pulsiert bis zu diesem Zeitpunkt (Testwarnung)

local frame, icon, iconBorder, countText, barBg, barFill, boot

local WHITE8 = "Interface\\Buttons\\WHITE8X8"

-- Farben des gewählten UI-Stils (siehe Style.lua / ApplyHUDStyle)
local S = {
  bg     = { 0.098, 0.106, 0.114 },
  line   = { 0.216, 0.231, 0.251 },
  fg     = { 0.941, 0.945, 0.953 },
  muted  = { 0.604, 0.620, 0.651 },
  accent = { 0, 0.569, 0.929 },
  font   = "Fonts\\ARIALN.TTF",
}

-- Zahlfarbe je Zustand; ok/none folgen dem UI-Stil, Warnfarben bleiben fest
local COL = {
  ok    = S.fg,
  low   = { 1,    0.66, 0.20 },
  empty = { 1,    0.30, 0.30 },
  none  = S.muted,
}

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

-- ---------- Datenbank ----------
local function InitDB()
  local stored = _G[DB_NAME]
  if type(stored) ~= "table" then
    stored = {}
    _G[DB_NAME] = stored
  end
  for k, v in pairs(DEFAULTS) do
    if stored[k] == nil then stored[k] = v end
  end
  if type(stored.itemCache) ~= "table" then stored.itemCache = {} end
  -- [itemID] = zuletzt als "voll" gesehener Vorrat (bleibt über /reload erhalten)
  if type(stored.fullByItem) ~= "table" then stored.fullByItem = {} end
  DB = stored
end

-- ---------- Berechnungen ----------
-- Warnt ab einem festen Wert (Menü: Warnung → "Warnen ab", Standard 400).
-- "full" bleibt als Parameter, damit die Aufrufer unverändert bleiben.
local function ComputeWarnPoint(full)
  return DB.warnAb or DEFAULTS.warnAb
end

local PROJECTILE_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Projectile) or 6

local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- Unterklasse der Munition (2 = Pfeil, 3 = Kugel) bzw. nil, wenn kein Projektil
local function ProjectileKind(itemId)
  if not getInstant then return nil end
  local _, _, _, equipLoc, _, classID, subID = getInstant(itemId)
  if classID == PROJECTILE_CLASS or equipLoc == "INVTYPE_AMMO" then return subID or 0 end
end

local function ItemCount(id)
  if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
  if GetItemCount then return GetItemCount(id) or 0 end
  return 0
end

local function IsProjectile(itemId)
  return ProjectileKind(itemId) ~= nil
end

-- Alle Munition in Taschen + Köcher: totals[itemID] = Anzahl, where[itemID] = {bag, slot}
local function ScanAmmo()
  local totals, where = {}, {}
  if not (C_Container and C_Container.GetContainerNumSlots) then return totals, where end
  for bag = 0, NUM_BAG_SLOTS or 4 do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local id = info and info.itemID
      if id and (totals[id] or IsProjectile(id)) then
        totals[id] = (totals[id] or 0) + (info.stackCount or 0)
        if not where[id] then where[id] = { bag, slot } end
      end
    end
  end
  return totals, where
end

-- Rückfall, wenn der Munitionsplatz leer meldet (z. B. kurz nach dem Einloggen
-- oder nach dem Kauf): Munition im Köcher / in den Taschen suchen.
-- Bevorzugt eine schon bekannte Sorte, sonst die mit dem größten Vorrat.
local function FindAmmoInBags()
  local totals = ScanAmmo()
  -- zusätzlich: schon bekannte Munitionssorten direkt zählen
  -- (falls die Taschenabfrage oder die Itemklasse im Client nicht greift)
  for id in pairs(DB.fullByItem) do
    if not totals[id] then
      local n = ItemCount(id)
      if n > 0 then totals[id] = n end
    end
  end
  local best, bestN, bestKnown
  for id, n in pairs(totals) do
    local known = DB.fullByItem[id] ~= nil
    if not best or (known and not bestKnown) or (known == bestKnown and n > bestN) then
      best, bestN, bestKnown = id, n, known
    end
  end
  return best
end

local ammoEquipped = false -- liefert der Munitionsplatz selbst die Sorte?

local function GetEquippedAmmoId()
  local id = GetInventoryItemID("player", AMMO_SLOT)
  if id == 0 then id = nil end
  ammoEquipped = id ~= nil
  if not id then id = FindAmmoInBags() end
  return id
end

-- Gesamtvorrat dieser Munition (Taschen + Köcher). Der Munitions-Slot zählt
-- die ausgerüstete Sorte bereits über alle Stapel (so machen es auch
-- EllesmereUI und Mastercraft im Forever-Client).
local function GetAmmoCount(id)
  if not id then return 0 end
  local n = ammoEquipped and GetInventoryItemCount("player", AMMO_SLOT) or nil
  if not n or n == 0 then
    if C_Item and C_Item.GetItemCount then
      n = C_Item.GetItemCount(id)
    elseif GetItemCount then
      n = GetItemCount(id)
    end
  end
  return n or 0
end

-- Itemdaten zur Laufzeit lesen (in Forever sind viele Items
-- erst nach dem ersten Beziehen bekannt) und zwischenspeichern.
-- Rückgabe: name, texture
local function GetAmmoInfo(itemId)
  if not itemId then return nil, nil end
  local name, texture
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if getInfo then
    local info = { getInfo(itemId) }
    name, texture = info[1], info[10]
  end
  if not texture then
    texture = GetInventoryItemTexture("player", AMMO_SLOT)
  end
  local cached = DB.itemCache[itemId]
  if cached then
    name = name or cached.name
    texture = texture or cached.texture
  end
  if name or texture then
    DB.itemCache[itemId] = { name = name, texture = texture }
  end
  return name, texture
end

-- ---------- Köcher / Munitionsbeutel ----------
local function MaxStack(itemId)
  local n = C_Item and C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(itemId)
  if not n then
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if getInfo then n = select(8, getInfo(itemId)) end
  end
  return n
end

-- Ist der Köcher bzw. Munitionsbeutel voll?
-- Rückgabe: hasBag, isFull, room (wie viel dieser Munition noch hineinpasst)
-- Taschenfamilie: Bit 1 = Köcher (Pfeile), Bit 2 = Munitionsbeutel (Kugeln)
local function GetQuiverState(ammoId)
  if not (C_Container and C_Container.GetContainerNumSlots and bit) then return false, false, 0 end
  local ammoFam = (ammoId and C_Item and C_Item.GetItemFamily and C_Item.GetItemFamily(ammoId)) or 0
  local ammoMax = ammoId and MaxStack(ammoId) or 0
  local hasBag, full, room = false, true, 0
  for bag = 1, NUM_BAG_SLOTS or 4 do
    local _, fam = C_Container.GetContainerNumFreeSlots(bag)
    fam = fam or 0
    local takesAmmo = fam ~= 0 and (
      (ammoFam ~= 0 and bit.band(ammoFam, fam) ~= 0) or
      (ammoFam == 0 and bit.band(fam, 3) ~= 0))
    if takesAmmo then
      hasBag = true
      for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if not info then
          full = false
          room = room + (ammoMax or 0)
        else
          local m = MaxStack(info.itemID)
          local c = info.stackCount or 0
          if m and c < m then
            full = false
            if info.itemID == ammoId then room = room + (m - c) end
          end
        end
      end
    end
  end
  return hasBag, hasBag and full, room
end

-- ---------- Warnung ----------
local function PlayAlertSound()
  local ok = pcall(PlaySoundFile, "Sound\\Interface\\RaidWarning.ogg", "Master")
  if not ok then
    pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
  end
end

-- Ton (+ optional Chat). Die sichtbare Meldung macht Alerts.lua (ns.UpdateAlert).
local function FireAlert(count, name, full)
  if DB.sound then PlayAlertSound() end
  if not DB.chatWarnung then return end
  if state == "empty" then
    Print("|cFFFF5555Munition aufgebraucht!|r " ..
      (name or "Deine Munition") .. " – jetzt nachkaufen.")
  else
    Print(("|cFFFFAA00Nur noch %d %s|r übrig (voll: %d) – Vorrat wird knapp!"):format(
      count, name or "Munition", full))
  end
end

-- ---------- Layout-Breite an die Zahl anpassen ----------
local function UpdateWidth()
  local s = DB.groesse
  local cw = math.max(countText:GetStringWidth() or 0, 24)
  frame:SetWidth(8 + s + 10 + math.ceil(cw) + 10)
end

-- ---------- Andere Munition: Schnellwechsel unter dem HUD ----------
-- Zeigt jede andere Pfeil-/Kugelsorte aus Taschen/Köcher als kleines Symbol;
-- Klick legt sie an (nur außerhalb des Kampfes – das erlaubt der Client nicht).
local RANGED_SLOT = 18
local ARROW, BULLET = 2, 3
local altBar
local altButtons = {}
local altSig

-- Welche Munition passt zur Fernkampfwaffe? (Bogen/Armbrust -> Pfeile, Gewehr -> Kugeln)
local function WantedKind()
  local rid = GetInventoryItemID("player", RANGED_SLOT)
  if not rid or not getInstant then return nil end
  local _, _, _, _, _, classID, subID = getInstant(rid)
  if classID ~= 2 then return nil end -- keine Waffe
  if subID == 2 or subID == 18 then return ARROW end
  if subID == 3 then return BULLET end
end

-- Secure-Buttons: der Klick führt "/equip item:ID" aus – das darf der Spieler
-- auch im Kampf. Aufbau, Attribute und Position der Knöpfe lassen sich aber
-- nur außerhalb des Kampfes ändern (Client-Regel für geschützte Frames).
-- Deshalb hängt die Leiste an UIParent (nicht am HUD) und wird nur außerhalb
-- des Kampfes neu aufgebaut/verschoben; im Kampf nur Zahlen aktualisieren.
local function AfterEquipClick()
  if C_Timer and C_Timer.After then
    C_Timer.After(0.3, function() checkT = 1 end)
  end
end

local function AltButton(i)
  local b = altButtons[i]
  if b then return b end
  b = CreateFrame("Button", "WFAmmoHUDAltButton" .. i, altBar, "SecureActionButtonTemplate")
  b:RegisterForClicks("AnyUp")
  b:SetAttribute("type", "macro")
  b:SetAttribute("useOnKeyDown", false)
  b:HookScript("PostClick", AfterEquipClick)
  b.border = b:CreateTexture(nil, "BORDER")
  b.border:SetAllPoints()
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 1, -1)
  b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.count:SetPoint("BOTTOMRIGHT", -1, 2)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints(b.icon)
  b.hl:SetColorTexture(1, 1, 1, 0.15)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    if not (self.where and GameTooltip:SetBagItem(self.where[1], self.where[2])) then
      GameTooltip:AddLine((DB.itemCache[self.itemId] or {}).name or ("Item " .. self.itemId), 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Vorrat: %d"):format(self.n or 0), 1, 1, 1)
    GameTooltip:AddLine("Klicken: diese Munition anlegen (auch im Kampf)", S.accent[1], S.accent[2], S.accent[3])
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  altButtons[i] = b
  return b
end

local altX, altY

-- Leiste unter das HUD setzen (nur außerhalb des Kampfes)
local function PlaceAltBar()
  local left, bottom = frame:GetLeft(), frame:GetBottom()
  if not left or not bottom then return end
  local k = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
  local x, y = math.floor(left * k + 0.5), math.floor(bottom * k + 0.5) - 3
  if x ~= altX or y ~= altY then
    altX, altY = x, y
    altBar:ClearAllPoints()
    altBar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
  end
end

local function HideAltBar()
  if altBar and not InCombatLockdown() then altBar:Hide() end
  altSig = nil
end

local function UpdateAltAmmo(currentId)
  if InCombatLockdown() then
    -- im Kampf nur die Zahlen der vorhandenen Knöpfe auffrischen
    if altBar and altBar:IsShown() then
      local totals = ScanAmmo()
      for _, b in ipairs(altButtons) do
        if b:IsShown() and b.itemId then
          b.n = totals[b.itemId] or 0
          b.count:SetText(b.n)
          b.icon:SetDesaturated(b.n == 0)
        end
      end
    end
    return
  end
  if not altBar then
    altBar = CreateFrame("Frame", "WFAmmoHUDAltBar", UIParent)
    altBar:SetFrameStrata("HIGH")
    altBar:SetSize(1, 1)
  end
  if not DB.ammoWahl then HideAltBar(); return end
  PlaceAltBar()

  local totals, where = ScanAmmo()
  local want = WantedKind()
  local list = {}
  for id, n in pairs(totals) do
    local skip = (ammoEquipped and id == currentId) or n <= 0
    if not skip and want then
      local kind = ProjectileKind(id)
      if kind and kind ~= want and kind ~= 0 then skip = true end
    end
    if not skip then
      local _, _, _, ilvl = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id)
      list[#list + 1] = { id = id, n = n, where = where[id], ilvl = ilvl or 0 }
    end
  end
  -- bessere (höherstufige) Munition zuerst
  table.sort(list, function(a, b)
    if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
    return a.id < b.id
  end)

  local size = math.max(20, math.floor(DB.groesse * 0.6))
  local parts = { size }
  for _, e in ipairs(list) do parts[#parts + 1] = e.id .. ":" .. e.n end
  local sig = table.concat(parts, ",")
  if sig == altSig then return end
  altSig = sig

  for i, e in ipairs(list) do
    local b = AltButton(i)
    b.itemId, b.where, b.n = e.id, e.where, e.n
    b:SetAttribute("macrotext", "/equip item:" .. e.id)
    b:SetSize(size, size)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", altBar, "TOPLEFT", (i - 1) * (size + 3), 0)
    b.border:SetColorTexture(S.line[1], S.line[2], S.line[3], 1)
    local tex = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.id)
    if not tex and e.where then
      local info = C_Container.GetContainerItemInfo(e.where[1], e.where[2])
      tex = info and info.iconFileID
    end
    b.icon:SetTexture(tex or DEFAULT_ICON)
    b.icon:SetDesaturated(false)
    b.count:SetFont(S.font, math.max(9, math.floor(size * 0.38)), "OUTLINE")
    b.count:SetText(e.n)
    b:Show()
  end
  for i = #list + 1, #altButtons do altButtons[i]:Hide() end
  altBar:SetShown(#list > 0)
end

-- ---------- Aktualisierung ----------
local function Refresh()
  if not frame then return end
  if not DB.enabled then
    frame:Hide()
    HideAltBar()
    if ns.HideAlert then ns.HideAlert() end
    return
  end
  if not frame:IsShown() then frame:Show() end

  local id = GetEquippedAmmoId()
  local name, texture = GetAmmoInfo(id)
  local count = GetAmmoCount(id)

  -- "Voll" = was nach dem Auffüllen dabei wäre:
  --   mit Köcher/Munitionsbeutel: aktueller Vorrat + freier Platz im Köcher
  --     (leere Plätze x Stapelgröße + Rest angebrochener Stapel dieser Sorte)
  --   ohne Köcher (oder Munition ohne Stapel, z. B. unendliche 1/1-Pfeile):
  --     gemerkter Höchststand dieser Sorte
  local full = 0
  local hasBag, bagFull, room = false, false, 0
  if id then hasBag, bagFull, room = GetQuiverState(id) end
  if id then
    -- Höchststand weiter merken (Rückfall ohne Köcher, bekannte Sorten)
    local oldFull = DB.fullByItem[id]
    if not oldFull or count > oldFull then DB.fullByItem[id] = count end
    if hasBag and (MaxStack(id) or 0) > 1 then
      full = count + (room or 0)
    else
      full = DB.fullByItem[id] or 0
    end

    -- Nachschub erkennen: Vorrat derselben Sorte ist gestiegen
    if curItemId == id and lastCount > 0 and count > lastCount then
      if ns.ShowTimedAlert then
        ns.ShowTimedAlert("info", bagFull and "Köcher voll" or "Vorrat aufgefüllt",
          ("%d / %d %s"):format(count, math.max(full, count), name or "Munition"), 5)
      end
      refillAt = GetTime() + 3 -- Chat erst, wenn 3 s nichts mehr dazukam
    end
  end
  if full < count then full = count end
  if refillAt and GetTime() >= refillAt then
    refillAt = nil
    if DB.chatWarnung and id then
      Print(("Vorrat aufgefüllt: jetzt %d / %d %s."):format(count, full, name or ""))
    end
  end

  if curItemId ~= id then
    curItemId = id
    warned = false
    refillAt = nil
  end

  lastCount, lastFull = count, full

  -- Zustand bestimmen
  local newState
  if not id then
    newState = "none"
  elseif count == 0 then
    newState = "empty"
  else
    -- Nur warnen, wenn tatsächlich verbraucht wurde (count < full).
    -- So bleiben "unendliche" 1/1-Pfeile in Ruhe.
    local wp = ComputeWarnPoint(full)
    if count < full and count <= wp then
      newState = "low"
    else
      newState = "ok"
    end
  end
  state = newState

  -- Warnung auslösen (sofort, danach alle 120 s)
  if state == "low" or state == "empty" then
    if (not warned) or (t - lastWarnT >= 120) then
      FireAlert(count, name, full)
      warned = true
      lastWarnT = t
    end
  else
    warned = false
  end

  -- Meldung im Meldungsbereich (Warnung bzw. Vorrat im Ruhebereich)
  -- "voll": Köcher/Beutel randvoll; ohne Köcher: Vorrat wieder auf dem gemerkten Höchststand
  -- (mit Köcher gilt count >= full automatisch genau dann, wenn kein Platz mehr frei ist)
  local isFull
  if hasBag then isFull = bagFull else isFull = id ~= nil and count >= full end
  if ns.UpdateAlert then ns.UpdateAlert(state, count, full, name, isFull, hasBag and room or nil) end

  -- Schnellwechsel für andere Munition
  UpdateAltAmmo(id)

  -- Icon
  icon:SetDesaturated(state == "none")
  if state ~= "none" and texture and texture ~= "" then
    icon:SetTexture(texture)
  else
    icon:SetTexture(DEFAULT_ICON)
  end

  -- Zahl
  countText:SetText(id and tostring(count) or "-")
  local c = COL[state] or COL.none
  countText:SetTextColor(c[1], c[2], c[3], 1)
  UpdateWidth()

  -- Fortschrittsbalken
  local ratio = 0
  if id then
    if full > 0 then
      ratio = math.max(0, math.min(1, count / full))
    else
      ratio = 1
    end
  end
  local barW = math.max(8, frame:GetWidth() - 16)
  barFill:SetWidth(math.max(0.01, barW * ratio))
  barFill:SetShown(ratio > 0)
  -- voll: Akzentfarbe des UI-Stils, knapp: orange, fast leer: rot
  if ratio > 0.5 then
    barFill:SetColorTexture(S.accent[1], S.accent[2], S.accent[3], 1)
  elseif ratio > 0.2 then
    barFill:SetColorTexture(1, 0.62, 0.25, 1)
  else
    barFill:SetColorTexture(1, 0.28, 0.25, 1)
  end
end

local function SafeRefresh()
  local ok, err = pcall(Refresh)
  if not ok and t - lastErrT > 30 then
    lastErrT = t
    Print("|cFFFF5555Fehler:|r " .. tostring(err))
  end
end

-- ---------- Layout & Position ----------
local function ApplyLayout()
  if not frame then return end
  local s = DB.groesse
  icon:ClearAllPoints()
  icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
  icon:SetSize(s, s)
  iconBorder:ClearAllPoints()
  iconBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
  iconBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)

  countText:ClearAllPoints()
  countText:SetPoint("LEFT", icon, "RIGHT", 10, 0)
  countText:SetJustifyH("LEFT")
  countText:SetFontObject(GameFontNormalLarge) -- Rückfall, falls die Schrift fehlt
  countText:SetFont(S.font, DB.schrift, "OUTLINE")

  frame:SetHeight(8 + math.max(s, DB.schrift + 4) + 6 + 5 + 5)
  UpdateWidth()

  barBg:ClearAllPoints()
  barBg:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 6)
  barBg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 6)
  barBg:SetHeight(5)

  barFill:ClearAllPoints()
  barFill:SetPoint("BOTTOMLEFT", barBg, "BOTTOMLEFT", 0, 0)
  barFill:SetHeight(5)

  SafeRefresh()
end

local function DefaultPosition()
  frame:ClearAllPoints()
  frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -16, -170)
end

local function Reposition()
  if not DB.relX or not DB.relY then
    DefaultPosition()
    return
  end
  local W, H = UIParent:GetWidth(), UIParent:GetHeight()
  local ox = math.max(0, math.min(W - 16, DB.relX * W))
  local oy = math.max(0, math.min(H - 16, DB.relY * H))
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", ox, -oy)
end

-- ---------- Verschieben ----------
local function OnDragStart(self)
  self:StartMoving()
end

local function OnDragStop(self)
  self:StopMovingOrSizing()
  self:SetUserPlaced(false) -- Position verwalten wir selbst (relativ in DB)
  local W, H = UIParent:GetWidth(), UIParent:GetHeight()
  local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
  local left = (self:GetLeft() or 0) * scale
  local top = (self:GetTop() or H) * scale
  DB.relX = math.max(0, math.min(0.995, left / W))
  DB.relY = math.max(0, math.min(0.995, (H - top) / H))
  Reposition()
end

-- ---------- Tooltip ----------
local function OnEnter(self)
  if not DB.enabled then return end
  local W = UIParent:GetWidth()
  local anchor = (self:GetRight() or 0) > W * 0.65 and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
  GameTooltip:SetOwner(self, anchor)
  if curItemId then
    if not GameTooltip:SetInventoryItem("player", AMMO_SLOT) then
      local name = DB.itemCache[curItemId] and DB.itemCache[curItemId].name
      GameTooltip:AddLine(name or ("Item " .. curItemId), 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Vorrat: %d (voll: %d)"):format(lastCount, lastFull), 1, 1, 1)
    GameTooltip:AddLine(("Warnt ab: %d"):format(ComputeWarnPoint(lastFull)), 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Ziehen, um das HUD zu verschieben.", 0.6, 0.6, 0.6)
  else
    GameTooltip:AddLine("Keine Munition ausgerüstet", 1, 1, 1)
    GameTooltip:AddLine("Rüste Pfeile oder Kugeln aus – das HUD zeigt dann deinen Vorrat.", 0.8, 0.8, 0.8, true)
  end
  GameTooltip:Show()
end

local function OnLeave(self)
  GameTooltip:Hide()
end

-- ---------- Update ----------
local function OnUpdate(self, elapsed)
  t = t + elapsed

  -- Pulsieren im Warnzustand (oder während einer Testwarnung)
  local testing = t < testUntil
  if testing or state == "low" or state == "empty" then
    local pulse = 0.5 + 0.5 * math.sin(t * 3.5)
    local a = 0.3 + 0.7 * pulse
    if state == "empty" and not testing then
      frame:SetBackdropColor(0.4 * pulse, 0.06 * pulse, 0.06 * pulse, 0.6)
      frame:SetBackdropBorderColor(1, 0.35, 0.3, a)
    else
      frame:SetBackdropColor(0.42 * pulse, 0.16 * pulse, 0.03 * pulse, 0.6)
      frame:SetBackdropBorderColor(1, 0.66, 0.2, a)
    end
  else
    frame:SetBackdropColor(S.bg[1], S.bg[2], S.bg[3], 0.85)
    frame:SetBackdropBorderColor(S.line[1], S.line[2], S.line[3], 1)
  end

  checkT = checkT + elapsed
  if checkT >= 1 then
    checkT = 0
    SafeRefresh()
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    if W ~= lastW or H ~= lastH then
      lastW, lastH = W, H
      if DB.relX and DB.relY then Reposition() end
    end
  end
end

-- ---------- UI aufbauen ----------
local function CreateUI()
  local template = BackdropTemplateMixin and "BackdropTemplate" or nil
  frame = CreateFrame("Frame", "WFAmmoHUDFrame", UIParent, template)
  frame:SetFrameStrata("HIGH")
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  -- flacher Rahmen mit 1-Pixel-Linie wie bei Naowh Forever / EllesmereUI
  frame:SetBackdrop({
    bgFile = WHITE8,
    edgeFile = WHITE8,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  frame:SetBackdropColor(S.bg[1], S.bg[2], S.bg[3], 0.85)
  frame:SetBackdropBorderColor(S.line[1], S.line[2], S.line[3], 1)
  frame:SetScript("OnDragStart", OnDragStart)
  frame:SetScript("OnDragStop", OnDragStop)
  frame:SetScript("OnEnter", OnEnter)
  frame:SetScript("OnLeave", OnLeave)
  frame:SetScript("OnUpdate", OnUpdate)

  iconBorder = frame:CreateTexture(nil, "BORDER")
  iconBorder:SetColorTexture(S.line[1], S.line[2], S.line[3], 1)

  icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(DEFAULT_ICON)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  countText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  countText:SetJustifyH("LEFT")

  barBg = frame:CreateTexture(nil, "BORDER")
  barBg:SetColorTexture(S.line[1], S.line[2], S.line[3], 1)

  barFill = frame:CreateTexture(nil, "ARTWORK")
  barFill:SetColorTexture(S.accent[1], S.accent[2], S.accent[3], 1)
end

-- Farben und Schrift des gewählten UI-Stils (Naowh Forever, EllesmereUI,
-- Forever oder Standard) aufs HUD übertragen
local function ApplyHUDStyle()
  if not frame or not DB or not ns.GetStyle then return end
  local p, font = ns.GetStyle(DB.menuStil)
  for _, k in ipairs({ "bg", "line", "fg", "muted", "accent" }) do
    S[k][1], S[k][2], S[k][3] = p[k][1], p[k][2], p[k][3]
  end
  S.font = font
  iconBorder:SetColorTexture(S.line[1], S.line[2], S.line[3], 1)
  barBg:SetColorTexture(S.line[1], S.line[2], S.line[3], 1)
  frame:SetBackdropColor(S.bg[1], S.bg[2], S.bg[3], 0.85)
  frame:SetBackdropBorderColor(S.line[1], S.line[2], S.line[3], 1)
  ApplyLayout() -- Schrift setzen, Größe neu berechnen, neu zeichnen
end
ns.ApplyHUDStyle = ApplyHUDStyle

-- ---------- Start ----------
local eventHandlers = {
  ADDON_LOADED = function(addon)
    if addon ~= ADDON then return end
    boot:UnregisterEvent("ADDON_LOADED")
    InitDB()
    local ok, slot = pcall(GetInventorySlotInfo, "AmmoSlot")
    if ok and type(slot) == "number" then AMMO_SLOT = slot end
    local okR, rslot = pcall(GetInventorySlotInfo, "RangedSlot")
    if okR and type(rslot) == "number" then RANGED_SLOT = rslot end
    CreateUI()
    if DB.relX and DB.relY then Reposition() else DefaultPosition() end
    ApplyHUDStyle()
    -- Itemdaten und Theme/Schrift anderer Addons brauchen kurz Ladezeit
    if C_Timer and C_Timer.After then
      C_Timer.After(2, function() pcall(ApplyHUDStyle); SafeRefresh() end)
    end
  end,
  PLAYER_LOGIN = function()
    pcall(ApplyHUDStyle)
  end,
}

-- Inventar-/Taschenänderungen -> sofortiger Check im nächsten Frame
local function ForceCheck()
  if frame then checkT = 1 end
end
for _, ev in ipairs({
  "PLAYER_ENTERING_WORLD", "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
  "BAG_UPDATE", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED",
  "PLAYER_UPDATE_RESTING", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}) do
  eventHandlers[ev] = ForceCheck
end

boot = CreateFrame("Frame", "WFAmmoHUDBoot")
boot:SetScript("OnEvent", function(self, event, ...)
  local fn = eventHandlers[event]
  if fn then fn(...) end
end)
for ev in pairs(eventHandlers) do
  -- pcall: falls der Client ein Event nicht kennt, nicht das ganze Addon abbrechen
  pcall(boot.RegisterEvent, boot, ev)
end

-- ---------- Chatbefehle ----------
local function ShowHelp()
  pcall(function()
    local id = GetEquippedAmmoId()
    if id then
      local name = GetAmmoInfo(id) or ("Item " .. id)
      local count = GetAmmoCount(id)
      local full = math.max(DB.fullByItem[id] or 0, count)
      Print(string.format("Munition: %s | Vorrat: %d (voll: %d, warnt ab: %d)",
        name, count, full, ComputeWarnPoint(full)))
    else
      Print("Keine Munition ausgerüstet.")
    end
  end)
  Print("Befehle:")
  DEFAULT_CHAT_FRAME:AddMessage("  /wfhud               – Einstellungsmenü öffnen")
  DEFAULT_CHAT_FRAME:AddMessage("  /wfhud hilfe         – Status + diese Hilfe")
  DEFAULT_CHAT_FRAME:AddMessage("  /wfhud test          – Testwarnung")
  DEFAULT_CHAT_FRAME:AddMessage("  /wfhud raid          – Raid-Check (Vorrat für den Raid prüfen)")
  DEFAULT_CHAT_FRAME:AddMessage("  /wfhud debug         – Diagnose der Munitionserkennung")
  DEFAULT_CHAT_FRAME:AddMessage("  /wfhud ein | aus      – HUD ein/aus")
  DEFAULT_CHAT_FRAME:AddMessage("  /wfhud grenz <n>     – warnen ab n Schuss (Std. 400)")
  DEFAULT_CHAT_FRAME:AddMessage("  /wfhud groesse <n>   – Icon-Größe 24–96 (Std. 44)")
  DEFAULT_CHAT_FRAME:AddMessage("  /wfhud schrift <n>   – Schriftgröße 10–36 (Std. 16)")
  DEFAULT_CHAT_FRAME:AddMessage("  /wfhud sound ein|aus – Warnton an/aus")
  DEFAULT_CHAT_FRAME:AddMessage("  /wfhud reset         – Position zurücksetzen (Alias: /munition)")
end

-- ---------- Schnittstelle für das Einstellungsmenü (Options.lua) ----------
ns.Print = Print
ns.GetDB = function() return DB end
ns.DEFAULTS = DEFAULTS
ns.ComputeWarnPoint = ComputeWarnPoint
ns.Refresh = SafeRefresh
ns.ApplyLayout = ApplyLayout
ns.GetStatus = function()
  local id = GetEquippedAmmoId()
  if not id then return nil, 0, 0 end
  local count = GetAmmoCount(id)
  local full = math.max(DB.fullByItem[id] or 0, count)
  return id, count, full
end
ns.GetAmmoName = function(id) return (GetAmmoInfo(id)) end
ns.PlayAlertSound = PlayAlertSound
ns.SetEnabled = function(on)
  DB.enabled = on and true or false
  if DB.enabled then
    SafeRefresh()
  else
    frame:Hide()
    HideAltBar()
    GameTooltip:Hide()
  end
end
ns.ResetPosition = function()
  DB.relX, DB.relY = nil, nil
  lastW, lastH = 0, 0
  DefaultPosition()
end
ns.TestAlert = function()
  PlayAlertSound()
  testUntil = t + 4
  if DB.enabled and not frame:IsShown() then frame:Show() end
  if ns.ShowTimedAlert and DB.meldungen then
    ns.ShowTimedAlert("low", "Munition knapp (Test)", "So erscheint die Warnung im Meldungsbereich.", 4)
  else
    Print("|cFFFFAA00Testwarnung|r – so warnt das HUD, wenn der Vorrat knapp wird.")
  end
end

SLASH_WFAMMOHUD1 = "/wfhud"
SLASH_WFAMMOHUD2 = "/munition"
SlashCmdList.WFAMMOHUD = function(msg)
  if not frame then
    Print("noch nicht fertig geladen – versuch es in einem Moment erneut.")
    return
  end
  local cmd, arg1 = (msg or ""):match("^%s*(%S+)%s*(%S*)")
  if not cmd then
    if ns.ToggleMenu then ns.ToggleMenu() else ShowHelp() end
    return
  end
  cmd = cmd:lower()
  arg1 = (arg1 or ""):lower()

  if cmd == "menu" or cmd == "menü" or cmd == "config" or cmd == "optionen" then
    if ns.ToggleMenu then ns.ToggleMenu() end
  elseif cmd == "test" then
    ns.TestAlert()
  elseif cmd == "debug" or cmd == "diag" then
    local ok, err = pcall(function()
      local sid = GetInventoryItemID("player", AMMO_SLOT)
      Print(("Slot %s: ItemID=%s, Anzahl=%s, Textur=%s"):format(tostring(AMMO_SLOT), tostring(sid),
        tostring(GetInventoryItemCount("player", AMMO_SLOT)), tostring(GetInventoryItemTexture("player", AMMO_SLOT))))
      Print(("Fernkampf-Slot %s: ItemID=%s | GetItemInfoInstant: %s | C_Container: %s"):format(
        tostring(RANGED_SLOT), tostring(GetInventoryItemID("player", RANGED_SLOT)),
        getInstant and "ja" or "NEIN", (C_Container and C_Container.GetContainerNumSlots) and "ja" or "NEIN"))
      local totals = ScanAmmo()
      local any = false
      for id, n in pairs(totals) do
        any = true
        Print(("  Taschen: %d x %s (Art %s)"):format(n, (DB.itemCache[id] or {}).name or id, tostring(ProjectileKind(id))))
      end
      if not any then Print("  Taschen: keine Munition erkannt") end
      for id in pairs(DB.fullByItem) do
        Print(("  bekannt: %s -> GetItemCount=%d"):format((DB.itemCache[id] or {}).name or id, ItemCount(id)))
      end
      for bag = 0, NUM_BAG_SLOTS or 4 do
        local free, fam = C_Container.GetContainerNumFreeSlots(bag)
        Print(("  Tasche %d: %s Plätze, frei %s, Familie %s"):format(bag,
          tostring(C_Container.GetContainerNumSlots(bag)), tostring(free), tostring(fam)))
      end
      local id = GetEquippedAmmoId()
      Print(("Ergebnis: ItemID=%s (angelegt: %s), Vorrat=%d, Zustand=%s"):format(
        tostring(id), ammoEquipped and "ja" or "nein", GetAmmoCount(id), state))
    end)
    if not ok then Print("Diagnose-Fehler: " .. tostring(err)) end
  elseif cmd == "raid" then
    if ns.RaidCheck then ns.RaidCheck(true) end
  elseif cmd == "ein" or cmd == "on" or cmd == "show" then
    DB.enabled = true
    SafeRefresh()
    Print("HUD eingeblendet.")
  elseif cmd == "aus" or cmd == "off" or cmd == "hide" then
    ns.SetEnabled(false)
    Print("HUD ausgeblendet.")
  elseif cmd == "grenz" or cmd == "grenze" or cmd == "abs" then
    local n = tonumber(arg1)
    if n and n >= 0 and n <= 3200 then
      DB.warnAb = math.floor(n)
      SafeRefresh()
      Print(("Warnung ab %d Schuss."):format(DB.warnAb))
    else
      Print("So: /wfhud grenz 400 (Zahl von 0–3200)")
    end
  elseif cmd == "groesse" or cmd == "größe" or cmd == "große" or cmd == "size" then
    local n = tonumber(arg1)
    if n and n >= 24 and n <= 96 then
      DB.groesse = math.floor(n)
      ApplyLayout()
      Print(("Icon-Größe auf %d gesetzt."):format(DB.groesse))
    else
      Print("So: /wfhud groesse 44 (Zahl von 24–96)")
    end
  elseif cmd == "schrift" or cmd == "font" then
    local n = tonumber(arg1)
    if n and n >= 10 and n <= 36 then
      DB.schrift = math.floor(n)
      ApplyLayout()
      Print(("Schriftgröße auf %d gesetzt."):format(DB.schrift))
    else
      Print("So: /wfhud schrift 16 (Zahl von 10–36)")
    end
  elseif cmd == "sound" or cmd == "ton" then
    if arg1 == "ein" or arg1 == "on" then
      DB.sound = true
      Print("Warnton an.")
    elseif arg1 == "aus" or arg1 == "off" then
      DB.sound = false
      Print("Warnton aus.")
    else
      Print("So: /wfhud sound ein|aus")
    end
  elseif cmd == "reset" then
    ns.ResetPosition()
    Print("Position zurückgesetzt (rechts oben).")
  else
    ShowHelp()
  end
end
