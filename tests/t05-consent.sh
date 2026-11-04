# t05-consent.sh: agreement and consent (spec 04); a further run skips page 2 (spec 01, Ablauf)

   case "$SANDBOX" in */aios-installer-test.*) ;; *) echo "*** run via tests/run, never directly" >&2; exit 1;; esac

   D="distribution-demo==1.0.0"
   C="$HOME/.aios/consent/nutzungsvertrag-0.1.json"
   field() { "$PY" -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$C" "$1"; }

#===============================================================================
# consent with the checkbox: file, fields, modes
#===============================================================================

   start_installer "$D" "$COMMIT0" >/dev/null
   client get lang=de >/dev/null
   client post step=1 choice=next >/dev/null
   client post step=2 choice=agree agree=on >/dev/null
   assert_file "$C"
   assert_eq "$(stat -f %Lp "$C")" "600" "consent: file mode 600"
   assert_eq "$(stat -f %Lp "$HOME/.aios/consent")" "700" "consent: folder mode 700"
   assert_eq "$(field version)" "0.1" "consent: version"
   assert_eq "$(field draft)" "True" "consent: draft"
   assert_eq "$(field language)" "de" "consent: language"
   assert_eq "$(field way)" "test" "consent: way test in test mode"
   assert_eq "$(field installer)" "0.1.0" "consent: installer version"
   assert_eq "$(field distribution)" "distribution-demo" "consent: distribution"
   assert_eq "$(field user)" "$(id -un)" "consent: login name"
   SUM="$(shasum -a 256 "$REPO/legal/nutzungsvertrag.de.md" | cut -d' ' -f1)"
   assert_eq "$(field sha256)" "$SUM" "consent: sha256 of the German text shown"
   R="$(client get)"; assert_contains "$R" "Arbeitsbereich" "after consent: page 3"
   client post step=3 choice=abort >/dev/null
   wait_until 10 no_installer && ok || fail "first run ended"
   assert_eq "$(result_field consent)" "$C" "result: names the consent"

#===============================================================================
# further run: page 2 is skipped for the same version
#===============================================================================

   start_installer "$D" "$COMMIT0" >/dev/null
   client post step=1 choice=next >/dev/null
   R="$(client get lang=de)"
   assert_contains "$R" "<h2>Arbeitsbereich</h2>" "further run: page 2 skipped"
   client post step=3 choice=abort >/dev/null
   wait_until 10 no_installer && ok || fail "second run ended"

#===============================================================================
# new version of the agreement asks again (copy of the repo with legal/VERSION 0.2)
#===============================================================================

   COPY="$SANDBOX/repo"; mkdir -p "$COPY"; cp -R "$REPO/installer" "$REPO/i18n" "$REPO/legal" "$COPY/"
   echo "0.2" > "$COPY/legal/VERSION"
   "$PY" -I "$COPY/installer/aios_installer.py" start "$D" "$COMMIT0" >/dev/null
   client post step=1 choice=next >/dev/null
   R="$(client get lang=de)"
   assert_contains "$R" "Nutzungsvertrag, Version 0.2" "new version: page 2 again"
   client post step=2 choice=agree agree=on >/dev/null
   assert_file "$HOME/.aios/consent/nutzungsvertrag-0.2.json"
   assert_file "$C"
   client post step=3 choice=abort >/dev/null
   wait_until 10 no_installer && ok || fail "third run ended"
