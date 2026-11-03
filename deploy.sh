#!/usr/bin/env bash
# Links the mod (src/autorun/*) and, optionally, the dev tools into the game's reframework/autorun folder:
# the read-only probe (tools/probe/*.lua) and the hooking experiments (tools/experiments/*.lua).
# Symlinks, so edits in the repo are live after "Reset scripts" in the REFramework menu.
#
#   ./deploy.sh                         link the mod
#   ./deploy.sh --probe                 link the mod and the probe
#   ./deploy.sh --experiments           link the mod and the experiments (they hook the game: back up first,
#                                       see tools/experiments/README.md)
#   ./deploy.sh --probe --experiments   link all three
#   ./deploy.sh --remove                remove every link this script created (mod, probe and experiments)
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
GAME="${DD2_DIR:-$HOME/Documentos/Games/Dragon Dogma 2}"
AUTORUN="$GAME/reframework/autorun"

probe=0 experiments=0 remove=0
for arg in "$@"; do
    case "$arg" in
        --probe) probe=1 ;;
        --experiments) experiments=1 ;;
        --remove) remove=1 ;;
        -h|--help) sed -n '2,/^set -/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (see --help)" >&2; exit 2 ;;
    esac
done

[[ -d "$AUTORUN" ]] || { echo "Not found: $AUTORUN (set DD2_DIR)" >&2; exit 1; }

sources=()
for f in "$ROOT"/src/autorun/*; do [[ "$(basename "$f")" == .gitkeep ]] || sources+=("$f"); done
if (( probe || remove )); then for f in "$ROOT"/tools/probe/*.lua; do sources+=("$f"); done; fi
if (( experiments || remove )); then for f in "$ROOT"/tools/experiments/*.lua; do sources+=("$f"); done; fi

for src in "${sources[@]}"; do
    [[ -e "$src" ]] || continue
    dst="$AUTORUN/$(basename "$src")"
    if (( remove )); then
        if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then rm "$dst"; echo "removed $dst"; fi
        continue
    fi
    if [[ -e "$dst" && ! -L "$dst" ]]; then
        echo "Refusing to replace a real file: $dst" >&2; exit 1
    fi
    ln -sfn "$src" "$dst"
    echo "linked $dst -> $src"
done
