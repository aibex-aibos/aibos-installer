# Usage agreement for AIbex AIOS

Version 1.0. Translation; the German version is authoritative.

## 1. Parties

This agreement applies between AIbex KG, Bergstrasse 27, 6342 Niederndorf, Austria, FN 676512 x ("AIbex"), and the person who installs AIbex AIOS with the installer ("you").

## 2. Subject

AIbex AIOS is an extension for AI assistants such as Claude Code. It consists of a kernel, packages and a distribution. The packages are under their own licences (usually Apache-2.0); this agreement governs the use of AIOS as a whole and the installation with the installer.

## 3. What AIOS changes

With the installation AIOS adds hooks to the settings of your AI and sets up a workspace. In this workspace AIOS fundamentally changes the behaviour of your AI: it loads knowledge and rules into every session, provides commands and can assign assistants. Outside the workspace your AI is meant to behave as without AIOS. AIOS writes only to the folder `~/.aios`, to your workspaces and to its own entries in `~/.claude/settings.json`.

## 4. Your responsibility

You decide which workspaces you create and what your AI does there. The answers and actions of an AI can be wrong; check them before you rely on them. The service of your AI (e.g. Claude by Anthropic) is subject to its own terms.

## 5. Liability

AIOS is provided without warranty. AIbex is not liable for damage from the use of AIOS or from the behaviour of an AI that uses AIOS, as far as the law permits. Excluded from this are damages caused by intent or gross negligence and personal injury.

## 6. Way back

You can remove AIOS at any time with `~/.aios/bin/aios --uninstall` and then delete the folder `~/.aios`. Your workspaces are kept.

## 7. Changes to this agreement

A new version of this agreement applies only when you accept it during an installation.

## 8. Law and jurisdiction

Austrian law applies, excluding the UN Convention on Contracts for the International Sale of Goods and the conflict-of-law rules. Place of jurisdiction is Innsbruck.
