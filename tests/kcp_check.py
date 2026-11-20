#!/usr/bin/env python3
"""Check the final graphs of a 1KCP-builder run on the toy data.
usage: kcp_check.py RUN_DIR TOY_DIR
Asserts, per final subgraph GFA:
  - it has segments, links and walks;
  - every input haplotype (CHM13, GRCh38, S1/S2 hap1/hap2) has at least one walk;
  - the GRCh38 and CHM13 walks are one walk each and spell their input chromosome exactly;
  - every sample walk spells an exact substring of its input contig (no invented sequence).
Prints OK/FAIL lines; exit status = number of failures."""
import sys, glob, gzip, os, re
run, toy = sys.argv[1], sys.argv[2]
def fasta(p):
    op = gzip.open if p.endswith('.gz') else open
    d, n = {}, None
    with op(p, 'rt') as f:
        for l in f:
            if l[0] == '>': n = l[1:].split()[0]; d[n] = []
            else: d[n].append(l.strip())
    return {k: ''.join(v) for k, v in d.items()}
inp = {'GRCh38': fasta(os.path.join(toy, 'GRCh38.fa')), 'CHM13': fasta(os.path.join(toy, 'CHM13.fa'))}
for s in ('S1', 'S2'):
    for h in (1, 2):
        inp['%s.hap%d' % (s, h)] = fasta(os.path.join(toy, '%s.hap%d.fa.gz' % (s, h)))
comp = str.maketrans('ACGTN', 'TGCAN')
fails = 0
def report(ok, name, msg):
    global fails
    print(('OK    ' if ok else 'FAIL  ') + '%-14s %s' % (name, msg)); fails += (not ok)
gfas = sorted(glob.glob(os.path.join(run, 'results/subgraph/subgraph_*/minigraph_*.seqwish.smoothxg.gfaffix.clip.kmer.chop.ids.gfa')))
report(len(gfas) == 2, 'kcp-graphs', '%d final subgraph GFAs (expect 2, one per toy chromosome)' % len(gfas))
for g in gfas:
    sid = re.search(r'subgraph_(\d+)/', g).group(1)
    seg, walks, nl = {}, [], 0
    for l in open(g):
        f = l.rstrip('\n').split('\t')
        if f[0] == 'S': seg[f[1]] = f[2]
        elif f[0] == 'L': nl += 1
        elif f[0] == 'W': walks.append(f)
    def spell(w):
        out = []
        for o, n in re.findall(r'([<>])([^<>]+)', w[6]):
            s = seg[n]; out.append(s if o == '>' else s[::-1].translate(comp))
        return ''.join(out)
    tag = 'subgraph_' + sid
    report(len(seg) > 0 and nl > 0 and len(walks) > 0, tag, '%d segments, %d links, %d walks' % (len(seg), nl, len(walks)))
    seen = {}
    for w in walks:
        seen.setdefault((w[1], w[2]), []).append(w)
    for ref in ('GRCh38', 'CHM13'):
        ws = [w for (s, h), v in seen.items() if s == ref for w in v]
        chrom = ws[0][3].split('.', 1)[1] if ws else None
        good = len(ws) == 1 and spell(ws[0]) == inp[ref].get(chrom)
        report(good, tag, '%s: %d walk(s), spells input %s exactly: %s' % (ref, len(ws), chrom, good))
    for s in ('S1', 'S2'):
        for h in (0, 1):
            ws = seen.get((s, str(h)), [])
            key = '%s.hap%d' % (s, h + 1)
            bad = 0; bp = 0
            for w in ws:
                contig = w[3].split('.', 2)[2]
                seq = spell(w); bp += len(seq)
                ref = inp[key][contig]
                st, en = int(w[4]), int(w[5])
                if ref[st:en] != seq: bad += 1
            report(len(ws) > 0 and bad == 0, tag, '%s: %d walk(s), %d bp, all match the input contig at their coordinates: %s' % (key, len(ws), bp, bad == 0))
print('kcp-toy-check: %d failure(s)' % fails)
sys.exit(fails)
