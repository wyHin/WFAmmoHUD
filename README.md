# WFAmmoHUD

Kleines HUD für **Jäger in World of Warcraft: Forever** – zeigt deinen Munitionsvorrat
(Pfeile & Kugeln) und warnt dich rechtzeitig, wenn's dem Ende zugeht.

## Was es macht
- Kleines, **verschiebbares HUD** (Standardposition: rechts oben unter der Minimap)
  mit Munitions-Icon, Restbestand und Fortschrittsbalken.
- **Warnung**, wenn der Vorrat knapp wird: pulsierendes HUD, Warnton und eine Meldung im
  Meldungsbereich von Naowh Forever (siehe *Meldungen*). Der Ton kommt alle 2 Minuten erneut,
  solange der Vorrat knapp ist.
- **„Voll“ richtet sich nach deinem Köcher/Munitionsbeutel:** aktueller Vorrat + freier Platz darin
  (leere Plätze × Stapelgröße + Rest angebrochener Stapel). Ohne Köcher gilt der gemerkte Höchststand
  pro Munitionstyp (auch über `/reload` und Neustarts hinweg). Nachschub wird automatisch erkannt
  und die Warnung zurückgesetzt.
- Tooltip über dem HUD zeigt Details (Vorrat, Schwelle, Item-Info).
- **Munitionswechsel:** Hast du weitere Pfeil- oder Kugelsorten dabei (z. B. Gefiederte Pfeile), erscheinen sie
  als kleine Symbole unter dem HUD – bessere Munition zuerst, passend zur Waffe (Bogen/Armbrust → Pfeile,
  Gewehr → Kugeln). Klick legt sie an – auch im Kampf (wie ein `/equip`-Makro). Welche Symbole da sind und
  wo die Leiste steht, wird nur außerhalb des Kampfes aktualisiert (Client-Regel); im Kampf zählen nur die Zahlen mit.

## Wie die Warnung funktioniert
Das HUD warnt, sobald dein Bestand auf den eingestellten Wert fällt – Standard **400 Schuss**,
im Menü (Seite *Warnung* → „Warnen ab“) oder per `/wfhud grenz <n>` frei einstellbar (0–3200).
Die Köchergröße spielt dafür keine Rolle; sie bestimmt nur, was als „voll“ gilt (Balken, Meldungen).

Solange du gar nichts schießt (oder deine Pfeile im Client nicht verbraucht werden),
warn es nicht – es erkennt nur echten Verbrauch.

## Installation
1. Im **Battle.net-Launcher**: *WoW Forever* → **„Im Finder zeigen"** (macOS) bzw.
   „Im Explorer zeigen" (Windows).
2. Diesen `WFAmmoHUD`-Ordner aus dem Downloads-Ordner in den `Interface/AddOns`-Ordner
   des Spiels kopieren (bei der Forever-Installation liegt der unter `_forever_`,
   also z. B. `…/World of Warcraft/_forever_/Interface/AddOns/WFAmmoHUD/`).
3. **Client neu starten** – ganz neue Addon-Ordner werden erst nach einem Neustart geladen
   (`/reload` genügt dafür nicht).
4. Auf dem Charakterbildschirm in der **Addon-Liste „WFAmmoHUD" aktivieren** und einloggen.

## Meldungen
Warnungen landen nicht im Chat, sondern als Meldung auf dem Bildschirm:

- **Mit Naowh Forever:** im Meldungsbereich von Naowh („Alerts“), dort wo auch Auffüll-Erinnerung,
  Begleiter-Tracker und Haltbarkeit erscheinen – mit derselben Schrift und demselben Hintergrund wie die
  Auffüll-Erinnerung. Verschieben über den HUD-Editor von Naowh (Eintrag „WFAmmoHUD – Munition“).
- **Ohne Naowh Forever:** an derselben Stelle (Bildschirmmitte, etwas oberhalb) im gewählten UI-Stil.

Was angezeigt wird:
- **Munition knapp** (orange) bzw. **Munition aufgebraucht!** (rot) – blinkt beim Erscheinen kurz und bleibt
  stehen, bis du nachgekauft hast.
- **Im Ruhebereich** (Gasthaus, Hauptstadt, außerhalb des Kampfes): dein aktueller Vorrat und wie viel
  noch in den Köcher passt. Ist der **Köcher/Munitionsbeutel voll** (alle Plätze mit vollen Stapeln),
  verschwindet die Meldung. Ohne Köcher gilt „voll“, sobald der Vorrat wieder den gemerkten Höchststand erreicht.
