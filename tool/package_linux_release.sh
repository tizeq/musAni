#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
revision=$(git -C "$repo" rev-parse --verify --end-of-options "${1:-HEAD}^{tree}")
output="$repo/build/releases"
native=$(realpath "${2:?pass the output directory of build_linux_taglib.sh}")
[[ $(uname -m) == x86_64 ]] || { echo 'Run the Linux x86-64 build on x86-64.' >&2; exit 1; }
for command in flutter curl patchelf file rg tar sha256sum; do
  command -v "$command" >/dev/null || { echo "Missing build tool: $command" >&2; exit 1; }
done

work=$(mktemp -d /tmp/musani-build.XXXXXX)
trap 'rm -rf -- "$work"' EXIT
source_dir="$work/source"
mkdir -p "$source_dir" "$output"
git -C "$repo" archive "$revision" -- lib linux assets pubspec.yaml pubspec.lock LICENSE COPYRIGHT \
  CHANGELOG.md docs/linux-release.md docs/linux-source-code.md docs/third-party-notices.md | tar -x -C "$source_dir"
version=$(awk '/^version: / {split($2, parts, "+"); print parts[1]}' "$source_dir/pubspec.yaml")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.]+)?$ ]]
name="musAni-v$version-linux-x86_64"
bundle="$work/$name"

(
  cd "$source_dir"
  flutter pub get --enforce-lockfile
  flutter build linux --release --no-pub
)
cp -a "$source_dir/build/linux/x64/release/bundle" "$bundle"

# CMake copies these plugins straight from the build tree.
for plugin in libfile_selector_linux_plugin.so libmedia_kit_libs_linux_plugin.so; do
  patchelf --set-rpath '$ORIGIN' "$bundle/lib/$plugin"
done
# The AOT manifest already records the relocatable lookup used at runtime.
cp "$bundle/data/flutter_assets/NativeAssetsManifest.json" "$bundle/lib/native_assets.json"

test -s "$native/flutter_taglib.o"
test -s "$native/libtaglib-static.a"
cp "$native/libflutter_taglib_native.so" "$bundle/lib/"
printf '%s\n' "$revision" > "$bundle/SOURCE-TREE"
cp "$source_dir/docs/linux-release.md" "$bundle/README-linux.md"
cp "$source_dir/docs/linux-source-code.md" "$bundle/SOURCE-CODE.md"
cp "$source_dir/docs/third-party-notices.md" "$bundle/THIRD-PARTY-NOTICES.md"
cp "$source_dir/CHANGELOG.md" "$source_dir/LICENSE" "$source_dir/COPYRIGHT" "$bundle/"
mkdir "$bundle/licenses"
sdk=$(dirname "$(dirname "$(realpath "$(command -v flutter)")")")
cp "$sdk/bin/cache/pkg/sky_engine/LICENSE" "$bundle/licenses/flutter-engine.txt"
cp "$sdk/bin/cache/artifacts/material_fonts/MaterialIcons_LICENSE.txt" "$bundle/licenses/"
while read -r filename sha256 url; do
  curl -fsSL --retry 2 "$url" -o "$bundle/licenses/$filename"
  printf '%s  %s\n' "$sha256" "$bundle/licenses/$filename" | sha256sum -c -
done <<'LICENSES'
flutter_taglib-LICENSE cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30 https://raw.githubusercontent.com/axel10/flutter_taglib/d2b7674b386583f5ef80188c3497709137dddae2/LICENSE
taglib-COPYING.LGPL dc626520dcd53a22f727af3ee42c770e56c97a64fe3adb063799d8ab032fe551 https://raw.githubusercontent.com/taglib/taglib/v2.3/COPYING.LGPL
taglib-AUTHORS 047780f6bded3712fc24edc77b9187bfa49ea3826ed090933cb6342458eace85 https://raw.githubusercontent.com/taglib/taglib/v2.3/AUTHORS
utfcpp-LICENSE c9bff75738922193e67fa726fa225535870d2aa1059f91452c411736284ad566 https://raw.githubusercontent.com/nemtrif/utfcpp/v4.0.9/LICENSE
hls.js-LICENSE ca8773cf798c7ed997d4dd7c8e23c348699f8d5b7462636694cc14de6cda12db https://raw.githubusercontent.com/video-dev/hls.js/v1.4.10/LICENSE
LICENSES

file "$bundle/musani" | rg -q 'ELF 64-bit.*x86-64'
if LC_ALL=C rg -al --hidden '/(home|Users|root)/[[:alnum:]_.-]+/' "$bundle"; then
  echo 'Bundle contains personal build paths.' >&2
  exit 1
fi
if find "$bundle" -type f -printf '%P\n' |
  rg -i '\.(mp3|flac|m4a|ogg|wav|opus|sqlite(-wal|-shm)?|pem|key)$|(^|/)(shared_preferences\.json|\.env(\..*)?)$'; then
  echo 'Bundle contains unexpected data or credentials.' >&2
  exit 1
fi

tar --sort=name --numeric-owner --owner=0 --group=0 -czf "$work/$name.tar.gz" -C "$work" "$name"
mv "$work/$name.tar.gz" "$output/$name.tar.gz"
(cd "$output"; sha256sum "$name.tar.gz" > "$name.tar.gz.sha256")
printf '%s\n' "$output/$name.tar.gz" "$output/$name.tar.gz.sha256"
