#!/usr/bin/env bash
# Back up and restore the Dragon's Dogma 2 save folder (and the mod's data folder) around in-game tests.
#
#   tools/saves.sh where              print the save folder that would be used
#   tools/saves.sh backup [label]     copy saves + reframework/data/Retinue into a new timestamped backup
#   tools/saves.sh list               list backups, newest last
#   tools/saves.sh restore <backup>   replace the live saves (and mod data) with a backup; takes a
#                                     "pre-restore" backup of the current state first
#
# Environment:
#   DD2_DIR         game folder (default: ~/Documentos/Games/Dragon Dogma 2)
#   DD2_SAVE_DIR    save folder (default: the most recently written .../2054970/remote/win64_save)
#   DD2_BACKUP_DIR  where backups go (default: $DD2_DIR/Retinue-backups)
#
# Refuses to run backup/restore while DD2.exe is running: the game may be mid-write.
set -euo pipefail

GAME="${DD2_DIR:-$HOME/Documentos/Games/Dragon Dogma 2}"
MOD_DATA="$GAME/reframework/data/Retinue"
BACKUPS="${DD2_BACKUP_DIR:-$GAME/Retinue-backups}"

die() { echo "$*" >&2; exit 1; }

# Most recently written save folder among the known Proton/Wine prefix locations. Found by data00-1.bin, the system
# save: every save folder has it, while data000.bin is deleted when slot 1 is converted for a restart.
save_dir() {
    if [[ -n "${DD2_SAVE_DIR:-}" ]]; then
        [[ -f "$DD2_SAVE_DIR/data00-1.bin" ]] || die "No data00-1.bin in DD2_SAVE_DIR=$DD2_SAVE_DIR"
        printf '%s\n' "$DD2_SAVE_DIR"; return
    fi
    local base f t best='' best_t=-1
    for base in \
        "$HOME/.local/share/crucible-launcher/Prefix" \
        "$HOME/.local/share/Steam/steamapps/compatdata" \
        "$HOME/.wine/drive_c/users"
    do
        [[ -d "$base" ]] || continue
        while IFS= read -r -d '' f; do
            t="$(stat -c %Y -- "$f")"
            if (( t > best_t )); then best_t=$t; best="$f"; fi
        done < <(find "$base" -type f -path '*/2054970/remote/win64_save/data00-1.bin' -print0 2>/dev/null)
    done
    [[ -n "$best" ]] || die "No DD2 save folder found (set DD2_SAVE_DIR)"
    dirname -- "$best"
}

game_not_running() {
    if pgrep -f 'DD2\.exe' >/dev/null; then die "DD2.exe is running. Quit the game first."; fi
}

# copy_verified <src dir> <dst dir>: copy a tree and fail unless the copy is byte-identical.
copy_verified() {
    mkdir -p -- "$2"
    cp -a -- "$1/." "$2/"
    diff -rq -- "$1" "$2" >/dev/null || die "Verification failed: $1 vs $2"
}

do_backup() {
    local label="${1:-}" src name dst
    [[ "$label" =~ ^[A-Za-z0-9_-]*$ ]] || die "Label may only contain letters, digits, - and _"
    game_not_running
    src="$(save_dir)"
    name="$(date +%Y%m%d-%H%M%S)${label:+-$label}"
    dst="$BACKUPS/$name"
    [[ -e "$dst" ]] && die "Already exists: $dst"
    copy_verified "$src" "$dst/win64_save"
    printf '%s\n' "$src" > "$dst/SOURCE.txt"
    [[ -d "$MOD_DATA" ]] && copy_verified "$MOD_DATA" "$dst/Retinue"
    echo "Backed up $(find "$dst/win64_save" -type f | wc -l) save files from $src"
    [[ -d "$dst/Retinue" ]] && echo "Backed up mod data from $MOD_DATA"
    echo "-> $dst"
}

do_list() {
    [[ -d "$BACKUPS" ]] || { echo "No backups yet ($BACKUPS)"; return; }
    ls -1 "$BACKUPS"
}

do_restore() {
    local name="${1:-}" from live recorded
    [[ -n "$name" ]] || die "Usage: tools/saves.sh restore <backup> (see: tools/saves.sh list)"
    from="$BACKUPS/$name"
    [[ -f "$from/win64_save/data00-1.bin" ]] || die "Not a backup: $from"
    game_not_running
    live="$(save_dir)"
    recorded="$(cat "$from/SOURCE.txt" 2>/dev/null || true)"
    if [[ -n "$recorded" && "$recorded" != "$live" ]]; then
        die "Backup came from $recorded but the live save folder is $live. Set DD2_SAVE_DIR to choose."
    fi
    do_backup pre-restore
    find "$live" -mindepth 1 -delete
    copy_verified "$from/win64_save" "$live"
    if [[ -d "$from/Retinue" ]]; then
        rm -rf -- "$MOD_DATA"
        copy_verified "$from/Retinue" "$MOD_DATA"
    elif [[ -d "$MOD_DATA" ]]; then
        rm -rf -- "$MOD_DATA"   # the backup predates any mod data: restore that state too
    fi
    echo "Restored $name into $live"
}

case "${1:-}" in
    where)   save_dir ;;
    backup)  do_backup "${2:-}" ;;
    list)    do_list ;;
    restore) do_restore "${2:-}" ;;
    *)       sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
