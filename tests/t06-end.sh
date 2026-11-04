# t06-end.sh: end of a run (spec 03, Server — Zeitgrenze, Ende; Ausweg Terminal): abort on page 1,
# time limit, switch to the terminal without a GET, temporary folders removed, no process left (IN7, IN8)

   case "$SANDBOX" in */aios-installer-test.*) ;; *) echo "*** run via tests/run, never directly" >&2; exit 1;; esac

   D="distribution-demo==1.0.0"
   work_left() { ls -d "${TMPDIR:-/tmp}"/aios-installer-work.* 2>/dev/null | wc -l | tr -d ' '; }
   BEFORE="$(work_left)"

#===============================================================================
# abort on page 1: result with step 1, nothing else written
#===============================================================================

   start_installer "$D" "$COMMIT0" >/dev/null
   client post step=1 choice=abort >/dev/null
   assert_eq "$(result_field status)" "aborted" "abort on page 1: aborted"
   assert_eq "$(result_field step)" "1" "abort on page 1: step"
   assert_eq "$(result_field consent)" "" "abort on page 1: no consent"
   assert_eq "$(ls "$HOME/.aios")" "install" "abort on page 1: only ~/.aios/install"
   wait_until 10 no_installer && ok || fail "abort on page 1: ended"

#===============================================================================
# time limit: without a request the run ends with timeout (shortened)
#===============================================================================

   AIOS_INSTALLER_TIMEOUT=2 start_installer "$D" "$COMMIT0" >/dev/null
   client get >/dev/null
   wait_until 20 no_installer && ok || fail "timeout: ended"
   assert_eq "$(result_field status)" "timeout" "timeout: status"

#===============================================================================
# switch to the terminal: no valid GET within the time (shortened), token invalid, command logged (F139)
#===============================================================================

   rm -f "$HOME/.aios/install/test-terminal"
   AIOS_INSTALLER_FALLBACK=1 start_installer "$D" "$COMMIT0" >/dev/null
   wait_until 20 no_installer && ok || fail "fallback: the server ended"
   assert_file "$HOME/.aios/install/test-terminal"
   T="$(cat "$HOME/.aios/install/test-terminal" 2>/dev/null)"
   assert_contains "$T" "open -a Terminal" "fallback: Terminal window"
   assert_contains "$T" "AIBOS-Installer.command" "fallback: script named after the window (H14)"
   assert_eq "$(client get | head -1)" "000" "fallback: browser address no longer served"
   S="$(printf '%s' "$T" | sed 's/^open -a Terminal //')"
   assert_contains "$(cat "$S" 2>/dev/null)" " 'tui' " "fallback: script runs the dialog as text"
   rm -rf "$(dirname "$S")"

#===============================================================================
# the dialog as text: the same steps in a terminal (stdin from a file)
#===============================================================================

   printf '1\nj\n1\n2\n' | "$PY" -I "$REPO/installer/aios_installer.py" tui "$D" "$COMMIT0" --home "$HOME" > "$SANDBOX/tui.out" 2>&1
   OUT="$(cat "$SANDBOX/tui.out")"
   assert_contains "$OUT" "AIBOS-Installer" "tui: title"
   assert_contains "$OUT" "1 " "tui: numbered choices"
   assert_file "$HOME/.aios/consent/nutzungsvertrag-1.1.json"
   W="$("$PY" -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["way"])' "$HOME/.aios/consent/nutzungsvertrag-1.1.json")"
   assert_eq "$W" "terminal" "tui: consent with way terminal"
   assert_eq "$(result_field status)" "aborted" "tui: end of input aborts"

#===============================================================================
# temporary work folders removed
#===============================================================================

   assert_eq "$(work_left)" "$BEFORE" "work folders removed"
