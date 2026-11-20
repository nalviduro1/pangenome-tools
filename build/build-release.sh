#!/bin/bash
# build-release.sh OUTDIR
# Builds every release asset into OUTDIR:
#   cactus-4.0.0.sif               upstream Cactus image, pulled by digest (unmodified)
#   1kcp-builder-<version>.sif     images/kcp
#   pangenome-analysis-<version>.sif       images/analysis
#   pangenome-tools-<version>.tar.gz   install.sh, wrappers, tests, docs, image sources
#   SHA256SUMS
# Needs docker (with buildx) and apptainer. Used by .github/workflows/release.yml and by hand.
# Optional: CA_BUNDLE=/path/ca.pem for builds behind a TLS-inspecting proxy.
set -euo pipefail
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
OUT=$(readlink -m "${1:?usage: build-release.sh OUTDIR}")
V=$(cat "$ROOT/VERSION")
. "$ROOT/images/cactus/IMAGE"
mkdir -p "$OUT"
secret=()
[ -n "${CA_BUNDLE:-}" ] && secret=(--secret "id=ca,src=$CA_BUNDLE")
for img in kcp analysis; do
  echo "== docker build images/$img"
  DOCKER_BUILDKIT=1 docker build ${secret[@]+"${secret[@]}"} -t "pgtools/$img:$V" "$ROOT/images/$img"
done
echo "== sif: 1kcp-builder, pangenome-analysis"
rm -f "$OUT/1kcp-builder-$V.sif" "$OUT/pangenome-analysis-$V.sif" "$OUT/cactus-4.0.0.sif"
apptainer build "$OUT/1kcp-builder-$V.sif" "docker-daemon://pgtools/kcp:$V"
apptainer build "$OUT/pangenome-analysis-$V.sif" "docker-daemon://pgtools/analysis:$V"
echo "== sif: cactus from $image@$digest"
apptainer pull --disable-cache "$OUT/cactus-4.0.0.sif" "docker://${image%%:*}@$digest"
echo "== scripts tarball"
stage=$(mktemp -d); d="$stage/pangenome-tools-$V"; mkdir -p "$d"
cp -r "$ROOT"/{VERSION,LICENSE,README.md,ADMIN.md,install.sh,images,libexec,tests,tools,build} "$d/"
tar czf "$OUT/pangenome-tools-$V.tar.gz" -C "$stage" "pangenome-tools-$V"; rm -rf "$stage"
(cd "$OUT" && sha256sum "cactus-4.0.0.sif" "1kcp-builder-$V.sif" "pangenome-analysis-$V.sif" "pangenome-tools-$V.tar.gz" > SHA256SUMS)
for f in "$OUT"/*.sif; do
  s=$(stat -c %s "$f"); [ "$s" -lt 2000000000 ] || { echo "ERROR: $f is $s bytes, over the 2 GB release-asset limit" >&2; exit 1; }
done
ls -la "$OUT"; cat "$OUT/SHA256SUMS"
