#!/usr/bin/env bash
set -euo pipefail

# The three inputs are the unpacked source archives in the Linux source kit.
bridge=$(realpath "${1:?flutter_taglib source directory}")
taglib=$(realpath "${2:?TagLib source directory}")
utfcpp=$(realpath "${3:?utfcpp source directory}")
mkdir -p "${4:?output directory}"
out=$(realpath "$4")
cxx=${CXX:-clang++}
jobs=${MUSANI_BUILD_JOBS:-6}
[[ $(uname -m) == x86_64 && "$jobs" =~ ^[1-9][0-9]*$ ]]

includes=(-I "$bridge/src" -I "$taglib" -I "$taglib/taglib" -I "$utfcpp/source")
while IFS= read -r -d '' directory; do
  includes+=(-I "$directory")
done < <(find "$taglib/taglib" -mindepth 1 -type d -print0 | sort -z)
flags=(-std=c++17 -O2 -fPIC -fvisibility=hidden -DHAVE_CONFIG_H=1 -DTAGLIB_STATIC=1)

# The bridge object is retained separately from the static TagLib objects.
objects=()
pids=()
while IFS= read -r -d '' source; do
  object="$out/objects/${source#"$taglib/taglib/"}.o"
  mkdir -p "$(dirname "$object")"
  "$cxx" "${flags[@]}" "${includes[@]}" -c "$source" -o "$object" &
  pids+=("$!")
  objects+=("$object")
  if (( ${#pids[@]} >= jobs )); then
    wait "${pids[0]}"
    pids=("${pids[@]:1}")
  fi
done < <(find "$taglib/taglib" -name '*.cpp' -type f -print0 | sort -z)
for pid in "${pids[@]}"; do wait "$pid"; done
ar crsD "$out/libtaglib-static.a" "${objects[@]}"
"$cxx" "${flags[@]}" "${includes[@]}" -c "$bridge/src/flutter_taglib.cpp" -o "$out/flutter_taglib.o"
bash "$(dirname "$0")/relink_linux_taglib.sh" "$out/flutter_taglib.o" \
  "$out/libtaglib-static.a" "$out/libflutter_taglib_native.so"
