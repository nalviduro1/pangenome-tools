#!/bin/bash
# Functional tests for the pangenome-analysis image. Runs INSIDE the container: tests/run-tests calls
#   apptainer exec <sif> bash analysis.sh <workdir>
# Each test runs the tool on a small input made here and checks the CONTENT of the output.
# Prints one line per test: OK / FAIL <name> <detail>; exit status = number of failures.
set -u
W=${1:?workdir}; mkdir -p "$W" && cd "$W" || exit 99
fails=0
ok()   { printf 'OK    %-14s %s\n' "$1" "$2"; }
bad()  { printf 'FAIL  %-14s %s\n' "$1" "$2"; fails=$((fails+1)); }
run()  { # name, check-description, command...  (command's stderr kept in $W/<name>.err)
  local n=$1 d=$2; shift 2
  if ( "$@" ) > "$n.out" 2> "$n.err"; then ok "$n" "$d"; else bad "$n" "$d -- see $W/$n.err: $(tail -n 2 "$n.err" | tr '\n' ' ')"; fi; }

python3 - <<'PY' || { echo "FAIL  setup          could not make test data"; exit 99; }
import random
random.seed(7)
B="ACGT"
ref=''.join(random.choice(B) for _ in range(30000))
# a 3-exon gene on the + strand, CDS 1,200 bp
ex=[(2001,2400),(5001,5400),(8001,8400)]
cds=''.join(ref[a-1:b] for a,b in ex)
start="ATG"; stop="TAA"
cds=start+cds[3:-3]
# remove internal stops so the protein is a full-length ORF
codons=[cds[i:i+3] for i in range(0,len(cds),3)]
codons=[c if c not in ("TAA","TAG","TGA") else "TCA" for c in codons]+[stop]
cds=''.join(codons)
# write the CDS back into the reference across the exons
pos=0; r=list(ref)
for a,b in ex:
    L=b-a+1; r[a-1:b]=cds[pos:pos+L]; pos+=L
# GT..AG introns
for (a,b),(c,d) in zip(ex,ex[1:]):
    r[b:b+2]=list("GT"); r[c-3:c-1]=list("AG")
ref=''.join(r)
tgt=list(ref)
for i in range(0,len(tgt),97):
    if not any(a-1<=i<b for a,b in ex): tgt[i]={'A':'C','C':'G','G':'T','T':'A'}[tgt[i]]
