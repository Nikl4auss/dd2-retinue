#!/usr/bin/env bash
# Watches the Dragon's Dogma 2 save folder while the SaveSlot experiment runs (tools/experiments/README.md) and logs
# every file that appears, changes or disappears, so the in-game log (Retinue_Exp_SaveSlot.lua) can be lined up with
# which dataNNNslot.bin was written when. READ-ONLY on the save folder: it only lists, stats and hashes.
#
#   tools/experiments/watch_saves.sh          poll once a second until Ctrl-C
#
# One line per event, to stdout and to
#   $DD2_DIR/reframework/data/Retinue/experiments/savefiles_<timestamp>.log
#   HH:MM:SS <event> <file> size=<n> mtime=<HH:MM:SS> sha1=<first 12 hex>
# event: initial (the listing at start), created, changed, deleted (size / mtime / sha1 are "-").
# A file caught mid-write may show the hash of a partial write; the next poll logs it again as "changed" if it moved on.
#
# Environment:
#   DD2_DIR        game folder (default: ~/Documentos/Games/Dragon Dogma 2)
#   DD2_SAVE_DIR   save folder (default: what `tools/saves.sh where` prints)
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
GAME="${DD2_DIR:-$HOME/Documentos/Games/Dragon Dogma 2}"
OUT_DIR="$GAME/reframework/data/Retinue/experiments"

die() { echo "$*" >&2; exit 1; }

SAVE_DIR="$("$ROOT/tools/saves.sh" where)" || die "Could not resolve the save folder (set DD2_SAVE_DIR)"
[[ -d "$SAVE_DIR" ]] || die "Not a directory: $SAVE_DIR"
mkdir -p -- "$OUT_DIR"
LOG="$OUT_DIR/savefiles_$(date +%Y%m%d_%H%M%S).log"

declare -A SIG=()     # file -> "size mtime" (mtime with sub-second precision, to catch quick rewrites)

emit() {  # emit <event> <file> <detail>
    local line
    line="$(date +%T) $1 $2 $3"
    printf '%s\n' "$line" | tee -a -- "$LOG"
}

sha12() {
    local h
    h="$(sha1sum -- "$1" 2>/dev/null | cut -c1-12)" || true
    printf '%s' "${h:--}"
}

# scan <initial|poll>: compare the folder with SIG / LINE and emit the differences.
scan() {
    local mode="$1" name size mtime sig detail event
    local -A seen=()
    while IFS=$'\t' read -r name size mtime; do
        seen["$name"]=1
        sig="$size $mtime"
        [[ "${SIG[$name]-}" == "$sig" ]] && continue
        if [[ "$mode" == initial ]]; then event=initial
        elif [[ -z "${SIG[$name]+x}" ]]; then event=created
        else event=changed; fi
        detail="size=$size mtime=$(date -d "@${mtime%.*}" +%T) sha1=$(sha12 "$SAVE_DIR/$name")"
        SIG["$name"]="$sig"
        emit "$event" "$name" "$detail"
    done < <(find "$SAVE_DIR" -maxdepth 1 -type f -printf '%f\t%s\t%T@\n' | LC_ALL=C sort)
    for name in "${!SIG[@]}"; do
        if [[ -z "${seen[$name]+x}" ]]; then
            unset 'SIG[$name]'
            emit deleted "$name" "size=- mtime=- sha1=-"
        fi
    done
}

trap 'echo; echo "stopped; log: $LOG"; exit 0' INT TERM

echo "watching $SAVE_DIR"
echo "log: $LOG (Ctrl-C to stop)"
scan initial
while true; do
    sleep 1
    scan poll
done
