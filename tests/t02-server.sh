# t02-server.sh: local server of the dialog (spec 03, Server) — token, Host, Origin, steps, language, end

   case "$SANDBOX" in */aibos-installer-test.*) ;; *) echo "*** run via tests/run, never directly" >&2; exit 1;; esac

   D="distribution-demo==1.0.0"
   OUT="$(start_installer "$D" "$COMMIT0" 2>&1)"; RC=$?
   assert_eq "$RC" "0" "start: exit 0"
   assert_eq "$OUT" "" "start: nothing on stdout (IN3)"
   assert_file "$HOME/.aibos/install/test-url"
   MODE="$(stat -f %Lp "$HOME/.aibos/install/test-url")"; assert_eq "$MODE" "600" "test-url: mode 600"
   status() { printf '%s' "$1" | head -1; }

#===============================================================================
# requests that are refused (403)
#===============================================================================

   assert_eq "$(status "$(client raw GET /)")" "403" "GET without token"
   assert_eq "$(status "$(client raw GET '/?t=wrong')")" "403" "GET with a wrong token"
   assert_eq "$(status "$(client raw GET '/?t=TOKEN' Host=evil.example)")" "403" "GET with a foreign Host"
   assert_eq "$(status "$(client raw GET '/other?t=TOKEN')")" "403" "GET of another path"
   assert_eq "$(status "$(client raw POST '/decision?t=TOKEN')")" "403" "POST without Origin"
   assert_eq "$(status "$(client raw POST '/decision?t=TOKEN' Origin=http://evil.example)")" "403" "POST with a foreign Origin"
   assert_eq "$(status "$(client raw PUT '/?t=TOKEN')")" "405" "PUT"

#===============================================================================
# page 1, language, decisions only for the current step (IN4)
#===============================================================================

   R="$(client get)"
   assert_eq "$(status "$R")" "200" "page 1: 200"
   assert_contains "$R" "<title>AIBOS-Installer</title>" "page 1: title (H14)"
   assert_not_contains "$R" "<script" "page 1: no JavaScript"
   R="$(client get lang=de)"
   assert_contains "$R" "Außerhalb des Arbeitsbereichs verhält sich deine KI wie ohne AIBOS." "page 1 de: outside as without AIBOS"
   assert_contains "$R" "Du installierst AIbex AIBOS mit der Distribution Demo V1.0 (distribution-demo @ v1.0.0)." "page 1 de: name, version line, tag"
   assert_contains "$R" "Distribution Demo V1.0 (distribution-demo @ v1.0.0)" "subtitle"
   assert_contains "$R" "Der Ordner ~/.aibos und deine Arbeitsbereiche bleiben dabei erhalten" "page 1 de: what stays after uninstall (H20)"
   R="$(client get lang=en)"
   assert_contains "$R" "Outside the workspace your AI behaves as without AIBOS." "page 1 en"
   R="$(client post step=3 choice=next mode=new name=X)"
   assert_eq "$(status "$R")" "303" "POST for another step: answered with 303"
   R="$(client get)"; assert_contains "$R" "Outside the workspace" "POST for another step: still page 1"
   R="$(client post step=1 choice=rm\ -rf\ /)"; R="$(client get)"
   assert_contains "$R" "Outside the workspace" "unknown choice: no effect"

#===============================================================================
# page 2 needs the checkbox
#===============================================================================

   client post step=1 choice=next >/dev/null
   R="$(client get lang=de)"
   assert_contains "$R" "Nutzungsvertrag, Version 1.2" "page 2: head with version"
   assert_not_contains "$R" "Entwurf, nicht juristisch geprüft" "page 2: no draft banner for 1.2"
   assert_contains "$R" "Gerichtsstand ist Innsbruck." "page 2: the agreement 1.2"
   client post step=2 choice=agree >/dev/null
   R="$(client get)"; assert_contains "$R" "Bitte bestätige mit dem Kästchen" "page 2: no consent without the checkbox"
   assert_nofile "$HOME/.aibos/consent/nutzungsvertrag-1.2.json"

#===============================================================================
# abort: result, end page, process gone (IN7, IN8)
#===============================================================================

   client post step=2 choice=abort >/dev/null
   R="$(client get)"; assert_contains "$R" "Geh zurück zu deiner KI" "end page"
   assert_eq "$(result_field status)" "aborted" "result: aborted"
   assert_eq "$(result_field step)" "2" "result: step 2"
   wait_until 10 no_installer && ok || fail "process ended (IN7)"
   assert_eq "$(status "$(client get)")" "000" "server closed"
