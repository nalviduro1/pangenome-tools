#!/bin/bash
# Functional test for the Cactus 4.0.0 image: a 4-genome Minigraph-Cactus pangenome of the
# cactusTestData evolver primates (one ~180 kb chr6 locus each), as in the Cactus pangenome docs.
# Runs INSIDE the container:  apptainer exec <sif> bash cactus.sh <workdir> <datadir> [cores]
# Checks the CONTENT: every input genome is a path in the GBZ and spells its input FASTA exactly,
# and the VCF holds variant records. Exit status = number of failures.
set -u
W=${1:?workdir}; D=${2:?datadir}; C=${3:-2}
mkdir -p "$W" && cd "$W" || exit 99
fails=0
ok()  { printf 'OK    %-14s %s\n' "$1" "$2"; }
bad() { printf 'FAIL  %-14s %s\n' "$1" "$2"; fails=$((fails+1)); }
grep -qw avx2 /proc/cpuinfo || { bad cpu "this node has no AVX2; Cactus 4.0.0 binaries need it (run on a compute node)"; exit 1; }
for g in Orang Chimp Human Gorilla; do printf 'sim%s\t%s/sim%s.chr6.fa.gz\n' $g "$D" $g; done > primates.txt
rm -rf js out work; mkdir -p work
if cactus-pangenome ./js primates.txt --outDir out --outName primates --reference simChimp \
      --vcf --gbz --gfa --maxCores "$C" --workDir "$W/work" > cactus.log 2>&1; then
  ok cactus-pangenome "4-genome pangenome built (log: $W/cactus.log)"
else
  bad cactus-pangenome "failed -- see $W/cactus.log: $(grep -m1 -iE 'error|exception' cactus.log | cut -c1-120)"
  echo "cactus: $fails failure(s)"; exit $fails
fi
[ -s out/primates.gbz ] && ok gbz "out/primates.gbz written" || bad gbz "no GBZ"
for g in Orang Chimp Human Gorilla; do
  # Minigraph-Cactus clips sequence it could not align (default clip graph), so a genome can come out
  # as one or more fragments named SAMPLE#HAP#CONTIG#OFFSET. Each fragment must equal the input at its
  # offset, and at least 95% of the input must be in the graph.
  vg paths -x out/primates.gbz -F -S sim$g 2>/dev/null > g.$g.fa
  r=$(python3 - "$D/sim$g.chr6.fa.gz" g.$g.fa <<'PY'
import sys, gzip
inp = ''.join(l.strip() for l in gzip.open(sys.argv[1], 'rt') if l[0] != '>').upper()
frags, name = {}, None
for l in open(sys.argv[2]):
    if l[0] == '>': name = l[1:].strip(); frags[name] = []
    else: frags[name].append(l.strip())
bad = kept = 0
for n, v in frags.items():
    seq = ''.join(v).upper(); off = int(n.rsplit('#', 1)[1]) if n.count('#') >= 3 else 0
    kept += len(seq); bad += inp[off:off + len(seq)] != seq
ok = frags and bad == 0 and kept >= 0.95 * len(inp)
print('%s %d fragment(s), %d of %d bp kept (%.1f%%), %d mismatching' % ('OK' if ok else 'BAD', len(frags), kept, len(inp), 100.0 * kept / max(1, len(inp)), bad))
PY
)
  case "$r" in OK*) ok "path-sim$g" "${r#OK }";; *) bad "path-sim$g" "${r#BAD }";; esac
done
n=$(zcat out/primates.vcf.gz 2>/dev/null | grep -vc '^#')
[ "${n:-0}" -gt 100 ] && ok vcf "out/primates.vcf.gz has $n variant records" || bad vcf "VCF missing or has ${n:-0} records"
v=$(vg stats -l out/primates.gbz 2>/dev/null | awk '{print $2}')
[ "${v:-0}" -gt 100000 ] && ok vg-stats "graph length $v bp" || bad vg-stats "vg stats failed or graph too small (${v:-0})"
echo "cactus: $fails failure(s)"
exit $fails
