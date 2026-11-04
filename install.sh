#!/bin/sh
# install.sh: formula of the AIBOS installer (spec 02, Einstieg und Formel)
# usage: sh install.sh "distribution-<name>==<version>" <commit of the kernel tag>
# POSIX sh on purpose: it must run and report on a Mac without Python 3.11 or git.

VERSION="0.1.0-rc1"
ASSET_SHA256="f6c1fa876ab0d3dafe83a0cdcf86891d0d1f64bebae001acb9805c1875fd6246"
ASSET_URL="https://github.com/aibex-aios/aios-installer/releases/download/v$VERSION/aios-installer-$VERSION.tar.gz"

TMPROOT=""
cleanup() { [ -n "$TMPROOT" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"; }
fail() { code="$1"; shift; for l in "$@"; do printf '%s\n' "$l"; done; cleanup; exit "$code"; }

#===============================================================================
# test switch (spec 06): only with AIOS_HUBS and a HOME below the temporary folder
#===============================================================================

TEST=""
if [ "${AIOS_INSTALLER_TEST:-}" = "1" ]; then
   T="${TMPDIR:-/tmp}"; T="${T%/}"
   case "$HOME" in
      "$T"/*|/tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) ;;
      *) fail 2 "AIBOS installer: test mode needs a HOME below the temporary folder. Nothing has been installed." ;;
   esac
   [ -n "${AIOS_HUBS:-}" ] || fail 2 "AIBOS installer: test mode needs AIOS_HUBS. Nothing has been installed."
   TEST=1
fi

#===============================================================================
# step 1: arguments
#===============================================================================

USAGE='AIBOS installer: usage: sh install.sh "distribution-<name>==<version>" <commit of the kernel>'
[ $# -eq 2 ] || fail 2 "$USAGE" "Nothing has been installed."
printf '%s' "$1" | grep -Eq '^distribution-[a-z0-9][a-z0-9-]*==[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$' \
   || fail 2 "AIBOS installer: not a distribution with version: $1" "$USAGE" "Nothing has been installed."
printf '%s' "$2" | grep -Eq '^[0-9a-f]{40}$' \
   || fail 2 "AIBOS installer: not a full commit hash (40 hex digits): $2" "$USAGE" "Nothing has been installed."

#===============================================================================
# step 2: macOS only
#===============================================================================

[ "$(uname -s 2>/dev/null)" = "Darwin" ] || fail 2 "AIBOS installer: this installer supports macOS only. Nothing has been installed."

#===============================================================================
# step 3: Python >= 3.11 (PATH, Homebrew, /usr/local, python.org)
#===============================================================================

CANDIDATES="python3 /opt/homebrew/bin/python3 /usr/local/bin/python3 /Library/Frameworks/Python.framework/Versions/Current/bin/python3"
[ -n "$TEST" ] && [ -n "${AIOS_INSTALLER_PYTHONS+x}" ] && CANDIDATES="$AIOS_INSTALLER_PYTHONS"
PY=""; FOUND=""
for C in $CANDIDATES; do
   P="$(command -v "$C" 2>/dev/null)" || continue
   [ -x "$P" ] || continue
   V="$("$P" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null)" || continue
   FOUND="${FOUND:+$FOUND, }$V ($P)"
   if "$P" -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null; then PY="$P"; break; fi
done
[ -n "$PY" ] || fail 3 "AIBOS installer: Python 3.11 or newer is required, found: ${FOUND:-none}." \
   "Install it from https://www.python.org/downloads/macos/ or with Homebrew (brew install python)," \
   "then run the same command again. Nothing has been installed."

#===============================================================================
# step 4: git, checked via xcode-select first (no dialog of macOS before the report)
#===============================================================================

{ xcode-select -p >/dev/null 2>&1 && git --version >/dev/null 2>&1; } \
   || fail 4 "AIBOS installer: git is required (Command Line Tools for Xcode)." \
             "Install them with: xcode-select --install" \
             "then run the same command again. Nothing has been installed."

#===============================================================================
# step 5: release asset into a temporary folder, checked against ASSET_SHA256
#===============================================================================

T="${TMPDIR:-/tmp}"
TMPROOT="$(mktemp -d "${T%/}/aios-installer.XXXXXX")" || fail 5 "AIBOS installer: no temporary folder. Nothing has been installed."
ASSET="$TMPROOT/aios-installer-$VERSION.tar.gz"
DOWNLOAD_FAILED="AIBOS installer: the download of aios-installer-$VERSION.tar.gz failed or its checksum does not match."
if [ -n "$TEST" ] && [ -n "${AIOS_INSTALLER_ASSET:-}" ]; then
   cp "$AIOS_INSTALLER_ASSET" "$ASSET" 2>/dev/null || fail 5 "$DOWNLOAD_FAILED" "Nothing has been installed."
else
   curl -fsSL "$ASSET_URL" -o "$ASSET" 2>/dev/null \
      || fail 5 "$DOWNLOAD_FAILED" "Nothing has been installed. Check the network and run the same command again."
fi
SUM="$(shasum -a 256 "$ASSET" | cut -d' ' -f1)"
[ "$SUM" = "$ASSET_SHA256" ] || fail 5 "$DOWNLOAD_FAILED" "Nothing has been installed."
tar -xzf "$ASSET" -C "$TMPROOT" 2>/dev/null && [ -f "$TMPROOT/installer/aios_installer.py" ] \
   || fail 5 "AIBOS installer: the release asset is incomplete. Nothing has been installed."

#===============================================================================
# step 6: start the installer detached; it reports over a pipe whether it runs
#===============================================================================

"$PY" -I "$TMPROOT/installer/aios_installer.py" start "$1" "$2" --cleanup "$TMPROOT" \
   || fail 6 "AIBOS installer: the installer did not start. Nothing has been installed."

#===============================================================================
# step 7: message for the AI
#===============================================================================

cat <<'EOF'
AIBOS installer started. The dialog runs outside of this chat, in the browser window
"AIBOS-Installer" (or, if no browser opened, in a Terminal window of the same name).
Tell the user to complete the dialog there, then come back and write "fertig" (or "done").
When the user does, read ~/.aios/install/result.json and report it to the user.
Do not answer the dialog yourself and do not run any other install command.
EOF
exit 0
