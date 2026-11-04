# Nutzungsvertrag für AIbex AIOS

Version 0.1 — Entwurf, nicht juristisch geprüft

## 1. Vertragsparteien

Dieser Vertrag gilt zwischen der AIbex KG, [Anschrift] („AIbex"), und der Person, die AIbex AIOS mit dem Installer installiert („du").

## 2. Gegenstand

AIbex AIOS ist eine Erweiterung für KI-Assistenten wie Claude Code. Es besteht aus einem Kernel, Paketen und einer Distribution. Die Pakete stehen unter ihren eigenen Lizenzen (in der Regel Apache-2.0); dieser Vertrag regelt die Nutzung von AIOS als Ganzes und die Installation mit dem Installer.

## 3. Was AIOS verändert

Mit der Installation trägt AIOS Hooks in die Einstellungen deiner KI ein und richtet einen Arbeitsbereich ein. In diesem Arbeitsbereich ändert AIOS das Verhalten deiner KI grundlegend: Es lädt Wissen und Regeln in jede Sitzung, stellt Befehle bereit und kann Assistenten zuordnen. Außerhalb des Arbeitsbereichs soll sich deine KI wie ohne AIOS verhalten. AIOS schreibt nur in den Ordner `~/.aios`, in deine Arbeitsbereiche und in die eigenen Einträge in `~/.claude/settings.json`.

## 4. Deine Verantwortung

Du entscheidest, welche Arbeitsbereiche du anlegst und was deine KI dort tut. Die Antworten und Handlungen einer KI können falsch sein; prüfe sie, bevor du dich auf sie verlässt. Für den Dienst deiner KI (z. B. Claude von Anthropic) gelten dessen eigene Bedingungen.

## 5. Haftung

AIOS wird ohne Gewähr bereitgestellt. AIbex haftet nicht für Schäden aus der Nutzung von AIOS oder aus dem Verhalten einer KI, die AIOS nutzt, soweit das gesetzlich zulässig ist. [Ausnahmen nach zwingendem Recht, etwa für Vorsatz und grobe Fahrlässigkeit, ergänzt die juristische Prüfung.]

## 6. Rückweg

Du kannst AIOS jederzeit mit `~/.aios/bin/aios --uninstall` entfernen und danach den Ordner `~/.aios` löschen. Deine Arbeitsbereiche bleiben erhalten.

## 7. Änderungen dieses Vertrags

Eine neue Version dieses Vertrags gilt erst, wenn du ihr bei einer Installation zustimmst.

## 8. Recht und Gerichtsstand

[Anwendbares Recht und Gerichtsstand ergänzt die juristische Prüfung.]
