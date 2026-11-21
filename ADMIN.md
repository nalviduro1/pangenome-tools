# Installing pangenome-tools on a cluster

This adds three environment modules: `cactus/4.0.0`, `1kcp-builder/<version>` and
`pangenome-analysis/<version>`. Each is an apptainer image plus small wrapper scripts.

- Nothing is compiled.
- Nothing is downloaded on the cluster.
- No root is needed if you can write to the target folders.
- About 1.6 GB of disk.

## 1. Download 5 files (on any machine with internet)

From the release page `https://github.com/<owner>/pangenome-tools/releases/tag/v<version>`:

```
pangenome-tools-<version>.tar.gz      scripts, tests, modulefile templates (< 1 MB)
cactus-4.0.0.sif                      ~0.5 GB
1kcp-builder-<version>.sif            ~0.8 GB
pangenome-analysis-<version>.sif              ~0.4 GB
SHA256SUMS
```

Copy all five into **one folder** on the cluster, for example `/opt/tools/src/pangenome-tools`.

## 2. Install (one command, about 3 minutes)

```sh
cd /opt/tools/src/pangenome-tools
tar xzf pangenome-tools-<version>.tar.gz
module load apptainer          # or pass --apptainer /path/to/apptainer
bash pangenome-tools-<version>/install.sh \
     --prefix /opt/tools/pangenome-tools \
     --modulefiles /opt/modulefiles \
     --binds "/home /data /scratch"
```

Change the three paths to yours (`--binds` = the shared file systems users work in). Add any of these
to the same command only if it applies; the script stops and tells you when one is needed:

| option | add it when |
|---|---|
| `--group <unix-group>` | `apptainer.conf` has `limit container groups`: use one of the groups listed there |
| `--lsf-queue <queue>` | the selftest job should not go to the queue `normal` |
| `--lsf-group <lsf-user-group>` | your LSF site requires `bsub -G` |
| `--lsf-select <resource>` | your AVX2 nodes carry a resource with another name than `avx2` (found automatically when it is `avx2`) |
| `--apptainer /path/to/apptainer` | apptainer is not on your PATH |

The script stops with a message and installs nothing if any check fails. In order, it:

1. checks that apptainer runs on its own, the way the wrappers call it (if it only runs with its module's
   `LD_LIBRARY_PATH`, the installer records that library folder so users do not need to load the module);
2. checks the image checksums;
3. checks `apptainer.conf` for `limit container groups / owners / paths`. Those limits do not apply to
   root, so an install tested as root would pass and users would still be refused. If the images would
   be refused, the script stops and says which `--group` to pass;
4. starts each image;
5. builds the install in a temporary folder and runs a quick selftest there, in a clean environment;
6. only then moves the files and modulefiles into place.

**The default `cactus` module does not change.** If an older `cactus` module exists in the
`--modulefiles` folder, it stays the default, and the script writes `cactus/.version` to keep it. If
the older `cactus` is in a different folder on `MODULEPATH`, the script stops before changing anything
and asks you to use that folder (or to pass `--cactus-default`). Users load the new one as `module load cactus/4.0.0`. Add
`--cactus-default` if you want 4.0.0 to be the default.

Run `install.sh --help` for the other options:

- `--binds` sets the folders the containers see. The default is `/home /data /scratch`.
- `--group G` gives the installed files group G (needed with `limit container groups`).
- `--lsf-queue Q`, `--lsf-group G`, `--lsf-select R` are recorded so that `pangenome-tools-selftest full --bsub` needs no extra options.
- `--force` re-installs the same version.

**Upgrading** to a later release is the same command with the new tarball. The `cactus/4.0.0`
modulefile is shared by all releases, so it is moved to the new release; the older release's own
modules stay and keep working until you remove them.

Requirements: apptainer 1.0 or later (tested with 1.5.0), Environment Modules or Lmod, bash. LSF is
used only by `pangenome-tools-selftest --bsub`; on other schedulers, run the selftest without `--bsub`
inside an interactive job on a compute node.

## 3. Full selftest on a compute node (about 10 minutes)

```sh
module load pangenome-analysis/<version>
pangenome-tools-selftest full --bsub --workdir <scratch>/pgt-selftest
# when the job is done:
grep -E '^(OK|FAIL|SKIP)|failure' <scratch>/pgt-selftest/selftest.out
```

Run it as an ordinary user, not root. The last line must read `0 failure(s), 0 skipped`. The test builds a small pangenome with each
image and checks that the output sequence matches the input exactly.

## What is where

```
/opt/tools/pangenome-tools/<version>/
    sif/        the three images
    bin/cactus  bin/kcp  bin/analysis     one wrapper per command (module PATH)
    libexec/    pgt-exec (the apptainer call every wrapper makes), pgt-selftest
    etc/pgt.conf   apptainer path, its library folder, bind list and selftest LSF settings, recorded at install time
    share/      the tests and the per-module command lists
/opt/modulefiles/{cactus/4.0.0, 1kcp-builder/<version>, pangenome-analysis/<version>}
```

- **If apptainer moves**, edit `PGT_APPTAINER` (and `PGT_APPTAINER_LD_LIBRARY_PATH`, if set) in `etc/pgt.conf` and run the selftest again.
- **To uninstall**, remove the version folder and the three modulefiles. Also remove
  `cactus/.version` if the installer wrote it; its second line says so.
