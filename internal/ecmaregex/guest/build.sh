#!/bin/sh
set -eu

if [ "$#" -ne 4 ]; then
  echo "usage: build.sh quickjs-v0.15.1.tar.gz regexpp-4.12.2.tgz wasi-sdk-33.0-arm64-macos.tar.gz output.wasm" >&2
  exit 2
fi

quickjs_archive=$1
regexpp_archive=$2
wasi_archive=$3
output_dir=$(CDPATH= cd -- "$(dirname -- "$4")" && pwd)
output="$output_dir/$(basename -- "$4")"
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/refine-ecmaregex-build-XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}
require_hash() {
  actual=$(sha256 "$1")
  if [ "$actual" != "$2" ]; then
    echo "SHA-256 mismatch for $1: $actual" >&2
    exit 1
  fi
}

require_hash "$quickjs_archive" c4e813951b7c46845096a948e978c620b11ab4cf5fd622ca09c727ec31f42623
require_hash "$regexpp_archive" b5cb22e604ad47f511e96b7aa57910995994f3e48744fbc507018da9efae0f12
require_hash "$wasi_archive" 85c997a2665ead91673b5bb88b7d0df3fc8900df3bfa244f720d478187bbdc78

tar -xzf "$quickjs_archive" -C "$work"
mkdir "$work/regexpp"
tar -xzf "$regexpp_archive" -C "$work/regexpp" --strip-components=1
tar -xzf "$wasi_archive" -C "$work"
patch -s -p1 -d "$work/quickjs-0.15.1" < "$root/quickjs-libregexp-interrupt.patch"

{
  sed -n '1p' "$work/regexpp/index.js"
  printf 'var exports = {};\n'
  sed -n '2,$p' "$work/regexpp/index.js" | sed '$d'
  cat "$root/regexpp_epilogue.js"
  tail -n 1 "$work/regexpp/index.js"
} > "$work/regexpp_init.js"
go run "$root/embed_source.go" "$work/regexpp_init.js" "$work/regexpp_source.inc"
cp "$root/regex_abi.c" "$root/no_capabilities.c" "$work/"

(cd "$work" && \
  wasi=wasi-sdk-33.0-arm64-macos && \
  "$wasi/bin/clang" --target=wasm32-wasip1 \
    --sysroot="$wasi/share/wasi-sysroot" \
    -O2 -flto -ffunction-sections -fdata-sections -D_GNU_SOURCE \
    -I quickjs-0.15.1 -I . \
    quickjs-0.15.1/dtoa.c quickjs-0.15.1/libregexp.c \
    quickjs-0.15.1/libunicode.c quickjs-0.15.1/quickjs.c \
    regex_abi.c no_capabilities.c \
    -nostartfiles -Wl,--no-entry -Wl,--gc-sections -Wl,--strip-all \
    -Wl,--max-memory=33554432 \
    -Wl,--export=regex_abi_version -Wl,--export=regex_init \
    -Wl,--export=regex_alloc -Wl,--export=regex_free \
    -Wl,--export=regex_compile -Wl,--export=regex_test \
    -Wl,--export=regex_release -Wl,--export=regex_reset \
    -Wl,--export=regex_destroy \
    -Wl,--export-memory -lm -o "$output")

require_hash "$output" ee1ff0212d3a3bd28a72f00033f51dad747c8b36e9302edbbbd35cf6a58bfe8f
