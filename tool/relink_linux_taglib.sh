#!/usr/bin/env bash
set -euo pipefail

cxx=${CXX:-clang++}
"$cxx" -shared -Wl,--no-undefined -Wl,-soname,libflutter_taglib_native.so \
  -o "${3:?destination shared library}" "${1:?bridge object}" \
  -Wl,--whole-archive "${2:?TagLib static archive}" -Wl,--no-whole-archive -lcurl -lm
