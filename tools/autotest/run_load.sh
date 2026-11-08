#!/usr/bin/env bash
# Launches the game headless inside gamescope, loads the last saved data with keys only, waits until 16 s after entering
# the world, prints the run's [Retinue] log lines and terminates the game. Nothing else: restore, roster edits and checks
# stay with the caller.
#
#   tools/autotest/run_load.sh [label]    label names the screenshots (default: run)
#
# Headless: nothing shows on the desktop and the PC stays usable during a run. The game draws into gamescope's headless
# backend (1920x1080); keys go to gamescope's own Xwayland through XTEST, so they never reach the desktop and need no
# focus. Never use ydotool here: it types into whatever window the user has active.
# Needs gamescope (with gamescopectl), Python with python-xlib and Pillow, and pactl/paplay for the mute.
# Screenshots go to $DD2_AUTOTEST_DIR (default: a new temporary folder, printed at the start).
#
# The game's audio is muted while it runs. WirePlumber remembers a stream's mute by application name, so on exit the
# script plays a short silence under the game's name and unmutes it, leaving the game's sound as it was.
#
# Keys: PageUp closes the REFramework menu (it swallows input; under gamescope it opens at start only sometimes, so the
# script presses PageUp only when a screenshot shows it), F confirms. Enter does not.
# It presses "Load from Last Saved Data", the title's first entry, so the slot is the last one played: check the log.
# The game is terminated with SIGTERM: it ignores a window close while the server-error dialog is up. Saves are not
# written by this run unless the game autosaves.
set -u

GAME="${DD2_DIR:-$HOME/Documentos/Games/Dragon Dogma 2}"
LOG="$GAME/re2_framework_log.txt"
CRUCIBLE="${DD2_CRUCIBLE:-$HOME/Documentos/Games/Crucible-x86_64.AppImage}"
WORK="${DD2_AUTOTEST_DIR:-$(mktemp -d)}"
LABEL="${1:-run}"
START=$(date '+%Y-%m-%d %H:%M:%S.000')
APP_NAME="Dragon's Dogma 2" # the game's PulseAudio application.name
GS_PID=""
GAME_DISPLAY=""
GS_SOCKET=""
MUTED=""

mkdir -p "$WORK"
echo "screenshots: $WORK"

# press <evdev code> [hold seconds]: a key on the game's X display (X keycode = evdev code + 8).
press() {
    python3 -I - "$GAME_DISPLAY" "$1" "${2:-0.2}" <<'PY'
import sys, time
from Xlib import display, X
from Xlib.ext import xtest
d = display.Display(sys.argv[1])
kc = int(sys.argv[2]) + 8
xtest.fake_input(d, X.KeyPress, kc); d.sync()
time.sleep(float(sys.argv[3]))
xtest.fake_input(d, X.KeyRelease, kc); d.sync()
PY
}

# shot <name>: gamescope's own screenshot of the game. The request is asynchronous: wait for the file to appear.
shot() {
    local f="$WORK/$1.png"
    [ -n "$GS_SOCKET" ] || return 1
    rm -f "$f"
    GAMESCOPE_WAYLAND_DISPLAY="$GS_SOCKET" gamescopectl screenshot "$f" >/dev/null 2>&1
    for _ in $(seq 1 20); do
        [ -s "$f" ] && { sleep 0.5; return 0; }
        sleep 0.25
    done
    return 1
}

# True when the REFramework menu is on screen, which means the game is drawing its first screen: a run of at least 300
# grey title-bar pixels in one of the top rows. The menu's position is not fixed, so the whole width is scanned.
menu_visible() {
    python3 -I - "$WORK/wait.png" <<'PY' 2>/dev/null
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('L')
w = im.width
px = im.load()
for y in range(0, 120, 2):
    run = 0
    for x in range(w):
        if 100 <= px[x, y] <= 200:
            run += 1
            if run >= 300:
                sys.exit(0)
        else:
            run = 0
sys.exit(1)
PY
}

# True when the game draws a lit screen (the title is about 40 on 0-255; the black loading screens about 5). The top-left
# corner is left out: MangoHud draws there from the start.
screen_lit() {
    python3 -I - "$WORK/wait.png" <<'PY' 2>/dev/null
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('L')
sys.exit(0 if im.crop((400, 300, 1920, 1080)).resize((1, 1)).getpixel((0, 0)) > 20 else 1)
PY
}

