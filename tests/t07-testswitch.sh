# t07-testswitch.sh: test switch only in a sandbox (spec 06, Testschalter; F122); overrides ignored outside test mode

   case "$SANDBOX" in */aios-installer-test.*) ;; *) echo "*** run via tests/run, never directly" >&2; exit 1;; esac

   D="distribution-demo==1.0.0"
   I="$REPO/installer/aios_installer.py"

#===============================================================================
# the installer refuses the test switch without a sandbox HOME or without AIOS_HUBS, writes nothing
#===============================================================================

   OUT="$(HOME=/Users/Shared "$PY" -I "$I" start "$D" "$COMMIT0" 2>&1)"; RC=$?
   assert_eq "$RC" "2" "real HOME: exit 2"
   assert_contains "$OUT" "test mode needs a HOME below the temporary folder" "real HOME: message"
   OUT="$(AIOS_HUBS= "$PY" -I "$I" start "$D" "$COMMIT0" 2>&1)"; RC=$?
   assert_eq "$RC" "2" "no AIOS_HUBS: exit 2"
   assert_contains "$OUT" "test mode needs AIOS_HUBS" "no AIOS_HUBS: message"
   assert_nofile "$HOME/.aios"
   OUT="$(HOME=/Users/Shared "$PY" -I "$I" tui "$D" "$COMMIT0" --home /Users/Shared </dev/null 2>&1)"; RC=$?
   assert_eq "$RC" "1" "tui with a real HOME: refused"
   assert_contains "$OUT" "test mode needs a HOME" "tui with a real HOME: message"

#===============================================================================
# bad arguments
#===============================================================================

   OUT="$("$PY" -I "$I" start "distribution-demo" "$COMMIT0" 2>&1)"; assert_eq "$?" "2" "start without version: exit 2"
   OUT="$("$PY" -I "$I" start "$D" abc 2>&1)"; assert_eq "$?" "2" "start with a short commit: exit 2"
   OUT="$("$PY" -I "$I" fly "$D" "$COMMIT0" 2>&1)"; assert_eq "$?" "2" "unknown command: exit 2"

#===============================================================================
# outside test mode the test variables have no effect (checked in the code paths)
#===============================================================================

   OUT="$(cd "$REPO/installer" && AIOS_INSTALLER_TEST= AIOS_INSTALLER_MANIFEST="$SANDBOX/x.yaml" AIOS_INSTALLER_KERNEL_REPO="$SANDBOX/k" \
          "$PY" -I -c 'import sys; sys.path.insert(0, "."); import steps; from pathlib import Path
r = steps.Run(Path(".."), Path(sys.argv[1]), "distribution-demo==1.0.0", "0"*40, "0.1.0", False, "browser")
print(r.kernel_repo())
r.close()' "$HOME" 2>&1)"
   assert_eq "$OUT" "https://github.com/aibex-aios/aibex-aios" "outside test mode: the real kernel repository"
   SH_OUT="$(grep -c 'TEST" \] && \[ -n "${AIOS_INSTALLER' "$REPO/install.sh")"
   assert_eq "$SH_OUT" "2" "install.sh: both overrides only with the test switch"
