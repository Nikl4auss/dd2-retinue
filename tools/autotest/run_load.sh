#!/usr/bin/env bash
# Launches the game, loads the last saved data with keys only, waits until 16 s after entering the world, prints the
# run's [Retinue] log lines and terminates the game. Nothing else: restore, roster edits and checks stay with the caller.
#
#   tools/autotest/run_load.sh [label]    label names the screenshots (default: run)
#
# Needs KDE Wayland (KWin scripting, spectacle), a running ydotoold and Python with Pillow. The display must be 1920x1080.
# Do not use the PC during a run: keys go to the active window. The script checks that the game has the focus before
# each key press, and on losing it terminates the game without sending more keys.
# Screenshots go to $DD2_AUTOTEST_DIR (default: a new temporary folder, printed at the start).
#
# Keys: PageUp closes the REFramework menu (it opens at every start and swallows input), F confirms. Enter does not.
# It presses "Load from Last Saved Data", the title's first entry, so the slot is the last one played: check the log.
# The game is terminated with SIGTERM: it ignores a window close while the server-error dialog is up. Saves are not
# written by this run unless the game autosaves.
set -u

export YDOTOOL_SOCKET="${YDOTOOL_SOCKET:-/run/user/$(id -u)/.ydotool_socket}"
GAME="${DD2_DIR:-$HOME/Documentos/Games/Dragon Dogma 2}"
LOG="$GAME/re2_framework_log.txt"
CRUCIBLE="${DD2_CRUCIBLE:-$HOME/Documentos/Games/Crucible-x86_64.AppImage}"
WORK="${DD2_AUTOTEST_DIR:-$(mktemp -d)}"
LABEL="${1:-run}"
START=$(date '+%Y-%m-%d %H:%M:%S.000')

mkdir -p "$WORK"
echo "screenshots: $WORK"

cat > "$WORK/active.js" <<'JS'
var a = workspace.activeWindow;
print("ACTIVEWIN:" + (a ? a.caption + "|" + a.resourceClass : "none"));
JS

active_window() {
    local since id
    since=$(date '+%Y-%m-%d %H:%M:%S')
    id=$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$WORK/active.js" "autotest$RANDOM$RANDOM")
    qdbus6 org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run >/dev/null
    sleep 0.4
    qdbus6 org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.stop >/dev/null
    journalctl --user --since "$since" | grep -a 'ACTIVEWIN:' | sed 's/.*ACTIVEWIN://' | tail -1
}

game_focused() {
    case "$(active_window)" in "Dragon's Dogma 2|"*) return 0 ;; *) return 1 ;; esac
}

press() {
    ydotool key "$1:1" >/dev/null
    sleep 0.2
    ydotool key "$1:0" >/dev/null
}

shot() {
    spectacle -b -n -f -o "$WORK/$1.png" 2>/dev/null
}

# True when the REFramework menu's title bar is on screen, which means the game is drawing its first screen.
menu_visible() {
    python3 -I - "$WORK/wait.png" <<'PY' 2>/dev/null
import sys
from PIL import Image
sys.exit(0 if Image.open(sys.argv[1]).convert('L').crop((1372, 20, 1900, 60)).resize((1, 1)).getpixel((0, 0)) > 25 else 1)
PY
}

# This run's lines only: the log of the previous run stays on disk until the game rewrites it.
run_lines() {
    grep -a '\[Retinue\]' "$LOG" 2>/dev/null | awk -v s="[$START" '$0 >= s'
}

stop_game() {
    local pid
    pid=$(pgrep -x DD2.exe)
    [ -n "$pid" ] && kill -TERM "$pid"
    for _ in $(seq 1 20); do
        pgrep -x DD2.exe >/dev/null || { echo "game closed"; return 0; }
        sleep 2
    done
    echo "GAME STILL UP"
    return 1
}

fail() {
    echo "$1"
    shot "$LABEL-fail"
    stop_game
    exit "${2:-1}"
}

if pgrep -x DD2.exe >/dev/null; then
    echo "The game is already running." >&2
    exit 1
fi

"$CRUCIBLE" --launch "Dragon's Dogma 2" >/dev/null 2>&1 &

for i in $(seq 1 60); do
    sleep 4
    shot wait
    if menu_visible; then
        echo "first screen after ~$((i * 4))s"
        break
    fi
    [ "$i" = 60 ] && fail "TIMEOUT first screen"
done

game_focused || fail "NOT FOCUSED: $(active_window)" 2
press 104 # PageUp
sleep 1.5

# Early presses land before the screen is ready, so keep pressing: one F for the notice, one for the title entry.
for i in $(seq 1 20); do
    game_focused || fail "LOST FOCUS: $(active_window)" 2
    press 33 # F
    sleep 4
    if run_lines | grep -aq 'load request'; then
        echo "load requested after $i F presses"
        break
    fi
    [ "$i" = 20 ] && fail "TIMEOUT load"
done

for i in $(seq 1 90); do
    pgrep -x DD2.exe >/dev/null || { echo "GAME GONE"; exit 1; }
    if run_lines | grep -aq 'in the world: yes'; then
        echo "in world"
        break
    fi
    sleep 2
    [ "$i" = 90 ] && fail "TIMEOUT world"
done

# The reconciliation pass runs 3 s after entering the world, the backup poll at about 13 s.
sleep 16
shot "$LABEL-world"
run_lines | cut -c1-175
stop_game