tgt=''.join(tgt)
open("ref.fa","w").write(">chrT\n"+ref+"\n")
open("tgt.fa","w").write(">chrT\n"+tgt+"\n")
code={}
bases="TCAG"; aa="FFLLSSSSYY**CC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG"
for i,a in enumerate(aa): code[bases[i//16]+bases[i//4%4]+bases[i%4]]=a
prot=''.join(code[cds[i:i+3]] for i in range(0,len(cds)-3,3))
open("prot.fa","w").write(">GENE1\n"+prot+"\n")
with open("ref.gff","w") as g:
    g.write("##gff-version 3\n")
    g.write(f"chrT\tt\tgene\t{ex[0][0]}\t{ex[-1][1]}\t.\t+\t.\tID=GENE1;Name=GENE1\n")
    g.write(f"chrT\tt\tmRNA\t{ex[0][0]}\t{ex[-1][1]}\t.\t+\t.\tID=TX1;Parent=GENE1\n")
    for k,(a,b) in enumerate(ex):
        g.write(f"chrT\tt\texon\t{a}\t{b}\t.\t+\t.\tID=EX{k};Parent=TX1\n")
        g.write(f"chrT\tt\tCDS\t{a}\t{b}\t.\t+\t0\tID=CDS1;Parent=TX1\n")
# reads for kmc: 300 x 1 kb error-free from ref
with open("reads.fa","w") as f:
    for i in range(300):
        s=random.randrange(0,len(ref)-1000); f.write(f">r{i}\n{ref[s:s+1000]}\n")
# VCFs for truvari: one 500 bp deletion called in both, comp 3 bp shifted
hdr="##fileformat=VCFv4.2\n##contig=<ID=chrT,length=30000>\n##INFO=<ID=SVTYPE,Number=1,Type=String,Description=\"t\">\n##INFO=<ID=SVLEN,Number=1,Type=Integer,Description=\"t\">\n##FORMAT=<ID=GT,Number=1,Type=String,Description=\"t\">\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tS\n"
def rec(p): return f"chrT\t{p}\t.\t{ref[p-1:p+500]}\t{ref[p-1]}\t60\tPASS\tSVTYPE=DEL;SVLEN=-500\tGT\t0/1\n"
open("base.vcf","w").write(hdr+rec(15001)); open("comp.vcf","w").write(hdr+rec(15004))
PY

# --- k-mer counting -------------------------------------------------------------------------
mkdir -p kmctmp; run kmc "kmc count + kmc_tools histogram is non-empty" bash -c 'kmc -k21 -m2 -t2 -fm reads.fa kmcdb kmctmp && kmc_tools transform kmcdb histogram kmc.histo -cx100 && awk '"'"'$2>0{n++} END{exit !(n>5)}'"'"' kmc.histo'
run kmc_dump "kmc_dump writes k-mers" bash -c 'kmc_dump kmcdb kmc.dump && [ "$(wc -l < kmc.dump)" -gt 1000 ]'

# --- SV comparison --------------------------------------------------------------------------
run truvari "truvari bench matches a 500 bp DEL shifted 3 bp (TP=1)" bash -c '
  for v in base comp; do bgzip -f $v.vcf && tabix -f -p vcf $v.vcf.gz; done
  rm -rf tv && truvari bench -b base.vcf.gz -c comp.vcf.gz -o tv --pctseq 0 >/dev/null 2>&1
  python3 -c "import json,sys; s=json.load(open(\"tv/summary.json\")); sys.exit(0 if s[\"TP-base\"]==1 and s[\"FP\"]==0 else 1)"'

# --- annotation transfer --------------------------------------------------------------------
run liftoff "liftoff carries GENE1 (3 exons) to a diverged copy" bash -c '
  rm -rf lo && mkdir lo && cd lo && liftoff -g ../ref.gff -o lifted.gff3 -u unmapped.txt ../tgt.fa ../ref.fa >/dev/null 2>&1
  awk -F"\t" '"'"'$3=="gene" && $9~/GENE1/{g++} $3=="exon"{e++} END{exit !(g==1 && e==3)}'"'"' lifted.gff3'
run miniprot "miniprot aligns GENE1 protein with 3 CDS exons" bash -c '
  miniprot -t2 --gff ref.fa prot.fa > mp.gff 2>/dev/null
  awk -F"\t" '"'"'$3=="CDS"{c++} END{exit !(c==3)}'"'"' mp.gff'
run pangene "pangene builds a gene graph from two genomes" bash -c '
  miniprot -t2 -c 1 --outs=0.97 ref.fa prot.fa > a.paf 2>/dev/null; miniprot -t2 --outs=0.97 tgt.fa prot.fa > b.paf 2>/dev/null
  pangene a.paf b.paf > pg.gfa 2>/dev/null && grep -q "^S" pg.gfa && grep -c "^W" pg.gfa | grep -qx 2'
run pangene.js "k8 pangene.js gfa2matrix reads the gene graph" bash -c 'pangene.js gfa2matrix pg.gfa > pg.mat && grep -q GENE1 pg.mat'
run paftools "k8 paftools.js call finds the 1 bp SNVs between copies" bash -c '
  minimap2 -cx asm5 --cs ref.fa tgt.fa 2>/dev/null | sort -k6,6 -k8,8n > rt.paf && paftools.js call -l 1000 -L 1000 rt.paf 2>/dev/null | awk '"'"'$1=="V" && $4-$3==1{n++} END{exit !(n>200)}'"'"''
run rustybam "rb stats summarises the PAF" bash -c 'rb stats --paf rt.paf > rb.tsv && [ "$(grep -vc "^#" rb.tsv)" -ge 1 ]'
run seqtk "seqtk comp counts 30,000 bp" bash -c 'seqtk comp ref.fa | awk '"'"'{exit !($2==30000)}'"'"''

# --- phasing / ancestry / clustering ------------------------------------------------------------
run whatshap "whatshap stats reads a VCF" bash -c 'whatshap stats base.vcf.gz > wh.txt 2>/dev/null && grep -qi variants wh.txt'
run rfmix "rfmix starts and prints its usage" bash -c 'rfmix 2>&1 | grep -qi "query-file\|-f "'
run leiden "leidenalg finds communities in the karate-club graph" python3 -c '
import igraph as ig, leidenalg as la
g=ig.Graph.Famous("Zachary"); p=la.find_partition(g, la.ModularityVertexPartition, seed=1)
assert len(p)>=3 and g.modularity(p.membership)>0.35, (len(p), g.modularity(p.membership))'
run python-libs "numpy, scipy, pandas, edlib import and work" python3 -c '
import numpy, scipy.stats, pandas, edlib
assert edlib.align("ACGTACGT","ACGAACGT")["editDistance"]==1'

echo "pangenome-analysis: $fails failure(s)"
exit $fails