- **Vorrat aufgefüllt** bzw. **Köcher voll** – beim Nachkaufen, mit Vorrat / Köcherkapazität.
- **Raid-Check** – wenn du einem Raid beitrittst (oder deine Gruppe zum Raid wird) und beim Betreten einer
  Raid-Instanz: Vorrat gegen den empfohlenen Mindestbedarf. Akzentfarbe „reicht“, orange „zu wenig“, rot unter der Hälfte.
  Bleibt 60 Sekunden stehen (einstellbar 10–300).

### Wie viel Munition für einen Raid?
Richtwerte (Classic-Mechanik, Stapel 200, ca. 28–32 Schuss pro Minute im Kampf):
| Raid | Empfohlen mindestens |
|---|---|
| 20er (ZG, AQ20) | **1600** (8 Stapel) |
| 40er (MC, BWL, AQ40, Naxx) | **3200** (voller 16er-Köcher), komfortabel 4000 |

Die Werte sind voreingestellt und im Menü (Seite *Raid*) frei änderbar;
„Empfohlene Werte – Übernehmen“ setzt sie auf 1600 / 3200 zurück.

Quellen: Warcraft Tavern (Forever-Jäger-Guide, Munition & Köcher), warcraft.wiki.gg „Ammo“, Blizzard-Forum.

## Einstellungsmenü
`/wfhud` öffnet ein Einstellungsfenster im Stil von Naowh Forever. Alternativ
über das Addon-Menü an der Minimap oder unter *Optionen → AddOns → WFAmmoHUD*.

- **HUD:** HUD an/aus, Icon-Größe, Schriftgröße (Schieberegler oder Zahl eintippen), andere Munition anzeigen, Position zurücksetzen
- **Warnung:** „Warnen ab“ (Standard 400), aktueller Vorrat und Warnpunkt, sowie
  - *Im Meldungsbereich* (an): Warnungen erscheinen als Meldung statt im Chat
  - *Vorrat im Ruhebereich* (an): im Gasthaus / in der Stadt zeigt die Meldung, wie viel Munition du hast
  - *Zusätzlich im Chat* (aus) und *Warnton* (an)
- **Raid:** Raid-Check an/aus, Anzeigedauer der Meldung (Sekunden), Mindestvorrat für 20er- und 40er-Raids,
  Knopf „Prüfen“ zum Testen
- **Darstellung:** UI-Stil für Menü **und HUD** wählen. Das HUD übernimmt dann Hintergrund,
  Rahmenlinie, Textfarbe, Akzentfarbe (voller Balken) und Schriftart; Warnfarben (orange/rot)
  bleiben immer gleich.
  - *Automatisch* (Standard): Naowh Forever, falls geladen, sonst EllesmereUI, sonst Standard
  - *Naowh Forever*: übernimmt dein Naowh-Theme (Preset, eigene Farben oder Forever-Skin) und die Naowh-Schrift
  - *EllesmereUI*: übernimmt die EllesmereUI-Akzentfarbe, Grundfarben und globale Schrift
  - *Forever*: dunkles Braun mit Gold, unabhängig von anderen Addons
  - *Standard*: dunkel mit blauem Akzent
- Oben: **Warnung testen** (Ton + pulsierendes HUD) und **Standardwerte**
- Fenster per Kopfzeile verschiebbar, `Esc` schließt es.

## Befehle (Alias: `/munition`)
| Befehl | Wirkung |
|---|---|
| `/wfhud` | Einstellungsmenü öffnen/schließen |
| `/wfhud hilfe` | Status + Hilfe im Chat |
| `/wfhud test` | Testwarnung |
| `/wfhud raid` | Raid-Check jetzt ausführen |
| `/wfhud debug` | Diagnose der Munitionserkennung (Slot, Taschen, Ergebnis) |
| `/wfhud ein` / `aus` | HUD ein- bzw. ausblenden |
| `/wfhud grenz <n>` | warnen ab n Schuss, 0–3200 (Standard 400) |
| `/wfhud groesse <n>` | Icon-Größe 24–96 (Standard 44) |
| `/wfhud schrift <n>` | Schriftgröße der Zahl 10–36 (Standard 16) |
| `/wfhud sound ein` / `aus` | Warnton an/aus |
| `/wfhud reset` | HUD-Position auf Standard zurücksetzen |

Die Position speicherst du, indem du das HUD einfach per Maus ziehst.

## Hinweise
- Gebaut für den **Forever-Client 1.60.1** (TOC-Interface `16001`, moderne Addon-API).
- Falls in deinem Client Munition **nicht** verbraucht wird (Bestand bleibt immer „1"),
  zeigt das HUD einfach den Bestand an und warnt nicht – dann sind deine Pfeile unendlich.
- Änderst du `WFAmmoHUD.lua`, genügt `/reload`. Änderst du das TOC, bitte neu starten.

## Etwas kaputt?
Gib `/wfhud hilfe` ein – meldet das Addon einen Fehler, siehst du ihn direkt im Chat.
