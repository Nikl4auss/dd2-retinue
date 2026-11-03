#!/usr/bin/env bash
# Links the mod (src/autorun/*) and, optionally, the dev tools into the game's reframework/autorun folder:
# the read-only probe (tools/probe/*.lua), the M1 hooking experiment (tools/experiments/Retinue_Exp_Hooks.lua)
# and the M2 lifecycle experiment (tools/experiments/Retinue_Exp_Lifecycle.lua).
# Symlinks, so edits in the repo are live after "Reset scripts" in the REFramework menu.
#
#   ./deploy.sh                         link the mod
#   ./deploy.sh --probe                 link the mod and the probe
#   ./deploy.sh --experiments           link the M1 experiment INSTEAD of the mod (it rewrites the hooked calls:
#                                       back up first, see tools/experiments/README.md)
#   ./deploy.sh --probe --experiments   link the M1 experiment and the probe, not the mod
#   ./deploy.sh --lifecycle             link the mod and the lifecycle experiment (log-only hooks plus a
#                                       test-actions panel that changes saves: back up first)
#   ./deploy.sh --probe --lifecycle     link the mod, the probe and the lifecycle experiment
#
# The mod and the M1 experiment hook the same methods, so they are never linked together: linking one while the
# other is linked fails (run --remove first). --lifecycle has no such conflict and combines with any of the above.
#   ./deploy.sh --remove                remove every link this script created (mod, probe and experiments)
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
GAME="${DD2_DIR:-$HOME/Documentos/Games/Dragon Dogma 2}"
AUTORUN="$GAME/reframework/autorun"

probe=0 experiments=0 lifecycle=0 remove=0
for arg in "$@"; do
    case "$arg" in
        --probe) probe=1 ;;
        --experiments) experiments=1 ;;
        --lifecycle) lifecycle=1 ;;
        --remove) remove=1 ;;
        -h|--help) sed -n '2,/^set -/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (see --help)" >&2; exit 2 ;;
    esac
done

[[ -d "$AUTORUN" ]] || { echo "Not found: $AUTORUN (set DD2_DIR)" >&2; exit 1; }

if (( !remove )); then
    if (( experiments )); then other="$AUTORUN/Retinue.lua"; else other="$AUTORUN/Retinue_Exp_Hooks.lua"; fi
    if [[ -e "$other" || -L "$other" ]]; then
        echo "Already linked: $other. The mod and the experiments must not run together; run --remove first." >&2
        exit 1
    fi
fi

sources=()
if (( remove || !experiments )); then
    for f in "$ROOT"/src/autorun/*; do [[ "$(basename "$f")" == .gitkeep ]] || sources+=("$f"); done
fi
if (( probe || remove )); then for f in "$ROOT"/tools/probe/*.lua; do sources+=("$f"); done; fi
if (( experiments || remove )); then sources+=("$ROOT/tools/experiments/Retinue_Exp_Hooks.lua"); fi
if (( lifecycle || remove )); then sources+=("$ROOT/tools/experiments/Retinue_Exp_Lifecycle.lua"); fi

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
