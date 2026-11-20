# Publishing pangenome-tools on GitHub

This folder is a complete repository. GitHub Actions builds the images, tests them as the admin
would install them, and attaches the files to a release. Nothing has to be built by hand.

1. Create an empty GitHub repository, e.g. `pangenome-tools`. It can be private, but then the admin
   needs access to download the release files.
2. Upload this folder's contents to it, including the hidden `.github/` folder:

   ```sh
   cd 07_utils/pangenome-tools
   git init -b main && git add -A && git commit -m "pangenome-tools 2026.11.1"
   git remote add origin https://github.com/<you>/pangenome-tools.git && git push -u origin main
   ```

3. Start the release: **Actions → release → Run workflow**, tick **publish**, then click **Run workflow**.
   (Pushing a tag `v<VERSION>` does the same.)
4. Watch the run. It takes about 30–45 minutes. It builds the images, runs `build/test-release.sh`
   (the admin's install plus the full selftest), and only if every check passes creates the tag
   `v<VERSION>` and the release with the 5 files.
5. Send the admin `ADMIN.md` with `<owner>` and `<version>` filled in. The release page lists the
   5 files to download.

Without **publish** ticked, the run only builds and tests; the files are kept as a downloadable
artifact for 3 days.

## Licences of what the images contain

- **Cactus:** the unmodified upstream image.
- **1KCP-analysis:** MIT licence, kept at `/opt/1KCP-analysis/LICENSE` in the image.
- **The conda packages:** each keeps its own licence inside the image.

The patches and scripts in this folder are yours. Add a `LICENSE` file if the repository is public.
