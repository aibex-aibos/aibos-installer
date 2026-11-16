# t09-changeover.sh: a machine with AIOS 0.6 (~/.aios a folder): the installer writes nothing into ~/.aibos
# before the kernel; page 4a shows the changeover of the kernel, which moves ~/.aios to ~/.aibos with a link
# (Konzept-Repo AA-AIbex-AIOS, V0.7, memos 33, 34: F320; spec 04 of the kernel, Umstieg auf v0.7)

   case "$SANDBOX" in */aibos-installer-test.*) ;; *) echo "*** run via tests/run, never directly" >&2; exit 1;; esac

   for K_SRC in "$AIBOS_INSTALLER_KERNEL_SRC" "$(dirname "$REPO")/aibex-aibos" "$(dirname "$REPO")/aibex-aios"; do
      [ -x "$K_SRC/bin/aibos" ] && break
   done
   if [ ! -x "$K_SRC/bin/aibos" ] || [ ! -x "$K_SRC/tests/hub/build" ]; then
      echo "   skipped: no clone of aibex-aibos next to this repo (set AIBOS_INSTALLER_KERNEL_SRC)"; ok; return 0 2>/dev/null || exit 0
   fi

#===============================================================================
# setup as in t03; ~/.aios of AIOS 0.6 as a plain folder with a marker
#===============================================================================

   PYDIR=""
   for P in $(type -ap python3) /opt/homebrew/bin/python3 /usr/local/bin/python3; do
      [ -x "$P" ] && "$P" -c "import yaml, venv, ensurepip, sys; sys.exit(sys.version_info < (3, 11))" 2>/dev/null && { PYDIR="$(dirname "$P")"; break; }
   done
   [ -n "$PYDIR" ] && ok || { fail "t09 needs a python3 >= 3.11 with PyYAML"; return 0 2>/dev/null || exit 0; }
   mkdir -p "$SANDBOX/fake" "$SANDBOX/stup-src"
   printf '#!/bin/sh\nexit 1\n' > "$SANDBOX/fake/no-sudo"; chmod +x "$SANDBOX/fake/no-sudo"
   export PATH="$PYDIR:$SANDBOX/fake:/usr/bin:/bin:/usr/sbin:/sbin"
   YAML_DIR="$("$PYDIR/python3" -c 'import os, yaml; print(os.path.dirname(os.path.dirname(yaml.__file__)))')"
   printf '#!/bin/sh\nfor S in "$(dirname "$1")"/lib/python3*/site-packages; do echo "%s" > "$S/test-yaml.pth"; done\n' "$YAML_DIR" > "$SANDBOX/fake/pip"
   chmod +x "$SANDBOX/fake/pip"
   export AIBOS_SUDO="$SANDBOX/fake/no-sudo" AIBOS_PIP="$SANDBOX/fake/pip" AIBOS_STUP_URL="file://$SANDBOX/stup-src/stup"
   "$K_SRC/tests/hub/build" "$SANDBOX/hubs" >/dev/null
   export AIBOS_PIP_FIND_LINKS="$SANDBOX/hubs/wheels"
   S="$SANDBOX/kernel"
   (cd "$K_SRC" && git -c core.quotePath=false ls-files -co --exclude-standard) | while IFS= read -r F; do
      mkdir -p "$S/$(dirname "$F")"; cp -p "$K_SRC/$F" "$S/$F"
   done
   git -C "$S" init -q; git -C "$S" add -A
   git -C "$S" -c user.name=t -c user.email=t@t commit -q -m v0.6.0; git -C "$S" tag v0.6.0
   COMMIT="$(git -C "$S" rev-parse HEAD)"
   export AIBOS_INSTALLER_KERNEL_REPO="$S"
   git -C "$SANDBOX/hubs/aibex-aibos/distribution-demo" show v1.0.0:manifest.yaml > "$SANDBOX/demo.yaml"
   export AIBOS_INSTALLER_MANIFEST="$SANDBOX/demo.yaml"
   D="distribution-demo==1.0.0"; W="$HOME/work"; mkdir -p "$W"
   mkdir -p "$HOME/.aios/bin"; echo "AIOS 0.6" > "$HOME/.aios/marker"   # AIOS 0.6 on this machine
   page() { client get lang=de; }
   post3() { client post step=3 choice=next "$@" >/dev/null; local N=600
             while [ $N -gt 0 ]; do case "$(page)" in *"Der Plan wird erstellt"*) sleep 0.2;; *) return 0;; esac; N=$((N-1)); done; }
   wait_page() { local N=600; while [ $N -gt 0 ]; do R="$(page)"; case "$R" in *"$1"*) return 0;; esac; N=$((N-1)); sleep 0.2; done; return 1; }

#===============================================================================
# before the kernel: everything in ~/.aios, no ~/.aibos
#===============================================================================

   start_installer "$D" "$COMMIT" >/dev/null
   assert_file "$HOME/.aios/install/test-url"
   assert_nofile "$HOME/.aibos"
   client get lang=de >/dev/null; client post step=1 choice=next >/dev/null
   client post step=2 choice=agree agree=on >/dev/null
   assert_file "$HOME/.aios/consent/nutzungsvertrag-$(cat "$REPO/legal/VERSION").json"
   post3 mode=new name=Probe parent="$W"
   R="$(page)"
   assert_contains "$R" "AIBOS-Kernel 0.6.0 installieren" "4a: head"
   assert_contains "$R" "move $HOME/.aios to $HOME/.aibos and leave $HOME/.aios as a link to it (until AIBOS 0.8)" "4a: changeover of the kernel"
   assert_contains "$R" "(plan only, nothing written)" "4a: --plan"
   assert_nofile "$HOME/.aibos"
   [ -d "$HOME/.aios" ] && [ ! -L "$HOME/.aios" ] && ok || fail "4a: ~/.aios still a folder"

#===============================================================================
# kernel installed: ~/.aibos with everything, ~/.aios a link; then the distribution
#===============================================================================

   client post step=4a choice=install >/dev/null
   wait_page "<h2>Distribution installieren</h2>" && ok || fail "4b reached after the kernel: $(page | tail -5)"
   [ -d "$HOME/.aibos" ] && [ -L "$HOME/.aios" ] && ok || fail "changeover: ~/.aibos a folder, ~/.aios a link"
   assert_file "$HOME/.aibos/marker"
   assert_file "$HOME/.aibos/consent/nutzungsvertrag-$(cat "$REPO/legal/VERSION").json"
   assert_dir "$HOME/.aibos/versions/v0.6.0"
   assert_eq "$(git -C "$HOME/.aibos/installer/aibex-aibos" rev-parse HEAD)" "$COMMIT" "clone at the commit of the line"
   assert_file "$HOME/.aibos/bin/aibos"
   client post step=4b choice=install >/dev/null
   wait_page "Demo V1.0 (distribution-demo @ v1.0.0) ist in $W/§Probe installiert." && ok || fail "end page: done ($(result_field status): $(result_field message))"
   assert_eq "$(result_field status)" "done" "result: done"
   assert_file "$HOME/.aibos/install/result.json"
   assert_contains "$(cat "$W/§Probe/.aibos/config.yaml")" "aibos: 0.6.0" "vault bound to the kernel"
   wait_until 10 no_installer && ok || fail "install: ended"
