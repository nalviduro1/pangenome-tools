# Installing pangenome-tools on a cluster

This adds three environment modules: `cactus/4.0.0`, `1kcp-builder/<version>` and
`pangenome-analysis/<version>`. Each is an apptainer image plus small wrapper scripts.

- Nothing is compiled.
- Nothing is downloaded on the cluster.
- No root is needed if you can write to the target folders.
- About 1.8 GB of disk.

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
     --binds "/home /data /scratch"     # the shared file systems users work in
```

The script stops with a message and installs nothing if any check fails. In order, it:

1. checks that apptainer runs;
2. checks the image checksums;
3. starts each image;
4. builds the install in a temporary folder and runs a quick selftest there;
5. only then moves the files and modulefiles into place.

**The default `cactus` module does not change.** If an older `cactus` module exists, it stays the
default, and the script writes `cactus/.version` to keep it. Users load the new one as `module load cactus/4.0.0`. Add
`--cactus-default` if you want 4.0.0 to be the default.

Run `install.sh --help` for the other options:

- `--binds` sets the folders the containers see. The default is `/home /data /scratch`.
- `--force` re-installs the same version.

## 3. Full selftest on a compute node (about 10 minutes)

```sh
module load pangenome-analysis/<version>
pangenome-tools-selftest full --bsub --workdir <scratch>/pgt-selftest   # add --group G / --queue Q if your site needs them
# when the job is done:
grep -E '^(OK|FAIL|SKIP)|failure' <scratch>/pgt-selftest/selftest.out
```

The last line must read `0 failure(s), 0 skipped`. The test builds a small pangenome with each
image and checks that the output sequence matches the input exactly.

## What is where

```
/opt/tools/pangenome-tools/<version>/
    sif/        the three images
    bin/cactus  bin/kcp  bin/analysis     one wrapper per command (module PATH)
    libexec/    pgt-exec (the apptainer call every wrapper makes), pgt-selftest
    etc/pgt.conf   apptainer path and bind list, recorded at install time
    share/      the tests and the per-module command lists
/opt/modulefiles/{cactus/4.0.0, 1kcp-builder/<version>, pangenome-analysis/<version>}
```

- **If apptainer moves**, edit `PGT_APPTAINER` in `etc/pgt.conf` and run the selftest again.
- **To uninstall**, remove the version folder and the three modulefiles. Also remove
  `cactus/.version` if the installer wrote it; its first comment line says so.
