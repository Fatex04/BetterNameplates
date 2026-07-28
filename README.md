# BetterNameplates
WoW Classic Addon

Aktuelle Version: V1.1

V1.1 aktualisiert die Threat-Anzeige alle 0,1 Sekunden, stabilisiert sie bei
niedrigen Bildraten und korrigiert die dynamische Skalierung über den
0–100-%-Threatwert. Nameplate-Funktionen lassen sich unabhängig von Threat
abschalten. Die Einstellungen enthalten außerdem Live-Vorschauen und eine
Bestätigung vor dem Zurücksetzen. Der Threat-Tab verwendet das blaue
Katzen-Icon von Details Tiny Threat; die Anzeige auf Nameplates bleibt textbasiert.
Echte neue Threat-Werte ersetzen den kurzen Flackerschutz sofort, sodass 100 %
nach einem Aggro-Wechsel nicht mehr aus dem Cache stehen bleiben.
Level lassen sich unabhängig skalieren, lange Namen werden mit `...` gekürzt,
und alle Regler zeigen ihren jeweiligen Standardwert exakt an der Reglerposition.
Auch Namen und sichtbare HP-Zahlen lassen sich getrennt skalieren; die Kürzung
reserviert automatisch die tatsächlich benötigte Breite der HP-Zahl.
BNP erkennt dafür die unterschiedlichen Blizzard-Healthbar-Strukturen und
ändert die tatsächliche Fontgröße statt nur die Skalierung des Regionsrahmens.
Eine Kompatibilitätsschicht synchronisiert die BNP-Regler direkt mit den
zuständigen BetterBlizzPlates-Werten und aktualisiert dessen internen Cache.
Level-Farben und Totenköpfe folgen der Blizzard-Classic-Logik; Verbündete zeigen
immer ihr verfügbares Zahlenlevel. Das Einstellungsfenster ist unten rechts
skalierbar und merkt sich Größe sowie Position.
