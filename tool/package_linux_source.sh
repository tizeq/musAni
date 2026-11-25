#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
commit=$(git -C "$repo" rev-parse --verify --end-of-options "${1:-HEAD}^{commit}")
tree=$(git -C "$repo" rev-parse "$commit^{tree}")
materials=$(realpath "${2:?pass the directory containing the matching upstream, notices and relink materials}")
mimalloc=$(realpath "${3:?pass the verified mimalloc-2.1.2.tar.gz build input}")
version=$(git -C "$repo" show "$commit:pubspec.yaml" | awk '/^version: / {split($2, parts, "+"); print parts[1]}')
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.]+)?$ ]]
name="musAni-v$version-linux-x86_64-source"
output="$repo/build/releases"

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/musAni"
mkdir -p "$output"
git -C "$repo" archive "$commit" | tar -x -C "$work/musAni"

test -s "$materials/BUILD-INFO"
test -s "$materials/relink/flutter_taglib.o"
test -s "$materials/relink/libtaglib-static.a"
cmp "$work/musAni/pubspec.lock" "$materials/musAni/pubspec.lock"
cp -a "$materials/BUILD-INFO" "$materials/notices" "$materials/relink" \
  "$materials/upstream" "$work/"
printf '%s  %s\n' '5179c8f5cf1237d2300e2d8559a7bc55' "$mimalloc" | md5sum -c -
cp "$mimalloc" "$work/upstream/mimalloc-2.1.2.tar.gz"
tar -xOf "$mimalloc" mimalloc-2.1.2/LICENSE > "$work/notices/mimalloc-LICENSE"
cp "$work/musAni/docs/linux-source-code.md" "$work/SOURCE-CODE.md"
printf '%s\n' "$commit" > "$work/SOURCE-COMMIT"
printf '%s\n' "$tree" > "$work/SOURCE-TREE"

tar --sort=name --numeric-owner --owner=0 --group=0 \
  --exclude='SHA256SUMS' --exclude='*.sha256' -czf "$work/$name.tar.gz" \
  -C "$work" BUILD-INFO SOURCE-CODE.md SOURCE-COMMIT SOURCE-TREE musAni notices relink upstream
mv "$work/$name.tar.gz" "$output/$name.tar.gz"
printf '%s\n' "$output/$name.tar.gz"
