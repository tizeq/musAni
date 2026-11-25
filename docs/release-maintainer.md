# Linux release packaging

Verify the release branch with `bash tool/verify.sh` and `git diff --check`.
The version in `pubspec.yaml` determines the Linux archive names.

Build or obtain the matching TagLib bridge and its relinking objects. The
source materials directory contains `BUILD-INFO`, `musAni/pubspec.lock`,
`upstream/`, `notices/`, and `relink/`. Keep the Flutter and dependency
revisions in the source kit aligned with the binary. When those revisions are
unchanged, the matching materials and native bridge from the last release
can be reused.

```sh
bash tool/package_linux_release.sh HEAD /path/to/native-bridge
bash tool/package_linux_source.sh HEAD /path/to/source-materials \
  build/linux/x64/release/mimalloc-2.1.2.tar.gz
```

When the dependency download is unavailable, set `MUSANI_MIMALLOC_ARCHIVE`
to the absolute path of the locally cached archive for the binary packaging
command. The build validates that dependency with its pinned checksum.

Both archives are written to `build/releases/`. Verify that their
`SOURCE-TREE` values match, then extract and smoke-test the binary bundle.
Attach the binary archive and the corresponding source and relinking archive
to the release.
