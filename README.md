# aibos-installer

Installer für Distributionen von AIbex AIBOS, Version 0.2.0. Er installiert eine Distribution auf einem Mac, auf dem Claude Code läuft: Die KI führt **eine** Zeile aus dem README der Distribution aus, den Dialog mit Hinweis, Nutzungsvertrag, Wahl des Arbeitsbereichs und finaler Zustimmung führt der Installer im Browser, außerhalb der KI. Installiert wird mit dem Kernel von AIBOS (`aibos --install`).

## Benutzen

Im README einer Distribution steht eine Zeile wie diese (Version, Prüfsummen und Commit setzt `tools/release.sh`):

```sh
f=$(mktemp) && curl -fsSL https://raw.githubusercontent.com/aibex-aibos/aibos-installer/v<v>/install.sh -o "$f" && echo "<sha256>  $f" | shasum -a 256 -c - && sh "$f" "distribution-<name>==<version>" <commit des kernels>
```

Sag deiner KI etwa „Installiere Capricorn von github.com/aibex-aibos/distribution-capricorn", oder führe die Zeile im Terminal aus. Der Installer öffnet ein Fenster „AIBOS-Installer"; wenn er fertig ist, schreib deiner KI „fertig".

Voraussetzungen: macOS, Python ≥ 3.11, `git` (Command Line Tools). Fehlt etwas, meldet die Formel es und installiert nichts.

## Was wohin kommt

| Ort | Inhalt |
|---|---|
| temporärer Ordner | Formel und Installer während des Laufs; danach entfernt |
| `~/.aibos/consent/` | Zustimmung zum Nutzungsvertrag |
| `~/.aibos/install/` | `result.json` des letzten Laufs, Protokolle |
| `~/.aibos/installer/aibex-aibos/` | Klon des Kernels |
| alles Übrige | schreibt der Kernel (`~/.aibos`, der Arbeitsbereich, eigene Einträge in `~/.claude/settings.json`) |

## Entwickeln

- Spec: Konzept-Repo `aibex-aibos/AA-AIbex-AIOS`, `@Spec/Installer/01–06`.
- Tests: `tests/run [<präfix>]`, je Test ein Sandkasten, ohne Netzwerk; Testdateien nie direkt starten.
- Release: `tools/release.sh <version> [distribution-<name>==<dv> <commit>]`.

## Lizenz

Code: Apache-2.0, siehe `LICENSE` und `NOTICE`. Der Nutzungsvertrag in `legal/` ist nicht Teil dieser Lizenz.
