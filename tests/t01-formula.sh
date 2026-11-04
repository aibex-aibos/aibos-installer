# t01-formula.sh: install.sh (spec 02, Formel) — arguments, macOS, Python, git, asset, start, message

   case "$SANDBOX" in */aios-installer-test.*) ;; *) echo "*** run via tests/run, never directly" >&2; exit 1;; esac

#===============================================================================
# setup: fake programs, an asset built from the repo and a formula with its checksum
#===============================================================================

   FAKE="$SANDBOX/fake"; mkdir -p "$FAKE"
   SH() { "$SANDBOX/sh-env" sh "$SANDBOX/install.sh" "$@"; }
   printf '#!/bin/sh\nexec env PATH="%s:/usr/bin:/bin:/usr/sbin:/sbin" "$@"\n' "$FAKE" > "$SANDBOX/sh-env"; chmod +x "$SANDBOX/sh-env"
   ASSET="$SANDBOX/asset.tar.gz"
   (cd "$REPO" && COPYFILE_DISABLE=1 tar -czf "$ASSET" installer i18n legal)
   SUM="$(shasum -a 256 "$ASSET" | cut -d' ' -f1)"
   sed "s/^ASSET_SHA256=.*/ASSET_SHA256=\"$SUM\"/" "$REPO/install.sh" > "$SANDBOX/install.sh"
   export AIOS_INSTALLER_ASSET="$ASSET"
   export AIOS_INSTALLER_PYTHONS="$PY"
   D="distribution-demo==1.0.0"; C="0123456789abcdef0123456789abcdef01234567"
   nothing_written() { [ -z "$(ls -A "$HOME")" ] && ok || fail "$1: something written to HOME: $(ls -A "$HOME")"; }
   tmp_left() { ls -d "${TMPDIR:-/tmp}"/aios-installer.* 2>/dev/null | wc -l | tr -d ' '; }
   BEFORE="$(tmp_left)"

#===============================================================================
# step 1: arguments
#===============================================================================

   OUT="$(SH 2>&1)"; assert_eq "$?" "2" "no arguments: exit 2"
   assert_contains "$OUT" "usage: sh install.sh" "no arguments: usage"
   OUT="$(SH distribution-demo "$C" 2>&1)"; assert_eq "$?" "2" "no version: exit 2"
   assert_contains "$OUT" "not a distribution with version" "no version: message"
   OUT="$(SH "skill-x==1.0.0" "$C" 2>&1)"; assert_eq "$?" "2" "not a distribution: exit 2"
   OUT="$(SH "$D" abc 2>&1)"; assert_eq "$?" "2" "short commit: exit 2"
   assert_contains "$OUT" "not a full commit hash" "short commit: message"
   SH "distribution-demo==1.0.0-rc2" abc >/dev/null 2>&1; assert_eq "$?" "2" "candidate accepted as version, commit still checked"
   nothing_written "arguments"

#===============================================================================
# step 2: macOS only (fake uname)
#===============================================================================

   printf '#!/bin/sh\necho Linux\n' > "$FAKE/uname"; chmod +x "$FAKE/uname"
   OUT="$(SH "$D" "$C" 2>&1)"; assert_eq "$?" "2" "Linux: exit 2"
   assert_contains "$OUT" "supports macOS only" "Linux: message"
   rm "$FAKE/uname"

#===============================================================================
# step 3: Python >= 3.11
#===============================================================================

   printf '#!/bin/sh\ncase "$*" in *version_info\\ \\<*) exit 1;; *print*) echo 3.9.6;; esac\n' > "$FAKE/python-old"; chmod +x "$FAKE/python-old"
   OUT="$(AIOS_INSTALLER_PYTHONS="$FAKE/python-old /nowhere/python3" SH "$D" "$C" 2>&1)"; assert_eq "$?" "3" "old Python: exit 3"
   assert_contains "$OUT" "Python 3.11 or newer is required, found: 3.9.6 ($FAKE/python-old)" "old Python: found version"
   assert_contains "$OUT" "brew install python" "old Python: a way"
   assert_contains "$OUT" "Nothing has been installed." "old Python: nothing installed"
   OUT="$(AIOS_INSTALLER_PYTHONS="/nowhere/python3" SH "$D" "$C" 2>&1)"; assert_eq "$?" "3" "no Python: exit 3"
   assert_contains "$OUT" "found: none" "no Python: none"
   nothing_written "Python"

#===============================================================================
# step 4: git via xcode-select (fake: no Command Line Tools)
#===============================================================================

   printf '#!/bin/sh\nexit 2\n' > "$FAKE/xcode-select"; chmod +x "$FAKE/xcode-select"
   printf '#!/bin/sh\necho "git must not be called" >> "%s/git-called"; exit 1\n' "$SANDBOX" > "$FAKE/git"; chmod +x "$FAKE/git"
   OUT="$(SH "$D" "$C" 2>&1)"; assert_eq "$?" "4" "no Command Line Tools: exit 4"
   assert_contains "$OUT" "xcode-select --install" "no Command Line Tools: way"
   assert_nofile "$SANDBOX/git-called"
   rm "$FAKE/xcode-select" "$FAKE/git"
   nothing_written "git"

#===============================================================================
# step 5: asset checksum
#===============================================================================

   printf 'tampered' >> "$SANDBOX/bad.tar.gz"; cat "$ASSET" >> "$SANDBOX/bad.tar.gz"
   OUT="$(AIOS_INSTALLER_ASSET="$SANDBOX/bad.tar.gz" SH "$D" "$C" 2>&1)"; assert_eq "$?" "5" "bad asset: exit 5"
   assert_contains "$OUT" "checksum does not match" "bad asset: message"
   OUT="$(AIOS_INSTALLER_ASSET="$SANDBOX/missing.tar.gz" SH "$D" "$C" 2>&1)"; assert_eq "$?" "5" "missing asset: exit 5"
   nothing_written "asset"
   assert_eq "$(tmp_left)" "$BEFORE" "failures leave no temporary folder"

#===============================================================================
# steps 6, 7: start and message (test mode: test-url instead of a browser)
#===============================================================================

   OUT="$(SH "$D" "$C" 2>&1)"; RC=$?
   assert_eq "$RC" "0" "start: exit 0"
   assert_contains "$OUT" 'in the browser window
"AIOS-Installer"' "start: message names the window"
   assert_contains "$OUT" "read ~/.aios/install/result.json" "start: message names the result"
   assert_file "$HOME/.aios/install/test-url"
   TOKEN="$(sed 's/.*t=//' "$HOME/.aios/install/test-url")"
   assert_not_contains "$OUT" "$TOKEN" "start: token not on stdout (IN3)"
   assert_not_contains "$OUT" "127.0.0.1" "start: address not on stdout"
   R="$(client get)"; assert_eq "$(printf '%s' "$R" | head -1)" "200" "start: the dialog answers"
   client post step=1 choice=abort >/dev/null
   wait_until 10 no_installer && ok || fail "start: installer ended after abort"
   assert_eq "$(tmp_left)" "$BEFORE" "start: temporary folder of the formula removed at the end"

#===============================================================================
# test switch: refused outside a sandbox HOME
#===============================================================================

   OUT="$(HOME=/Users/nobody-here SH "$D" "$C" 2>&1)"; assert_eq "$?" "2" "test switch with a real HOME: exit 2"
   assert_contains "$OUT" "test mode needs a HOME below the temporary folder" "test switch: message"
   OUT="$(AIOS_HUBS= SH "$D" "$C" 2>&1)"; assert_eq "$?" "2" "test switch without AIOS_HUBS: exit 2"
