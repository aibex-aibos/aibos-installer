#!/bin/bash
# release.sh: build the release asset of the AIBOS installer, set its checksum in install.sh, print the install line

   if [ "$*" == "-?" ] || [ "$*" == "--help" ] || [ "$*" == "" ]; then
      echo '   usage: tools/release.sh <version> [distribution-<name>==<dv> <commit>]'
      echo '          tools/release.sh --version  # print version'
      echo '   builds dist/aios-installer-<version>.tar.gz (reproducible), sets ASSET_SHA256 and VERSION'
      echo '   in install.sh and VERSION in installer/aios_installer.py, commits, prints the checksums'
      echo '   and, with a distribution and the commit of its kernel, the install line (spec 02, 06)'
      exit 1
   fi

#===============================================================================
# print version: release.sh --version
#===============================================================================

   if [ "$*" == "--version" ]; then
      echo "0.1.0"; exit 0
   fi

#===============================================================================
# release: release.sh <version> [<distribution==version> <commit>]
#===============================================================================

   if [ "$#" == "1" ] || [ "$#" == "3" ]; then
      V="$1"; DIST="$2"; COMMIT="$3"
      R="$(cd "$(dirname "$0")/.." && pwd)"
      [[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$ ]] || { echo "*** release: not a version: $V"; exit 1; }
      [ -z "$DIST" ] || [[ "$DIST" =~ ^distribution-[a-z0-9][a-z0-9-]*==[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$ ]] \
         || { echo "*** release: not a distribution with version: $DIST"; exit 1; }
      [ -z "$COMMIT" ] || [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "*** release: not a full commit: $COMMIT"; exit 1; }
      [ -z "$(git -C "$R" status --porcelain)" ] || { echo "*** release: the working tree is not clean"; exit 1; }
      PY="$(command -v python3)"
      ASSET="$R/dist/aios-installer-$V.tar.gz"
      # first the version (it is part of the asset), then the asset, then its checksum in install.sh
      sed -i '' -e "s/^VERSION = \".*\"/VERSION = \"$V\"/" "$R/installer/aios_installer.py"
      sed -i '' -e "s/^VERSION=\".*\"/VERSION=\"$V\"/" "$R/install.sh"
      mkdir -p "$R/dist"
      "$PY" -I - "$R" "$ASSET" <<'PYEOF' || exit 1
import gzip, io, os, sys, tarfile
root, out = sys.argv[1], sys.argv[2]
files = []
for top in ("installer", "i18n", "legal"):
    for d, dirs, names in os.walk(os.path.join(root, top)):
        dirs[:] = sorted(x for x in dirs if x != "__pycache__")
        files += [os.path.join(d, n) for n in names if not n.endswith(".pyc") and n != ".DS_Store"]
buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as tar:
    for path in sorted(files):
        rel = os.path.relpath(path, root)
        info = tarfile.TarInfo(rel)
        data = open(path, "rb").read()
        info.size, info.mtime, info.uid, info.gid, info.uname, info.gname = len(data), 0, 0, 0, "", ""
        info.mode = 0o755 if os.access(path, os.X_OK) else 0o644
        tar.addfile(info, io.BytesIO(data))
with open(out, "wb") as f:
    with gzip.GzipFile(filename="", mode="wb", fileobj=f, mtime=0) as gz:
        gz.write(buf.getvalue())
PYEOF
      SUM="$(shasum -a 256 "$ASSET" | cut -d' ' -f1)"
      sed -i '' -e "s/^ASSET_SHA256=\".*\"/ASSET_SHA256=\"$SUM\"/" "$R/install.sh"
      grep -q "^VERSION=\"$V\"$" "$R/install.sh" && grep -q "^VERSION = \"$V\"$" "$R/installer/aios_installer.py" \
         || { echo "*** release: VERSION not set"; exit 1; }
      if [ -n "$(git -C "$R" status --porcelain -- install.sh installer)" ]; then
         git -C "$R" add install.sh installer/aios_installer.py
         git -C "$R" commit -q -m "Release $V: Version und Prüfsumme des Assets in install.sh" || exit 1
      fi
      echo "asset:      $ASSET"
      echo "asset sha256:      $SUM"
      echo "install.sh sha256: $(shasum -a 256 "$R/install.sh" | cut -d' ' -f1)"
      if [ -n "$DIST" ]; then
         echo "install line:"
         echo "f=\$(mktemp) && curl -fsSL https://raw.githubusercontent.com/aibex-aios/aios-installer/v$V/install.sh -o \"\$f\" && echo \"$(shasum -a 256 "$R/install.sh" | cut -d' ' -f1)  \$f\" | shasum -a 256 -c - && sh \"\$f\" \"$DIST\" $COMMIT"
      fi
      exit 0
   fi

#===============================================================================
# cannot deal with anything else ...
#===============================================================================

   "$0" -?
   exit 1
