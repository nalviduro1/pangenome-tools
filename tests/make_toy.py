#!/usr/bin/env python3
"""Deterministic toy data for the 1KCP builder self-test.

Writes, into the directory given as argv[1]:
  GRCh38.fa, CHM13.fa       two 'references' (chr1 300 kb, chr2 200 kb; CHM13 = GRCh38 with ~0.1% SNVs)
  S1.hap1.fa.gz ...          2 samples x 2 haplotypes, each = GRCh38 with ~0.3% SNVs plus a few
                             structural variants (insertions and deletions of 300 bp - 3 kb), gzipped
                             to exercise the gzip-input patch
  S1.reads.fq.gz ...         error-free 8 kb reads from both haplotypes, ~20x per haplotype
  samples.tsv, reads.tsv     the sheets kcp-init reads
Pure Python, no dependencies, seed fixed so the files are identical on every run.
"""
import gzip, os, random, sys

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
rng = random.Random(20261120)
B = "ACGT"

def rand_seq(n):
    return "".join(rng.choice(B) for _ in range(n))

def mutate(seq, rate):
    s = list(seq)
    for i in range(len(s)):
        if rng.random() < rate:
            s[i] = rng.choice([b for b in B if b != s[i]])
    return "".join(s)

def add_svs(seq, n):
    # apply from the right so earlier positions stay valid
    pos = sorted(rng.sample(range(20000, len(seq) - 20000), n), reverse=True)
    for p in pos:
        L = rng.randint(300, 3000)
        if rng.random() < 0.5:
            seq = seq[:p] + rand_seq(L) + seq[p:]          # insertion
        else:
            seq = seq[:p] + seq[p + L:]                    # deletion
    return seq

def write_fa(path, recs, gz=False):
    op = gzip.open if gz else open
    with op(path, "wt") as fh:
        for name, s in recs:
            fh.write(">%s\n" % name)
            for i in range(0, len(s), 80):
                fh.write(s[i:i + 80] + "\n")

ref = [("chr1", rand_seq(300000)), ("chr2", rand_seq(200000))]
write_fa(os.path.join(out, "GRCh38.fa"), ref)
write_fa(os.path.join(out, "CHM13.fa"), [(n, mutate(s, 0.001)) for n, s in ref])

samples, reads = [], []
for smp in ("S1", "S2"):
    haps = {}
    for hap in ("hap1", "hap2"):
        recs = [("h%stg%06dl" % (hap[-1], i + 1), add_svs(mutate(s, 0.003), 3)) for i, (n, s) in enumerate(ref)]
        haps[hap] = recs
        write_fa(os.path.join(out, "%s.%s.fa.gz" % (smp, hap)), recs, gz=True)
    fq = os.path.join(out, "%s.reads.fq.gz" % smp)
    with gzip.open(fq, "wt") as fh:
        k = 0
        for hap, recs in haps.items():
            for name, s in recs:
                nreads = len(s) * 20 // 8000
                for _ in range(nreads):
                    st = rng.randint(0, max(0, len(s) - 8000))
                    r = s[st:st + 8000]
                    if rng.random() < 0.5:
                        r = r[::-1].translate(str.maketrans("ACGT", "TGCA"))
                    k += 1
                    fh.write("@%s_r%d\n%s\n+\n%s\n" % (smp, k, r, "I" * len(r)))
    samples.append("%s\t%s\t%s" % (smp, os.path.join(out, smp + ".hap1.fa.gz"), os.path.join(out, smp + ".hap2.fa.gz")))
    reads.append("%s\t%s" % (smp, fq))

open(os.path.join(out, "samples.tsv"), "w").write("\n".join(samples) + "\n")
open(os.path.join(out, "reads.tsv"), "w").write("\n".join(reads) + "\n")
print("toy data written to", out)
