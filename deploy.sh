#!/usr/bin/env bash
# Links the mod (src/autorun/*) and, optionally, the dev tools (tools/probe/*.lua)
# into the game's reframework/autorun folder. Symlinks, so edits in the repo are live
# after "Reset scripts" in the REFramework menu.
#
#   ./deploy.sh            link the mod
#   ./deploy.sh --probe    link the mod and the probe
#   ./deploy.sh --remove   remove every link this script created
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
GAME="${DD2_DIR:-$HOME/Documentos/Games/Dragon Dogma 2}"
AUTORUN="$GAME/reframework/autorun"

[[ -d "$AUTORUN" ]] || { echo "Not found: $AUTORUN (set DD2_DIR)" >&2; exit 1; }

sources=()
for f in "$ROOT"/src/autorun/*; do [[ "$(basename "$f")" == .gitkeep ]] || sources+=("$f"); done
[[ "${1:-}" == --probe || "${1:-}" == --remove ]] && for f in "$ROOT"/tools/probe/*.lua; do sources+=("$f"); done

for src in "${sources[@]}"; do
    [[ -e "$src" ]] || continue
    dst="$AUTORUN/$(basename "$src")"
    if [[ "${1:-}" == --remove ]]; then
        if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then rm "$dst"; echo "removed $dst"; fi
        continue
    fi
    if [[ -e "$dst" && ! -L "$dst" ]]; then
        echo "Refusing to replace a real file: $dst" >&2; exit 1
    fi
    ln -sfn "$src" "$dst"
    echo "linked $dst -> $src"
done
