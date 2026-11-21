#!/bin/bash
# install.sh -- install pangenome-tools (Cactus 4.0.0, the 1KCP graph builder, the pangenome analysis tools)
# as three environment modules backed by apptainer images.
#
#   bash install.sh --prefix DIR --modulefiles DIR [options]
#
#   --prefix DIR        where the images and wrappers go; the release is installed in DIR/<version>
#                       (e.g. /opt/tools/pangenome-tools)
#   --modulefiles DIR   a directory on MODULEPATH (e.g. /opt/modulefiles); writes
#                         cactus/4.0.0   1kcp-builder/<version>   pangenome-analysis/<version>
#   --sif-dir DIR       where the downloaded .sif files and SHA256SUMS are (default: the directory
#                       that holds this release's folder, i.e. where the tarball was unpacked)
#   --apptainer PATH    apptainer binary (default: the one on PATH); recorded in the wrappers. If it only
#                       runs with its module's LD_LIBRARY_PATH, the library folder it needs is recorded too,
#                       so users do not have to load the apptainer module.
#   --binds "A B ..."   host paths bound into the containers when they exist on the node
#                       (default: "/home /data /scratch"; list your cluster's shared file systems)
#   --group G           give the installed files group G. Needed when apptainer.conf has
#                       "limit container groups": images whose group is not listed there are refused for
#                       every user except root. The installer checks this and stops if it would happen.
#   --lsf-queue Q       queue for 'pangenome-tools-selftest --bsub' (default: normal)
#   --lsf-group G       LSF user group (bsub -G) for 'pangenome-tools-selftest --bsub', if your site needs one
#   --lsf-select R      LSF select[] expression that picks AVX2 nodes for the selftest job (default: "avx2"
#                       when 'lsinfo' lists a Boolean resource of that name, otherwise none; "none" = none)
#   --cactus-default    make cactus/4.0.0 the default 'cactus' module. Without it, the current
#                       default (an older cactus/<version>) is kept by writing cactus/.version, and users
#                       get 4.0.0 with 'module load cactus/4.0.0'.
#   --force             replace an existing install of this version
#
# The script changes nothing until every check has passed: it verifies the checksums, runs each
# image, builds the install in a temporary folder, runs the quick selftest from there in a clean
# environment (as a user would run it), and only then moves it and the modulefiles into place. It ends
# by printing the command for the full selftest.
set -euo pipefail
HERE=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
VERSION=$(cat "$HERE/VERSION")
CACTUS_VERSION=4.0.0
PREFIX= MODDIR= SIFDIR=$(dirname "$HERE") APPT= BINDS="/home /data /scratch"
GROUP= LSF_QUEUE=normal LSF_GROUP= LSF_SELECT=auto CACTUS_DEFAULT=false FORCE=false
die()  { echo "install.sh: ERROR: $*" >&2; exit 1; }
step() { echo "== $*"; }
usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX=$2; shift 2;;
    --modulefiles) MODDIR=$2; shift 2;;
    --sif-dir) SIFDIR=$2; shift 2;;
    --apptainer) APPT=$2; shift 2;;
    --binds) BINDS=$2; shift 2;;
    --group) GROUP=$2; shift 2;;
    --lsf-queue) LSF_QUEUE=$2; shift 2;;
    --lsf-group) LSF_GROUP=$2; shift 2;;
    --lsf-select) LSF_SELECT=$2; shift 2;;
    --cactus-default) CACTUS_DEFAULT=true; shift;;
    --force) FORCE=true; shift;;
    -h|--help) usage; exit 0;;
    *) die "unknown option: $1 (see --help)";;
  esac
done
[ -n "$PREFIX" ] || die "--prefix is required"
[ -n "$MODDIR" ] || die "--modulefiles is required"
PREFIX=$(readlink -m "$PREFIX"); MODDIR=$(readlink -m "$MODDIR"); SIFDIR=$(readlink -m "$SIFDIR")
DEST="$PREFIX/$VERSION"
SIFS="cactus-$CACTUS_VERSION.sif 1kcp-builder-$VERSION.sif pangenome-analysis-$VERSION.sif"
CLEAN=(env -i "HOME=$HOME" "USER=${USER:-$(id -un)}" "LOGNAME=${LOGNAME:-$(id -un)}" PATH=/usr/bin:/bin)