# Closes the REFramework menu when it is up. It does not always open at start under gamescope, and PageUp on a closed
# menu would open it (it then swallows the game's keys), so it is only pressed after a screenshot shows the menu.
close_menu_if_up() {
    shot wait || return 0
    if menu_visible; then
        echo "REFramework menu up: PageUp"
        press 104 # PageUp
        sleep 1.5
    fi
}

# This run's lines only: the log of the previous run stays on disk until the game rewrites it.
run_lines() {
    grep -a '\[Retinue\]' "$LOG" 2>/dev/null | awk -v s="[$START" '$0 >= s'
}

# environ_of <pid> <name>: a variable from a running process's environment.
environ_of() {
    tr '\0' '\n' < "/proc/$1/environ" 2>/dev/null | sed -n "s/^$2=//p" | head -1
}

stream_id() {
    pactl list sink-inputs 2>/dev/null | awk -v n="application.name = \"$APP_NAME\"" '
        /^Sink Input #/ { id = substr($3, 2) }
        index($0, n) { print id }' | tail -1
}

# Clears WirePlumber's remembered mute: a silent stream under the game's name, unmuted while it plays.
unmute_remembered() {
    local id
    head -c 1600000 /dev/zero > "$WORK/silence.raw"
    paplay --raw --rate=44100 --channels=2 --format=s16le "--property=application.name=$APP_NAME" "$WORK/silence.raw" &
    local play=$!
    for _ in $(seq 1 10); do
        sleep 0.3
        id=$(stream_id)
        [ -n "$id" ] && { pactl set-sink-input-mute "$id" 0; break; }
    done
    wait "$play" 2>/dev/null
    rm -f "$WORK/silence.raw"
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

cleanup() {
    if [ -n "$GS_PID" ] && kill -0 "$GS_PID" 2>/dev/null; then
        kill -TERM "$GS_PID" 2>/dev/null
        for _ in $(seq 1 10); do kill -0 "$GS_PID" 2>/dev/null || break; sleep 0.5; done
    fi
    [ -n "$MUTED" ] && unmute_remembered
}
trap cleanup EXIT

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

gamescope --backend headless -W 1920 -H 1080 -w 1920 -h 1080 -- "$CRUCIBLE" --launch "Dragon's Dogma 2" \
    >"$WORK/gamescope.log" 2>&1 &
GS_PID=$!

# The game's X display is gamescope's Xwayland, read from the game itself; the screenshot socket from gamescope's child,
# which sees host paths (inside the game's container the socket has another path).
for i in $(seq 1 60); do
    sleep 2
    kill -0 "$GS_PID" 2>/dev/null || fail "GAMESCOPE GONE (see $WORK/gamescope.log)"
    if [ -z "$GS_SOCKET" ]; then
        child=$(pgrep -P "$GS_PID" | head -1)
        [ -n "$child" ] && GS_SOCKET=$(environ_of "$child" GAMESCOPE_WAYLAND_DISPLAY)
    fi
    pid=$(pgrep -x DD2.exe | head -1)
    [ -n "$pid" ] && GAME_DISPLAY=$(environ_of "$pid" DISPLAY)
    [ -n "$GAME_DISPLAY" ] && [ -n "$GS_SOCKET" ] && break
    [ "$i" = 60 ] && fail "TIMEOUT game process (display '$GAME_DISPLAY', socket '$GS_SOCKET')"
done
echo "game display $GAME_DISPLAY, gamescope socket $GS_SOCKET"

for i in $(seq 1 60); do
    sleep 4
    if [ -z "$MUTED" ]; then
        id=$(stream_id)
        [ -n "$id" ] && pactl set-sink-input-mute "$id" 1 && MUTED=yes
    fi
    shot wait
    if menu_visible || screen_lit; then
        echo "first screen after ~$((i * 4))s"
        break
    fi
    [ "$i" = 60 ] && fail "TIMEOUT first screen"
done

# Early presses land before the screen is ready, so keep pressing: one F for the notice, one for the title entry.
for i in $(seq 1 20); do
    if [ -z "$MUTED" ]; then
        id=$(stream_id)
        [ -n "$id" ] && pactl set-sink-input-mute "$id" 1 && MUTED=yes
    fi
    close_menu_if_up
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
