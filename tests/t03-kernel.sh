# t03-kernel.sh: pages 4a, 4b and 5 with a real kernel (spec 05) — commit check (IN9), abort after 4a (F113),
# further run without 4a, failure of the kernel; kernel from a local clone, hub and wheels as in the kernel tests (F138)

   case "$SANDBOX" in */aios-installer-test.*) ;; *) echo "*** run via tests/run, never directly" >&2; exit 1;; esac

   for K_SRC in "$AIOS_INSTALLER_KERNEL_SRC" "$(dirname "$REPO")/aibex-aios"; do [ -x "$K_SRC/bin/aios" ] && break; done
   if [ ! -x "$K_SRC/bin/aios" ] || [ ! -x "$K_SRC/tests/hub/build" ]; then
      echo "   skipped: no clone of aibex-aios next to this repo (set AIOS_INSTALLER_KERNEL_SRC)"; ok; return 0 2>/dev/null || exit 0
   fi

#===============================================================================
# setup: python3 with PyYAML, no pip, no sudo; sandbox clone of the kernel with tag v0.6.0; test hubs
#===============================================================================

   PYDIR=""
   for P in $(type -ap python3) /opt/homebrew/bin/python3 /usr/local/bin/python3; do
      [ -x "$P" ] && "$P" -c "import yaml, venv, ensurepip, sys; sys.exit(sys.version_info < (3, 11))" 2>/dev/null && { PYDIR="$(dirname "$P")"; break; }
   done
   [ -n "$PYDIR" ] && ok || { fail "t03 needs a python3 >= 3.11 with PyYAML"; return 0 2>/dev/null || exit 0; }
   mkdir -p "$SANDBOX/fake" "$SANDBOX/stup-src"
   printf '#!/bin/sh\nexit 1\n' > "$SANDBOX/fake/no-sudo"; chmod +x "$SANDBOX/fake/no-sudo"
   export PATH="$PYDIR:$SANDBOX/fake:/usr/bin:/bin:/usr/sbin:/sbin"
   # "pip" of the kernel venv: a .pth to the PyYAML of the test python (no network)
   YAML_DIR="$("$PYDIR/python3" -c 'import os, yaml; print(os.path.dirname(os.path.dirname(yaml.__file__)))')"
   printf '#!/bin/sh\nfor S in "$(dirname "$1")"/lib/python3*/site-packages; do echo "%s" > "$S/test-yaml.pth"; done\n' "$YAML_DIR" > "$SANDBOX/fake/pip"
   chmod +x "$SANDBOX/fake/pip"
   export AIOS_SUDO="$SANDBOX/fake/no-sudo" AIOS_PIP="$SANDBOX/fake/pip" AIOS_STUP_URL="file://$SANDBOX/stup-src/stup"
   "$K_SRC/tests/hub/build" "$SANDBOX/hubs" >/dev/null
   export AIOS_PIP_FIND_LINKS="$SANDBOX/hubs/wheels"
   S="$SANDBOX/kernel"
   (cd "$K_SRC" && git -c core.quotePath=false ls-files -co --exclude-standard) | while IFS= read -r F; do
      mkdir -p "$S/$(dirname "$F")"; cp -p "$K_SRC/$F" "$S/$F"
   done
   git -C "$S" init -q; git -C "$S" add -A
   git -C "$S" -c user.name=t -c user.email=t@t commit -q -m v0.6.0; git -C "$S" tag v0.6.0
   COMMIT="$(git -C "$S" rev-parse HEAD)"
   export AIOS_INSTALLER_KERNEL_REPO="$S"
   git -C "$SANDBOX/hubs/aibex-aios/distribution-demo" show v1.0.0:manifest.yaml > "$SANDBOX/demo.yaml"
   export AIOS_INSTALLER_MANIFEST="$SANDBOX/demo.yaml"
   D="distribution-demo==1.0.0"; W="$HOME/work"; mkdir -p "$W"
   page() { client get lang=de; }
   status_is() { [ "$(result_field status)" == "$1" ]; }
   wait_page() { local N=600; while [ $N -gt 0 ]; do R="$(page)"; case "$R" in *"$1"*) return 0;; esac; N=$((N-1)); sleep 0.2; done; return 1; }
   to_page3() { client get lang=de >/dev/null; client post step=1 choice=next >/dev/null
                case "$(page)" in *"Nutzungsvertrag"*) client post step=2 choice=agree agree=on >/dev/null;; esac; }

