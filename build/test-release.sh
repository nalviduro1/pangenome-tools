#!/bin/bash
# test-release.sh OUTDIR [CORES]
# Does what the admin does, from the release assets in OUTDIR: unpack the tarball, run install.sh
# into a scratch prefix and modulefile folder, then run the full selftest through the installed
# wrappers, and load the modules if Environment Modules is present. Exit 0 only if everything passed.
set -euo pipefail
OUT=$(readlink -m "${1:?usage: test-release.sh OUTDIR [CORES]}"); CORES=${2:-4}
V=$(sed -n 's/^\([0-9a-f]\{64\}\)  pangenome-tools-\(.*\)\.tar\.gz$/\2/p' "$OUT/SHA256SUMS")
[ -n "$V" ] || { echo "no tarball in $OUT/SHA256SUMS" >&2; exit 1; }
T=$(mktemp -d "${TMPDIR:-/tmp}/pgt-test.XXXXXX")
mkdir -p "$T/modulefiles/cactus" "$T/work"
# a stand-in for an existing cactus module, to check that the installer keeps it as the default
printf '#%%Module1.0\nsetenv PGT_TEST_OLD_CACTUS 1\n' > "$T/modulefiles/cactus/2.9.0"
tar xzf "$OUT/pangenome-tools-$V.tar.gz" -C "$T"
bash "$T/pangenome-tools-$V/install.sh" --sif-dir "$OUT" --prefix "$T/prefix" --modulefiles "$T/modulefiles"
grep -q 'ModulesVersion "2.9.0"' "$T/modulefiles/cactus/.version" || { echo "FAIL: cactus default not kept" >&2; exit 1; }
"$T/prefix/$V/bin/analysis/pangenome-tools-selftest" full --cores "$CORES" --workdir "$T/work" | tee "$T/selftest.txt"
grep -q '0 failure(s), 0 skipped' "$T/selftest.txt"
for init in /usr/share/modules/init/bash /etc/profile.d/modules.sh; do
  if [ -r "$init" ]; then
    # shellcheck source=/dev/null
    . "$init"; export MODULEPATH="$T/modulefiles"
    module load cactus/4.0.0 1kcp-builder/"$V" pangenome-analysis/"$V"
    truvari version && kcp-init --help | head -1 && vg version | head -1
    module purge; module load cactus; [ "${PGT_TEST_OLD_CACTUS:-}" = 1 ] || { echo "FAIL: default cactus changed" >&2; exit 1; }
    echo "modules: OK ($init)"; break
  fi
done
echo "test-release: PASSED ($T)"
