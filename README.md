# pangenome-tools

Three environment modules for building and analysing human pangenome graphs. Each module is an
apptainer image with small wrapper commands, so nothing has to be compiled or installed on the
cluster.

| module | what it is | image |
|---|---|---|
| `cactus/4.0.0` | Minigraph-Cactus 4.0.0, unmodified upstream release (vg 1.78, minigraph 0.21, odgi 0.9, GFAffix 0.2.2, HAL tools, Toil 9.6) | `quay.io/comparative-genomics-toolkit/cactus:v4.0.0`, pinned by digest |
| `1kcp-builder/<version>` | the graph builder of the 1000 Chinese pangenome (1KCP; JianYang-Lab/1KCP-analysis, `02_Pangenome`) with the tool versions of the paper | built here |
| `pangenome-analysis/<version>` | analysis tools: Truvari, KMC, Liftoff, miniprot, pangene, rustybam, seqtk, WhatsHap, RFMix, python-igraph/leidenalg | built here |

The admin installs them with one script (see `ADMIN.md`). Users then run `module load ...`.

## Using the modules

```sh
module load cactus/4.0.0        # cactus-pangenome, vg, minigraph, odgi, hal*, samtools, ...
module load 1kcp-builder/<ver>  # kcp-init, kcp-snakemake, seqwish, smoothxg, genomescope2, kcp-vg, ...
module load pangenome-analysis/<ver>    # truvari, kmc, liftoff, miniprot, pangene, rb, seqtk, whatshap, rfmix, pga-python
module help pangenome-analysis/<ver>    # where the commands are; `ls` that folder to see all of them
```

The three modules can be loaded together: no command name appears in two of them, apart from
`pangenome-tools-selftest`, which is the same script in each. The 1KCP
builder's own copies of vg, odgi, minigraph, GFAffix and Mash are older than Cactus's, so they are
named `kcp-vg`, `kcp-odgi`, `kcp-minigraph`, `kcp-gfaffix` and `kcp-mash`. To run anything else
inside an image, use `cactus-exec CMD`, `kcp-exec CMD` or `pga-exec CMD`.

In the 1KCP image, Python code that does `import odgi` needs jemalloc preloaded, exactly as the
authors' rules do it: `kcp-exec env LD_PRELOAD=/opt/envs/kcp/lib/libjemalloc.so.2 python3 my.py`.
Without it, odgi aborts with "double free or corruption".

### Things that work differently from a local install

- **Cactus needs AVX2.** Cactus 4.0.0 is built for x86-64-v3. Some login nodes do not have
  AVX2, so the Cactus commands refuse to start there with a message that says so. The compute
  nodes have it. Run Cactus inside a job.
- **Files must be under a bound folder.** The containers see the folders the admin listed
  at install time (`--binds`; default `/home /data /scratch`) and the folder you are in. To add another, run `export PGT_BINDS="/other/path"`.
- **The container environment is clean.** Your shell's variables (conda, PYTHONPATH, ...) do not
  leak into the tools. `TMPDIR` and `OMP_NUM_THREADS` are passed through. Add others with
  `export PGT_ENV="NAME=value,NAME2=value2"`.
- **Apptainer's own INFO lines are hidden.** Its warnings and errors still show. To see the INFO lines too,
  run `export PGT_QUIET=0`.
- **Jobs run inside the container on one node.** Cactus (Toil `single_machine`) and the 1KCP
  Snakemake workflow cannot call `bsub` from inside the container. Submit the whole run as one LSF
  job on a large node, and give it the node's cores (`--maxCores N`, `kcp-snakemake -j N`).

### Minigraph-Cactus 4.0.0

```sh
module load cactus/4.0.0
cactus-pangenome ./js seqfile.txt --outDir out --outName pangenome --reference CHM13 GRCh38 \
    --vcf --giraffe clip --gbz clip full --haplo clip --maxCores 48 --workDir $TMPDIR
```

What changed since the 3.x releases is in the Cactus release notes: reproducible output, telomere and
subtelomere retention, the GAF CIGAR fix, index memory sized from the snarls, `--inGFA` to extend
an existing graph, and PanSN `SAMPLE#HAP` naming.

### 1KCP graph builder

The authors' workflow runs from a working directory. `kcp-init` creates one for your assemblies:

```sh
module load 1kcp-builder/<ver>
kcp-init mygraph --grch38 GRCh38.fa --chm13 chm13v2.0.fa --samples samples.tsv --reads reads.tsv
cd mygraph && kcp-snakemake -j 48 --keep-going      # inside one LSF job on a large node
```