step "pangenome-tools $VERSION: checking"
# 1. apptainer must RUN (a path on PATH is not enough) -- and run without the admin's shell environment,
#    because the wrappers call it directly, without loading any module.
if [ -z "$APPT" ]; then APPT=$(command -v apptainer || command -v singularity || true); fi
[ -n "$APPT" ] || die "no apptainer on PATH; load it (module load apptainer) or pass --apptainer PATH"
APPT=$(readlink -f "$APPT")
APPT_LD=
if ! av=$("${CLEAN[@]}" "$APPT" --version 2>&1); then
  # find the one library folder it needs: next to the binary first, then each LD_LIBRARY_PATH entry
  cands="$(dirname "$(dirname "$APPT")")/lib $(echo "${LD_LIBRARY_PATH:-}" | tr ':' ' ')"
  for c in $cands; do
    [ -d "$c" ] || continue
    if av=$("${CLEAN[@]}" LD_LIBRARY_PATH="$c" "$APPT" --version 2>&1); then APPT_LD=$c; break; fi
  done
  [ -n "$APPT_LD" ] || die "$APPT does not run in a clean environment: $("${CLEAN[@]}" "$APPT" --version 2>&1 | tail -1)
       (users run it without your modules loaded). Pass --apptainer with a build that runs on its own."
  echo "   apptainer needs LD_LIBRARY_PATH=$APPT_LD; recorded for the wrappers (users need not load a module)"
fi
echo "   apptainer: $APPT ($av)"
appt() { if [ -n "$APPT_LD" ]; then LD_LIBRARY_PATH="$APPT_LD" "$APPT" "$@"; else "$APPT" "$@"; fi; }

# 2. checksums of the images
[ -r "$SIFDIR/SHA256SUMS" ] || die "no SHA256SUMS in $SIFDIR (use --sif-dir)"
for s in $SIFS; do [ -r "$SIFDIR/$s" ] || die "missing $SIFDIR/$s"; done
(cd "$SIFDIR" && grep -E " \*?($(echo $SIFS | sed 's/ /|/g; s/\./\\./g'))\$" SHA256SUMS | sha256sum -c --quiet -) \
  || die "checksum mismatch in $SIFDIR -- re-download the file(s) named above"
echo "   checksums: OK ($SIFS)"

# 3. targets
[ -d "$MODDIR" ] && [ -w "$MODDIR" ] || die "modulefile directory $MODDIR does not exist or is not writable"
# remember the highest folder this run creates, so that a failed check leaves nothing behind
NEWDIR=; d=$PREFIX; while [ ! -e "$d" ]; do NEWDIR=$d; d=$(dirname "$d"); done
TMP=
cleanup() {
  rm -rf "${TMP:-/nonexistent}" "$MODDIR"/.pgt-tmp.$$ 2>/dev/null || true
  if [ -n "$NEWDIR" ]; then
    d=$PREFIX; while rmdir "$d" 2>/dev/null && [ "$d" != "$NEWDIR" ]; do d=$(dirname "$d"); done
  fi
}
trap cleanup EXIT
mkdir -p "$PREFIX" || die "cannot create $PREFIX"
[ -w "$PREFIX" ] || die "$PREFIX is not writable"
if [ -e "$DEST" ]; then $FORCE || die "$DEST exists (use --force to replace it)"; fi
replaced=""
for m in "cactus/$CACTUS_VERSION" "1kcp-builder/$VERSION" "pangenome-analysis/$VERSION"; do
  [ -e "$MODDIR/$m" ] || continue
  if ! grep -q 'pangenome-tools' "$MODDIR/$m" 2>/dev/null; then
    $FORCE || die "$MODDIR/$m exists and was not written by this installer (use --force to replace it)"
  elif grep -qF "$DEST/" "$MODDIR/$m"; then
    $FORCE || die "$MODDIR/$m exists (use --force to replace it)"
  elif [ "$(sed -n 's/^## written by pangenome-tools install.sh \([^,]*\),.*/\1/p' "$MODDIR/$m")" = "$VERSION" ]; then
    # the same release installed under another --prefix: re-pointing it would silently move users off it
    $FORCE || die "$MODDIR/$m already points at release $VERSION in another folder
       ($(sed -n 's/^prepend-path PATH //p' "$MODDIR/$m")). Use that --prefix, another --modulefiles folder,
       or --force to point it at $DEST."
  else
    # written by another pangenome-tools release (an upgrade): it will point at this release
    replaced="$replaced $m"
  fi