#===============================================================================
# wrong commit: failed before any call of bin/aios (IN9)
#===============================================================================

   start_installer "$D" "$COMMIT0" >/dev/null
   to_page3
   client post step=3 choice=next mode=new name=Probe parent="$W" >/dev/null
   assert_eq "$(result_field status)" "failed" "wrong commit: failed"
   assert_contains "$(result_field message)" "not to 000000000000" "wrong commit: message"
   assert_nofile "$HOME/.aios/versions"
   assert_nofile "$HOME/.aios/bin/aios"
   assert_nofile "$HOME/.aios/installer"
   wait_until 10 no_installer && ok || fail "wrong commit: ended"

#===============================================================================
# page 4a: plan of the kernel verbatim, install; page 4b: plan of the distribution; abort (F113)
#===============================================================================

   start_installer "$D" "$COMMIT" >/dev/null
   to_page3
   client post step=3 choice=next mode=new name=Probe parent="$W" >/dev/null
   R="$(page)"
   assert_contains "$R" "AIOS-Kernel 0.6.0 installieren" "4a: head"
   assert_contains "$R" "AIbex AIOS v0.6.0" "4a: plan of the kernel verbatim"
   assert_contains "$R" "(plan only, nothing written)" "4a: --plan"
   assert_nofile "$HOME/.aios/versions/v0.6.0"
   client post step=4a choice=install >/dev/null
   wait_page "Distribution installieren" && ok || fail "4b reached after the kernel: $(page | tail -5)"
   assert_dir "$HOME/.aios/versions/v0.6.0"
   assert_dir "$HOME/.aios/installer/aibex-aios"
   assert_eq "$(git -C "$HOME/.aios/installer/aibex-aios" rev-parse HEAD)" "$COMMIT" "clone at the commit of the line"
   [ ! -e "$HOME/.aios/repo" ] || [ "$(cat "$HOME/.aios/repo" 2>/dev/null || readlink "$HOME/.aios/repo")" == "$HOME/.aios/installer/aibex-aios" ] \
      && ok || fail "~/.aios/repo, if the kernel sets it, points to the clone"
   R="$(page)"
   assert_contains "$R" "Ordner anlegen: $W/§Probe" "4b: create folder line"
   assert_contains "$R" "install distribution-demo 1.0.0 into $W/§Probe" "4b: plan of the distribution verbatim"
   assert_nofile "$W/§Probe"
   client post step=4b choice=abort >/dev/null
   assert_eq "$(result_field status)" "aborted" "abort on 4b: aborted"
   assert_eq "$(result_field step)" "4b" "abort on 4b: step"
   assert_eq "$(result_field kernel_installed)" "true" "abort after 4a: kernel stays (F113)"
   assert_eq "$(result_field vault_created)" "false" "abort after 4a: no vault"
   assert_nofile "$W/§Probe"
   wait_until 10 no_installer && ok || fail "abort on 4b: ended"

#===============================================================================
# further run: no page 2, no page 4a; install into a new vault
#===============================================================================

   start_installer "$D" "$COMMIT" >/dev/null
   to_page3
   client post step=3 choice=next mode=new name=Probe parent="$W" >/dev/null
   R="$(page)"; assert_contains "$R" "Distribution installieren" "further run: 4a skipped"
   client post step=4b choice=install >/dev/null
   wait_page "Demo V1.0 (distribution-demo @ v1.0.0) ist in $W/§Probe installiert." && ok || fail "end page: done ($(result_field status): $(result_field message))"
   assert_eq "$(result_field status)" "done" "result: done"
   assert_eq "$(result_field vault)" "$W/§Probe" "result: vault"
   assert_eq "$(result_field vault_created)" "true" "result: vault created"
   assert_eq "$(result_field kernel)" "0.6.0" "result: kernel"
   assert_file "$(result_field log)"
   assert_contains "$(cat "$W/§Probe/.aios/config.yaml")" "aios: 0.6.0" "vault bound to the kernel"
   assert_contains "$(cat "$W/§Probe/.aios/config.yaml")" "distribution-demo" "distribution in packages:"
   wait_until 10 no_installer && ok || fail "install: ended"

#===============================================================================
# known vaults on page 3; failure of the kernel (AIOS_TEST_FAIL): failed, created folder stays
#===============================================================================

   AIOS_TEST_FAIL=2 start_installer "$D" "$COMMIT" >/dev/null
   to_page3
   R="$(page)"; assert_contains "$R" "$W/§Probe — aios 0.6.0" "page 3: known vault from aios --vaults"
   client post step=3 choice=next mode=new name=Zwei parent="$W" >/dev/null
   client post step=4b choice=install >/dev/null
   wait_until 120 status_is failed && ok || fail "kernel failure: failed ($(result_field status))"
   assert_contains "$(result_field message)" "the distribution was not installed" "kernel failure: message"
   assert_eq "$(result_field vault_created)" "true" "kernel failure: created folder named"
   assert_dir "$W/§Zwei"
   wait_until 10 no_installer && ok || fail "kernel failure: ended"