- `samples.tsv` has one line per sample: `name <TAB> hap1.fa(.gz) <TAB> hap2.fa(.gz)`.
- `reads.tsv` has one line per read file: `name <TAB> reads.fq(.gz)`. The k-mer filter uses these
  reads. The paper used Illumina reads; HiFi reads work too.

Run `kcp-init --help` for all options.

The workflow is the authors' code at commit `f428f2445bbf`, with six small patches. `kcp-init`
applies them to the working copy. Each patch is in `images/kcp/patches/` with a comment saying why:

| patch | what it changes |
|---|---|
| 01 | assemblies come from `samples.tsv` and may be gzipped. The original hard-coded `../01_Assembly/results/...`. |
| 02 | reads for the k-mer filter come from `reads.tsv`. The original required Illumina R1/R2 templates. |
| 03 | node annotation is optional. The original always required per-haplotype annotation BEDs. |
| 04 | **bug fix** in `border_node_select.py`. For any reference path shorter than 20 Mb (e.g. chrM), the last chunk used an unset or stale loop variable. Paths of 20 Mb or more get exactly the same chunks as before. |
| 05 | the `gfaffix` rule fails if GFAffix produced no graph. Before, it reported success with an empty graph (see the versions note below). |
| 06 | the KMC memory cap is a setting: `kcp-init --kmc-mem`, default 20 GB as in the original. |

`kcp-init --no-patches` gives the unmodified workflow, which needs the original folder layout and
inputs.

**Versions differ from the paper in two places, both on purpose:**

- **smoothxg 0.7.4.** The paper says 0.7.9, a version that was never released. The released
  versions go from 0.7.4 to 0.8.0, and 0.7.4 is the last 0.7.x.
- **GFAffix 0.2.2.** The paper says 0.1.5, but its workflow reads the graph from standard output,
  and only GFAffix 0.2.0 and later write it there. With 0.1.5 every subgraph comes out empty.
  0.2.2 is also the version in Cactus 4.0.0.

All other versions match the paper's supplement: minigraph 0.21, odgi 0.8.6, seqwish 0.7.4,
vg 1.59.0, Mash 2.3, KMC 3.2.4 and GenomeScope 2.0.1. The full pinned environment is
`images/kcp/environment.yml`.

### Pangenome analysis tools

Truvari 4.2.2, KMC 3.2.4, Liftoff 1.6.3, miniprot 0.18, pangene 1.1 (with `pangene.js` and `k8`),
minimap2 2.31 (on the PATH as `paftools.js`; the `minimap2` command itself comes from the cactus
module, or run this one with `pga-exec minimap2`), rustybam 0.2.2 (`rb`), seqtk 1.5, WhatsHap 2.8, RFMix 2.03, and
`pga-python` (Python 3.11 with python-igraph, leidenalg, numpy, scipy, pandas and edlib). The
pinned environment is `images/analysis/environment.yml`.

## Selftest

`pangenome-tools-selftest` is on the PATH of all three modules.

- `quick` checks that every wrapper resolves and that each key tool reports its expected version.
  It takes about a minute.
- `full` also runs each image on small test data and checks the output content. It takes about
  10 minutes on 4 cores and needs AVX2. On the login node, use `--bsub` to submit it (the queue and LSF group the admin gave at install
  time are used; `--queue`/`--group` override them, and `--mem` sets the job's memory in MB).

The full test runs:

- **pangenome-analysis:** each tool on a small made-up genome.
- **1kcp-builder:** the whole workflow on a 2-sample toy. Every walk in the final graphs must spell
  its input sequence exactly.
- **cactus:** a 4-genome pangenome. Every genome must be in the graph and match its input.

## Building the images (maintainers)

The conda environments are installed from lock files (`images/*/*.lock`: every package with its
URL and md5), so a rebuild gets exactly the packages that were tested. The readable specs are the
`environment.yml` / `gs.yml` files next to them. To change a version, edit the spec, solve it,
and regenerate the lock with `micromamba env export -p /opt/envs/<env> --explicit --md5`.

`.github/workflows/release.yml` builds the two custom images on GitHub. It pulls Cactus by digest,
converts all three to `.sif`, runs `pangenome-tools-selftest full` on them, and publishes a release
with the `.sif` files, the scripts tarball and `SHA256SUMS`. To make a new release, update `VERSION`
and push a tag `v<version>`.

## Licence

MIT (see `LICENSE`) for the scripts, wrappers, patches and tests in this repository. The tools
inside the images keep their own licences; see `PUBLISH.md`.
