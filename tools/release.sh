#!/usr/bin/env bash
# Builds the release zip: dist/Retinue-<version>.zip, laid out like the game folder (reframework/autorun/...), so it
# unpacks straight into the game folder or installs through Fluffy Mod Manager (modinfo.ini at the root).
#
#   tools/release.sh 0.1.0
#
# Refuses a dirty tree or failing tests: the zip is built from the committed src/autorun.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"

version="${1:?usage: tools/release.sh <version>}"
if [[ -n "$(git status --porcelain)" ]]; then echo "Working tree not clean; commit first." >&2; exit 1; fi
tests/run.sh >/dev/null || { echo "tests/run.sh failed" >&2; exit 1; }

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/reframework"
git archive HEAD src/autorun | tar -x -C "$stage"
mv "$stage/src/autorun" "$stage/reframework/autorun"
rmdir "$stage/src"
git show HEAD:LICENSE >"$stage/LICENSE"
cat >"$stage/modinfo.ini" <<INI
name=Retinue
version=$version
description=Adopt up to two hired pawns that keep their identity and progress and level up like the main pawn. Needs REFramework.
author=Nicolas Joel Marinelli
INI

mkdir -p dist
out="dist/Retinue-$version.zip"
rm -f "$out"
(cd "$stage" && bsdtar -a -cf "$ROOT/$out" modinfo.ini LICENSE reframework)
echo "$out"
