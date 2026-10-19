#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
developer_dir="$(xcode-select -p)"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/disciplina-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
if [[ "$developer_dir" == */CommandLineTools ]]; then
  frameworks="$developer_dir/Library/Developer/Frameworks"
  swift test --disable-sandbox \
    --cache-path "${TMPDIR:-/tmp}/disciplina-spm-cache" \
    --config-path "${TMPDIR:-/tmp}/disciplina-spm-config" \
    --security-path "${TMPDIR:-/tmp}/disciplina-spm-security" \
    -Xswiftc -F -Xswiftc "$frameworks" \
    -Xlinker -rpath -Xlinker "$frameworks" \
    -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/usr/lib" \
    -Xlinker "-F$frameworks"
else
  swift test
fi