done
[ -z "$replaced" ] || echo "   upgrade: will point$replaced at release $VERSION (written by an earlier release)"
if [ -n "$GROUP" ]; then
  getent group "$GROUP" >/dev/null || die "--group $GROUP: no such group"
  t=$(mktemp "$PREFIX/.pgt-grp.XXXXXX"); chgrp "$GROUP" "$t" 2>/dev/null || { rm -f "$t"; die "cannot give files group $GROUP (you must be root or a member)"; }; rm -f "$t"
fi

# 4. apptainer.conf limits that refuse images for normal users (root is exempt, so a test run as root
#    would pass and users would still be refused)
conf=
sc=$(appt buildcfg SYSCONFDIR 2>/dev/null || true)
for c in "${sc:+$sc/apptainer/apptainer.conf}" "$(dirname "$(dirname "$APPT")")/etc/apptainer/apptainer.conf"; do
  [ -n "$c" ] && [ -r "$c" ] && { conf=$c; break; }
done
limit() { [ -n "$conf" ] && sed -n "s/^[[:space:]]*limit container $1[[:space:]]*=[[:space:]]*//p" "$conf" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' || true; }
img_group=${GROUP:-$(stat -c %G "$PREFIX/." 2>/dev/null)}
# a folder without the setgid bit gives new files the installer's primary group, not the folder's
[ -n "$GROUP" ] || [ -g "$PREFIX" ] || img_group=$(id -gn)
lg=$(limit groups); lo=$(limit owners); lp=$(limit paths)
if [ -n "$lg" ] && ! echo "$lg" | grep -qx "$img_group"; then
  die "$conf has 'limit container groups = $(echo $lg | sed 's/ /, /g')';
       the images would have group '$img_group', so apptainer would refuse them for every user except root.
       Re-run with --group <one of those groups>."
fi
if [ -n "$lo" ] && ! echo "$lo" | grep -qx "$(id -un)"; then
  die "$conf has 'limit container owners = $(echo $lo | sed 's/ /, /g')'; the images would be owned by
       $(id -un). Run the installer as one of those users."
fi
if [ -n "$lp" ]; then
  ok=false; for p in $lp; do case "$DEST/" in "${p%/}"/*) ok=true;; esac; done
  $ok || die "$conf has 'limit container paths = $(echo $lp | sed 's/ /, /g')'; $DEST is not under any of them."
fi
[ -n "$conf" ] && echo "   apptainer.conf: $conf (images will have group $img_group)"

# 5. the default 'cactus' module: only this folder can keep an older cactus as the default
others_here=
if [ -d "$MODDIR/cactus" ]; then
  others_here=$(cd "$MODDIR/cactus" && ls -1 | sed 's/\.lua$//' | grep -vx "$CACTUS_VERSION" | grep -E '^[0-9]' | sort -V | tail -1 || true)
fi
if ! $CACTUS_DEFAULT && [ -z "$others_here" ]; then
  for d in $(echo "${MODULEPATH:-}" | tr ':' ' '); do
    [ "$(readlink -m "$d")" = "$MODDIR" ] && continue
    [ -d "$d/cactus" ] && [ -n "$(ls -A "$d/cactus" 2>/dev/null)" ] || continue
    die "there is already a 'cactus' module in $d. Installing cactus/$CACTUS_VERSION into $MODDIR would
       make it the default 'cactus' for everyone. Either use --modulefiles $d (the installer then keeps
       the current default), or add --cactus-default if 4.0.0 should become the default."
  done
fi

# 6. the LSF resource that selects AVX2 nodes for 'pangenome-tools-selftest --bsub'.
#    lsinfo exits 0 even for an unknown name, so read its table instead of its exit status.
if [ "$LSF_SELECT" = auto ]; then
  LSF_SELECT=
  if command -v lsinfo >/dev/null 2>&1 && lsinfo avx2 2>/dev/null | awk '$1=="avx2" && $2=="Boolean"{f=1} END{exit !f}'; then
    LSF_SELECT=avx2
  fi
fi
[ "$LSF_SELECT" = none ] && LSF_SELECT=
if command -v bsub >/dev/null 2>&1; then
  if [ -n "$LSF_SELECT" ]; then sel="select[$LSF_SELECT]"; else sel="no AVX2 selector (no Boolean 'avx2' resource in lsinfo; see --lsf-select)"; fi
  echo "   LSF selftest job: queue $LSF_QUEUE${LSF_GROUP:+, group $LSF_GROUP}, $sel"
fi

# 7. build the install in a temporary folder next to its final place
TMP="$PREFIX/.install-$VERSION.$$"
mkdir -p "$TMP"/{sif,bin/cactus,bin/kcp,bin/analysis,libexec,etc,share}
step "copying images to $DEST/sif (about 1.6 GB)"
for s in $SIFS; do cp "$SIFDIR/$s" "$TMP/sif/$s"; done
(cd "$TMP/sif" && grep -E " \*?($(echo $SIFS | sed 's/ /|/g; s/\./\\./g'))\$" "$SIFDIR/SHA256SUMS" | sha256sum -c --quiet -) \
  || die "copied images do not match their checksums (disk full?)"
cp "$HERE/libexec/pgt-exec" "$HERE/libexec/pgt-selftest" "$TMP/libexec/"
cp -r "$HERE/tests" "$TMP/share/tests"; cp -r "$HERE/tools" "$TMP/share/tools"
cp "$HERE/README.md" "$HERE/VERSION" "$TMP/"; [ -r "$HERE/LICENSE" ] && cp "$HERE/LICENSE" "$TMP/"
cat > "$TMP/etc/pgt.conf" <<EOF
# written by install.sh $(date '+%F %T') -- edit PGT_APPTAINER or PGT_BINDS_DEFAULT here if they change
PGT_VERSION="$VERSION"
PGT_CACTUS_VERSION="$CACTUS_VERSION"
PGT_APPTAINER="$APPT"
PGT_APPTAINER_LD_LIBRARY_PATH="$APPT_LD"
PGT_BINDS_DEFAULT="$BINDS"
PGT_LSF_QUEUE="\${PGT_LSF_QUEUE:-$LSF_QUEUE}"
PGT_LSF_GROUP="\${PGT_LSF_GROUP:-$LSF_GROUP}"
PGT_LSF_SELECT="\${PGT_LSF_SELECT:-$LSF_SELECT}"
PGT_CACTUS_SIF="$DEST/sif/cactus-$CACTUS_VERSION.sif"
PGT_KCP_SIF="$DEST/sif/1kcp-builder-$VERSION.sif"
PGT_ANALYSIS_SIF="$DEST/sif/pangenome-analysis-$VERSION.sif"
EOF
# while testing from TMP, point the config at the TMP images; rewritten below before the move
sed "s#$DEST/sif#$TMP/sif#" "$TMP/etc/pgt.conf" > "$TMP/etc/pgt.conf.test"
cp "$TMP/etc/pgt.conf" "$TMP/etc/pgt.conf.final"; cp "$TMP/etc/pgt.conf.test" "$TMP/etc/pgt.conf"

step "writing wrappers"
nwrap=0
for img in cactus kcp analysis; do
  while IFS=$'\t' read -r w c chk exp; do
    case "$w" in \#*|'') continue;; esac
    f="$TMP/bin/$img/$w"
    if [ "$c" = '*' ]; then
      printf '#!/bin/bash\n# pangenome-tools %s: run any command inside the %s image\nexec "%s/libexec/pgt-exec" %s "$@"\n' "$VERSION" "$img" "$DEST" "$img" > "$f"
    else
      printf '#!/bin/bash\n# pangenome-tools %s: %s inside the %s image\nexec "%s/libexec/pgt-exec" %s %s "$@"\n' "$VERSION" "$c" "$img" "$DEST" "$img" "$c" > "$f"
    fi
    nwrap=$((nwrap+1))
  done < "$HERE/tools/$img.tsv"
  ln -s "$DEST/libexec/pgt-selftest" "$TMP/bin/$img/pangenome-tools-selftest"
done
find "$TMP/bin" "$TMP/libexec" -type f -exec chmod 755 {} +
if [ -n "$GROUP" ]; then chgrp -R "$GROUP" "$TMP"; fi
chmod -R a+rX "$TMP"
echo "   $nwrap wrappers"

step "running each image"
for s in $SIFS; do
  o=$(appt exec ${PGT_EXEC_OPTS:-} --cleanenv "$TMP/sif/$s" true 2>&1) || die "apptainer cannot run $s: $o"
done
echo "   all 3 images start"

step "quick selftest (from the temporary folder, in a clean environment)"
# the wrappers point at $DEST, which does not exist yet: test through libexec directly
qs="$TMP/qs"; mkdir -p "$qs"
if ! "${CLEAN[@]}" "$TMP/libexec/pgt-selftest" quick --workdir "$qs" | tee "$TMP/selftest-quick.txt" | grep -E '^(OK|FAIL|SKIP)|failure'; then
  die "quick selftest failed -- nothing was installed (details above)"
fi
rm -rf "$qs"
if [ -n "$GROUP" ]; then chgrp "$GROUP" "$TMP/selftest-quick.txt"; fi
chmod a+r "$TMP/selftest-quick.txt"
mv "$TMP/etc/pgt.conf.final" "$TMP/etc/pgt.conf"; rm -f "$TMP/etc/pgt.conf.test"

step "writing modulefiles"
MT="$MODDIR/.pgt-tmp.$$"; mkdir -p "$MT"
modfile() { # name version bindir whatis help
  cat <<EOF
#%Module1.0
## written by pangenome-tools install.sh $VERSION, $(date '+%F')
proc ModulesHelp { } {
  puts stderr "$5"
  puts stderr ""
  puts stderr "Commands: ls $3"
  puts stderr "Selftest: pangenome-tools-selftest quick   (or: full --bsub; see --help)"
  puts stderr "Docs:     $DEST/README.md"
}
module-whatis "$4"
conflict $1
prepend-path PATH $3
EOF
}
modfile cactus "$CACTUS_VERSION" "$DEST/bin/cactus" \
  "Minigraph-Cactus $CACTUS_VERSION (upstream image) with vg 1.78, minigraph, odgi, GFAffix, HAL tools, samtools, bcftools, minimap2" \
  "Cactus $CACTUS_VERSION, unmodified upstream container. Needs a node with AVX2 (not the login node)." > "$MT/cactus"
modfile 1kcp-builder "$VERSION" "$DEST/bin/kcp" \
  "1KCP graph builder (JianYang-Lab/1KCP-analysis 02_Pangenome) with its pinned tools: kcp-init, kcp-snakemake, ..." \
  "1KCP pangenome graph builder. Start with: kcp-init --help" > "$MT/1kcp"
modfile pangenome-analysis "$VERSION" "$DEST/bin/analysis" \
  "Pangenome analysis tools: truvari, kmc, liftoff, miniprot, pangene, rustybam, seqtk, whatshap, rfmix, leiden" \
  "Pangenome analysis tools. Python with igraph/leidenalg: pga-python" > "$MT/analysis"
chmod a+r "$MT"/*

# keep the current default 'cactus' unless asked otherwise (Modules picks the highest version otherwise)
note=""
if ! $CACTUS_DEFAULT; then
  if [ -n "$others_here" ] && [ ! -e "$MODDIR/cactus/.version" ] && [ ! -e "$MODDIR/cactus/.modulerc" ] && [ ! -e "$MODDIR/cactus/.modulerc.lua" ] && [ ! -e "$MODDIR/cactus/default" ]; then
    printf '#%%Module1.0\n## written by pangenome-tools install.sh: keeps the default when cactus/%s was added\nset ModulesVersion "%s"\n' "$CACTUS_VERSION" "$others_here" > "$MT/cactus.version"
    chmod a+r "$MT/cactus.version"
    note="cactus default kept at $others_here (wrote $MODDIR/cactus/.version)"
  elif [ -n "$others_here" ]; then
    note="cactus default unchanged (a default is already marked in $MODDIR/cactus)"
  fi
else
  [ -e "$MODDIR/cactus/.version" ] && cp -p "$MODDIR/cactus/.version" "$MODDIR/cactus/.version.before-pgt-$VERSION"
  printf '#%%Module1.0\nset ModulesVersion "%s"\n' "$CACTUS_VERSION" > "$MT/cactus.version"
  chmod a+r "$MT/cactus.version"
  note="cactus default is now $CACTUS_VERSION"
fi

step "moving into place"
if [ -e "$DEST" ]; then rm -rf "$DEST.old.$$"; mv "$DEST" "$DEST.old.$$"; fi
mv "$TMP" "$DEST"
rm -rf "$DEST.old.$$" 2>/dev/null || true
for m in cactus 1kcp-builder pangenome-analysis; do
  if [ ! -d "$MODDIR/$m" ]; then
    mkdir "$MODDIR/$m"; chmod a+rx "$MODDIR/$m"
    if [ -n "$GROUP" ]; then chgrp "$GROUP" "$MODDIR/$m"; fi
  fi
done
mv "$MT/cactus" "$MODDIR/cactus/$CACTUS_VERSION"
mv "$MT/1kcp" "$MODDIR/1kcp-builder/$VERSION"
mv "$MT/analysis" "$MODDIR/pangenome-analysis/$VERSION"
[ -e "$MT/cactus.version" ] && mv "$MT/cactus.version" "$MODDIR/cactus/.version"
rmdir "$MT"
trap - EXIT

# check with the module system itself what a bare 'module load cactus' gives now
check=""
if type module >/dev/null 2>&1; then
  mp=$MODDIR; case ":${MODULEPATH:-}:" in *":$MODDIR:"*) mp=$MODULEPATH;; *) mp="$MODDIR${MODULEPATH:+:$MODULEPATH}";; esac
  got=$(MODULEPATH=$mp bash -c 'module purge >/dev/null 2>&1; module load cactus >/dev/null 2>&1; module -t list 2>&1' 2>/dev/null | grep -o 'cactus/[^ ]*' | head -1 || true)
  want=$($CACTUS_DEFAULT && echo "cactus/$CACTUS_VERSION" || { [ -n "$others_here" ] && echo "cactus/$others_here"; } || true)
  if [ -n "$want" ] && [ -n "$got" ] && [ "$got" != "$want" ]; then
    check="WARNING: 'module load cactus' now loads $got, not $want. Mark the default you want in $MODDIR/cactus."
  elif [ -n "$got" ]; then
    check="module load cactus -> $got"
  fi
fi

sel="pangenome-tools-selftest full --bsub --workdir <a scratch folder>"
cat <<EOF

Installed pangenome-tools $VERSION in $DEST
Modules:  cactus/$CACTUS_VERSION   1kcp-builder/$VERSION   pangenome-analysis/$VERSION
${replaced:+         now pointing at $VERSION:$replaced
}${note:+         $note
}${check:+         $check
}
Last step -- the full selftest on a compute node (about 10 minutes, 4 cores; LSF queue $LSF_QUEUE${LSF_GROUP:+, group $LSF_GROUP}):

  module load pangenome-analysis/$VERSION
  $sel

then:  grep -E '^(OK|FAIL|SKIP)|failure' <that folder>/selftest.out
It must end with "0 failure(s), 0 skipped". Run it as an ordinary user, not root: apptainer applies
some of its limits only to ordinary users.
EOF
