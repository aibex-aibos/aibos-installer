# t08-release.sh: tools/release.sh (spec 06, Release) — reproducible asset, checksum and version, install line

   case "$SANDBOX" in */aibos-installer-test.*) ;; *) echo "*** run via tests/run, never directly" >&2; exit 1;; esac

#===============================================================================
# setup: a copy of the repo as its own git repo
#===============================================================================

   C="$SANDBOX/copy"
   (cd "$REPO" && git -c core.quotePath=false ls-files -co --exclude-standard) | while IFS= read -r F; do
      mkdir -p "$C/$(dirname "$F")"; cp -p "$REPO/$F" "$C/$F"
   done
   git -C "$C" init -q; git -C "$C" add -A; git -C "$C" -c user.name=t -c user.email=t@t commit -q -m copy
   export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
   K="0cb16b4b8dd0e49fab07fd6f4aedc2eac89a8c53"

#===============================================================================
# release: asset, checksum, versions, commit, install line
#===============================================================================

   OUT="$("$C/tools/release.sh" 0.9.9-rc9 "distribution-capricorn==0.4.1-rc1" "$K" 2>&1)"; RC=$?
   assert_eq "$RC" "0" "release: exit 0"
   A="$C/dist/aibos-installer-0.9.9-rc9.tar.gz"
   assert_file "$A"
   SUM="$(shasum -a 256 "$A" | cut -d' ' -f1)"
   assert_contains "$(cat "$C/install.sh")" "ASSET_SHA256=\"$SUM\"" "install.sh: checksum of the asset"
   assert_contains "$(cat "$C/install.sh")" 'VERSION="0.9.9-rc9"' "install.sh: version"
   assert_contains "$(tar -xzOf "$A" installer/aibos_installer.py)" 'VERSION = "0.9.9-rc9"' "asset: installer with the version"
   assert_eq "$(git -C "$C" status --porcelain)" "" "release: committed"
   assert_contains "$(git -C "$C" log -1 --format=%s)" "Release 0.9.9-rc9" "release: commit message"
   ISUM="$(shasum -a 256 "$C/install.sh" | cut -d' ' -f1)"
   assert_contains "$OUT" "v0.9.9-rc9/install.sh" "install line: tag"
   assert_contains "$OUT" "echo \"$ISUM  \$f\"" "install line: checksum of install.sh"
   assert_contains "$OUT" "sh \"\$f\" \"distribution-capricorn==0.4.1-rc1\" $K" "install line: distribution and commit"
   assert_not_contains "$(tar -tzf "$A")" "install.sh" "asset: without install.sh"
   assert_not_contains "$(tar -tzf "$A")" "tests/" "asset: without tests"

#===============================================================================
# reproducible: the same sources give the same asset; a dirty tree is refused
#===============================================================================

   cp "$A" "$SANDBOX/first.tar.gz"; sleep 1
   "$C/tools/release.sh" 0.9.9-rc9 >/dev/null 2>&1
   assert_eq "$(shasum -a 256 "$A" | cut -d' ' -f1)" "$SUM" "reproducible asset"
   echo x >> "$C/README.md"
   OUT="$("$C/tools/release.sh" 0.1.0-rc2 2>&1)"; assert_eq "$?" "1" "dirty tree: exit 1"
   assert_contains "$OUT" "not clean" "dirty tree: message"
   OUT="$("$C/tools/release.sh" 1.0 2>&1)"; assert_eq "$?" "1" "bad version: exit 1"

#===============================================================================
# the released formula accepts its asset (end to end without network)
#===============================================================================

   git -C "$C" checkout -q README.md
   AIBOS_INSTALLER_ASSET="$A" AIBOS_INSTALLER_PYTHONS="$PY" sh "$C/install.sh" "distribution-demo==1.0.0" "$COMMIT0" >/dev/null 2>&1
   assert_eq "$?" "0" "released formula starts with its asset"
   client post step=1 choice=abort >/dev/null
   wait_until 10 no_installer && ok || fail "released installer ended"
