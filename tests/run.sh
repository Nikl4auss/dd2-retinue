#!/usr/bin/env bash
# Runs every tests/*_test.lua under plain Lua 5.4 (the pure modules only; no REFramework).
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT" || exit 1
export LUA_PATH="$ROOT/src/autorun/?.lua;;"

shopt -s nullglob
files=(tests/*_test.lua)
if (( ${#files[@]} == 0 )); then echo "FAIL: no test files found" >&2; exit 1; fi

failed=0
for f in "${files[@]}"; do
    if lua5.4 "$f"; then echo "PASS $f"; else echo "FAIL $f"; failed=1; fi
done
exit "$failed"
