#!/bin/bash
# lib.sh: helpers for the installer tests (sandbox, assertions, client); sourced by tests/run

   REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

#===============================================================================
# sandbox: fresh HOME under the temporary folder, test switch on, no network
#===============================================================================

   sandbox_new() {
      SANDBOX="$(T="${TMPDIR:-/tmp}"; cd "$(mktemp -d "${T%/}/aios-installer-test.XXXXXX")" && pwd -P)" || exit 1
      export HOME="$SANDBOX/home"
      export AIOS_PREFIX="$SANDBOX/opt/aios"
      export AIOS_CLAUDE_DIR="$HOME/.claude"
      export AIOS_INSTALLER_TEST=1
      export AIOS_INSTALLER_TERMINAL=log
      export AIOS_HUBS="aibex-aios=file://$SANDBOX/hubs/aibex-aios"
      unset AIOS_INSTALLER_ASSET AIOS_INSTALLER_KERNEL_REPO AIOS_INSTALLER_MANIFEST AIOS_INSTALLER_PYTHONS
      unset AIOS_INSTALLER_TIMEOUT AIOS_INSTALLER_FALLBACK
      mkdir -p "$HOME"
      cd "$SANDBOX" || exit 1             # never inherit the caller's cwd
      PY="$(find_python)"
   }

   sandbox_drop() {
      stop_installers
      case "$SANDBOX" in
         */aios-installer-test.*) chmod -R u+rwx "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX" ;;
      esac
   }

   find_python() {                       # a python3 >= 3.11 (the installer needs it)
      local P
      for P in $(type -ap python3) /opt/homebrew/bin/python3 /usr/local/bin/python3; do
         [ -x "$P" ] && "$P" -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null && { echo "$P"; return; }
      done
   }

#===============================================================================
# assertions: count passes and failures, print one line per failure
#===============================================================================

   PASS=0; FAIL=0

   ok()   { PASS=$((PASS+1)); }
   fail() { FAIL=$((FAIL+1)); printf '   \033[31mFAIL\033[0m %s\n' "$*"; }

   assert_file()   { [ -f "$1" ] && ok || fail "missing file: $1"; }
   assert_nofile() { [ ! -e "$1" ] && ok || fail "should not exist: $1"; }
   assert_dir()    { [ -d "$1" ] && ok || fail "missing dir: $1"; }
   assert_eq()     { [ "$1" == "$2" ] && ok || fail "$3: expected [$2], got [$1]"; }
   assert_contains() { case "$1" in *"$2"*) ok ;; *) fail "$3: [$2] not in output" ;; esac; }
   assert_not_contains() { case "$1" in *"$2"*) fail "$3: [$2] in output" ;; *) ok ;; esac; }

#===============================================================================
# installer: start detached from the repo, talk to it over HTTP, stop it
#===============================================================================

   COMMIT0="0000000000000000000000000000000000000000"

   start_installer() {                   # start_installer <dist==version> <commit>: start, wait for test-url
      "$PY" -I "$REPO/installer/aios_installer.py" start "$@"
   }

   client() {                            # client get|post [field=value ...]: request to the running installer
      "$PY" -I "$REPO/tests/client.py" "$HOME/.aios/install/test-url" "$@"
   }

   wait_until() {                        # wait_until <seconds> <command...>: poll every 0.2 s
      local N=$(( $1 * 5 )); shift
      while [ "$N" -gt 0 ]; do "$@" >/dev/null 2>&1 && return 0; N=$((N-1)); sleep 0.2; done
      return 1
   }

   no_installer() { ! pgrep -fl "aios_installer.py" 2>/dev/null | grep -q -- "--home $HOME"; }

   stop_installers() {
      local P
      for P in $(pgrep -f "aios_installer.py" 2>/dev/null); do
         ps -p "$P" -o command= 2>/dev/null | grep -q -- "--home $HOME" && kill "$P" 2>/dev/null
      done
      return 0
   }

   result_field() {                      # result_field <key>: value from ~/.aios/install/result.json
      "$PY" -I -c 'import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2]); print("" if v is None else (str(v).lower() if isinstance(v,bool) else v))' \
         "$HOME/.aios/install/result.json" "$1" 2>/dev/null
   }
