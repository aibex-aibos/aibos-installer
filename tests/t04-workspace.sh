# t04-workspace.sh: page 3, checks of the workspace (spec 05, Arbeitsbereich; spec 03, Meldungen auf Seite 3)

   case "$SANDBOX" in */aios-installer-test.*) ;; *) echo "*** run via tests/run, never directly" >&2; exit 1;; esac

   D="distribution-demo==1.0.0"
   printf 'name: distribution-demo\nversion: 1.0.0\ntype: distribution\n' > "$SANDBOX/no-kernel.yaml"
   export AIOS_INSTALLER_MANIFEST="$SANDBOX/no-kernel.yaml"     # valid choices end at the manifest (no kernel:)
   W="$HOME/work"; mkdir -p "$W/full/§Voll" "$W/§Vault/inner" "$W/plain" "$W/locked"
   touch "$W/full/§Voll/datei"
   chmod 000 "$W/locked"

   start_installer "$D" "$COMMIT0" >/dev/null
   client get lang=de >/dev/null
   client post step=1 choice=next >/dev/null
   client post step=2 choice=agree agree=on >/dev/null
   try() { client post step=3 choice=next "$@" >/dev/null; client get; }

#===============================================================================
# new workspace
#===============================================================================

   R="$(try mode=new "name=Probe Installer" parent="$W")"
   assert_contains "$R" "Erlaubt sind Buchstaben, Ziffern, - und _." "name with a space"
   R="$(try mode=new name=a/b parent="$W")"
   assert_contains "$R" "Erlaubt sind Buchstaben" "name with a slash"
   R="$(try mode=new name= parent="$W")"
   assert_contains "$R" "Erlaubt sind Buchstaben" "empty name"
   R="$(try mode=new name=Probe parent="$W/fehlt")"
   assert_contains "$R" "Den Ordner $W/fehlt gibt es nicht." "parent missing (F115)"
   assert_nofile "$W/fehlt"
   R="$(try mode=new name=Probe parent="$W/locked")"
   assert_contains "$R" "macOS erlaubt den Zugriff auf $W/locked nicht." "parent not readable"
   R="$(try mode=new name=Voll parent="$W/full")"
   assert_contains "$R" "gibt es schon und er ist nicht leer" "target not empty"
   R="$(try mode=new name=Innen parent="$W/§Vault/inner")"
   assert_contains "$R" "liegt im Arbeitsbereich $W/§Vault." "inside a vault"
   mkdir -p "$HOME/.aios/x"
   R="$(try mode=new name=Probe parent="$HOME/.aios/x")"
   assert_contains "$R" "liegt in ~/.aios." "inside ~/.aios"

#===============================================================================
# existing workspace
#===============================================================================

   R="$(try mode=existing path="$W/plain")"
   assert_contains "$R" "Ein Arbeitsbereich ist ein Ordner, dessen Name mit § beginnt. Benenne $W/plain um" "existing without §"
   R="$(try mode=existing path="$W/§Fehlt")"
   assert_contains "$R" "Den Ordner $W/§Fehlt gibt es nicht." "existing missing"
   R="$(try mode=existing path=)"
   assert_contains "$R" "gibt es nicht" "existing empty path"
   assert_contains "$R" "<h2>Arbeitsbereich</h2>" "still page 3 after errors"
   assert_not_contains "$R" "<option value=\"/" "no list without a kernel"

#===============================================================================
# a valid choice goes on: here it ends at the manifest without kernel: (F127)
#===============================================================================

   R="$(try mode=new name=Gültig_1 parent="~/work")"
   assert_eq "$(result_field status)" "failed" "manifest without kernel: failed"
   assert_contains "$(result_field message)" "names no kernel" "manifest without kernel: message"
   assert_eq "$(result_field vault)" "$W/§Gültig_1" "~ resolved, umlaut allowed (F132)"
   assert_nofile "$W/§Gültig_1"
   wait_until 10 no_installer && ok || fail "installer ended"
   chmod 755 "$W/locked"
