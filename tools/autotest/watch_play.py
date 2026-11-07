#!/usr/bin/env python3
"""Records a play session the user drives, so the steps can be automated later.

    tools/autotest/watch_play.py <output folder>

Writes <output folder>/timeline.tsv, one line per event, with these kinds:
    KEY     a key, mouse button or pad button, with how long it was held; only while the game has the focus
    SHOT    a small JPEG taken about 1 s after a press, at most one each 3 s; only while the game has the focus, and
            dropped if the focus goes within 2 s after it
    RETINUE a [Retinue] line of the game's log
    FILE    a save or mod slot file that appeared, changed or went away
    FOCUS   the game gained or lost the focus
    WATCH   the watcher's own notes

Nothing typed in another window is recorded: input is dropped unless the active window is the game. Mouse movement is
not recorded. Stops 10 s after the game exits, or on SIGTERM. Needs KDE Wayland (KWin scripting, spectacle), read access
to /dev/input (the input group), python-evdev and Pillow.

Options for testing the watcher itself: --focus <prefix> matches another window title, --virtual includes ydotool's device.
"""
import argparse, json, os, selectors, signal, subprocess, sys, threading, time
from pathlib import Path

import evdev
from evdev import ecodes
from PIL import Image

GAME = Path(os.environ.get("DD2_DIR", Path.home() / "Documentos/Games/Dragon Dogma 2"))
LOG = GAME / "re2_framework_log.txt"
SLOTS = GAME / "reframework/data/Retinue/slots"
REPO = Path(__file__).resolve().parents[2]

ap = argparse.ArgumentParser()
ap.add_argument("out", type=Path)
ap.add_argument("--focus", default="Dragon's Dogma 2")
ap.add_argument("--virtual", action="store_true")
args = ap.parse_args()
args.out.mkdir(parents=True, exist_ok=True)
SAVES = Path(subprocess.check_output([REPO / "tools/saves.sh", "where"], text=True).strip())

lock = threading.Lock()
timeline = open(args.out / "timeline.tsv", "a", buffering=1)
state = {"focused": False, "stop": False, "shot_at": None, "last_shot": 0.0, "shots": 0, "lost_at": 0.0}


def emit(kind, text):
    with lock:
        timeline.write(f"{time.strftime('%H:%M:%S')}.{int(time.time() * 1000) % 1000:03d}\t{kind}\t{text}\n")


def follow_focus():
    """KWin reports each window change to the journal; anything unexpected leaves focused False, so nothing is recorded."""
    script = args.out / "focus-report.js"
    script.write_text(
        'function r(w){print("ACTIVEWIN:"+(w?w.caption:"none"));}\n'
        "workspace.windowActivated.connect(r);r(workspace.activeWindow);\n"
    )
    journal = subprocess.Popen(["journalctl", "--user", "-f", "-n0", "-o", "cat"], stdout=subprocess.PIPE, text=True)
    time.sleep(0.5)
    kwin = ["qdbus6", "org.kde.KWin"]
    name = f"watchplay{os.getpid()}"
    number = subprocess.check_output(kwin + ["/Scripting", "org.kde.kwin.Scripting.loadScript", str(script), name],
                                     text=True).strip()
    subprocess.run(kwin + [f"/Scripting/Script{number}", "org.kde.kwin.Script.run"], stdout=subprocess.DEVNULL)
    state["unload"] = lambda: (
        subprocess.run(kwin + [f"/Scripting/Script{number}", "org.kde.kwin.Script.stop"], stdout=subprocess.DEVNULL),
        journal.terminate(),
    )
    for line in journal.stdout:
        if "ACTIVEWIN:" not in line:
            continue
        focused = line.split("ACTIVEWIN:", 1)[1].strip().startswith(args.focus)
        if focused != state["focused"]:
            state["focused"] = focused
            if not focused:
                state["lost_at"] = time.time()
            emit("FOCUS", "gained" if focused else "lost")


def follow_log():
    position = LOG.stat().st_size if LOG.exists() else 0  # the game starts a new log at launch
    while not state["stop"]:
        try:
            size = LOG.stat().st_size
            if size < position:
                position = 0
            if size > position:
                with open(LOG, "rb") as f:
                    f.seek(position)
                    data = f.read()
                end = data.rfind(b"\n") + 1
                position += end
                for line in data[:end].decode("utf-8", "replace").splitlines():
                    if "[Retinue]" in line:
                        emit("RETINUE", line.split("[Retinue]", 1)[1].strip())
        except OSError:
            pass
        time.sleep(0.5)


def snapshot():
    seen = {}
    for root in (SAVES, SLOTS):
        for path in root.rglob("*"):
            try:
                if path.is_file():
                    info = path.stat()
                    seen[str(path.relative_to(root.parent))] = (info.st_size, info.st_mtime_ns)
            except OSError:
                pass
    return seen


def follow_files():
    before = snapshot()
    while not state["stop"]:
        time.sleep(1)
        after = snapshot()
        for path in sorted(set(before) | set(after)):
            if before.get(path) != after.get(path):
                word = "new" if path not in before else "gone" if path not in after else "changed"
                size = after[path][0] if path in after else 0
                emit("FILE", f"{word} {path} {size} bytes")
        before = after


def follow_game():
    seen, gone_since = False, None
    while not state["stop"]:
        running = subprocess.run(["pgrep", "-x", "DD2.exe"], stdout=subprocess.DEVNULL).returncode == 0
        if running and not seen:
            seen = True
            emit("WATCH", "the game is running")
        gone_since = None if running else (gone_since or time.time())
        if seen and gone_since and time.time() - gone_since > 10:
            emit("WATCH", "the game exited")
            state["stop"] = True
        time.sleep(1)


def take_shots():
    folder = args.out / "shots"
    folder.mkdir(exist_ok=True)
    while not state["stop"]:
        time.sleep(0.1)
        due, now = state["shot_at"], time.time()
        if not (due and now >= due and now - state["last_shot"] >= 3 and state["focused"]):
            continue
        state["shot_at"], state["last_shot"] = None, now
        state["shots"] += 1
        name = folder / f"{state['shots']:04d}-{time.strftime('%H%M%S')}"
        raw = name.with_suffix(".png")
        subprocess.run(["spectacle", "-b", "-n", "-f", "-o", str(raw)], stderr=subprocess.DEVNULL)
        # The focus report lags the screen (an Alt+Tab switcher or the desktop can already show), so a shot close to a
        # loss of focus is dropped unseen.
        time.sleep(2)
        if state["lost_at"] >= now - 1:
            raw.unlink(missing_ok=True)
            continue
        try:
            Image.open(raw).convert("RGB").resize((960, 540)).save(name.with_suffix(".jpg"), quality=60)
            raw.unlink()
            emit("SHOT", name.with_suffix(".jpg").name)
        except OSError as problem:
            emit("WATCH", f"shot failed: {problem}")


def label(code, kind):
    names = ecodes.bytype[kind].get(code, code) if kind in ecodes.bytype else code
    return names[0] if isinstance(names, (list, tuple)) else names


def watch_input():
    selector, known, held, hats = selectors.DefaultSelector(), set(), {}, {}
    last_scan = 0.0
    while not state["stop"]:
        if time.time() - last_scan > 5:  # a pad may be plugged in later
            last_scan = time.time()
            for path in evdev.list_devices():
                if path in known:
                    continue
                try:
                    device = evdev.InputDevice(path)
                except OSError:
                    continue
                virtual = device.name.startswith("ydotoold")
                if ecodes.EV_KEY in device.capabilities() and (args.virtual or not virtual):
                    known.add(path)
                    selector.register(device, selectors.EVENT_READ)
                    emit("WATCH", f"reading {device.name}")
        for key, _ in selector.select(timeout=0.5):
            try:
                events = list(key.fileobj.read())
            except OSError:
                known.discard(key.fileobj.path)
                selector.unregister(key.fileobj)
                continue
            for event in events:
                name, down = None, False
                if event.type == ecodes.EV_KEY and event.value in (0, 1):
                    name, down = label(event.code, ecodes.EV_KEY), event.value == 1
                elif event.type == ecodes.EV_ABS and event.code in (ecodes.ABS_HAT0X, ecodes.ABS_HAT0Y):
                    hat = (key.fileobj.path, event.code)  # a release reads 0, so keep the direction it released
                    if event.value != 0:
                        hats[hat] = f"{label(event.code, ecodes.EV_ABS)}:{event.value}"
                    name, down = hats.get(hat), event.value != 0
                elif event.type == ecodes.EV_REL and event.code == ecodes.REL_WHEEL and state["focused"]:
                    emit("KEY", f"WHEEL {event.value:+d}")
                if name is None or not state["focused"]:
                    held.pop((key.fileobj.path, name), None)
                    continue
                slot = (key.fileobj.path, name)
                if down:
                    held[slot] = time.time()
                    state["shot_at"] = state["shot_at"] or time.time() + 1
                else:
                    started = held.pop(slot, None)
                    length = f"{time.time() - started:.2f}s" if started else "?"
                    emit("KEY", f"{name} {length} [{key.fileobj.name.strip()}]")


def finish(*_):
    state["stop"] = True


signal.signal(signal.SIGTERM, finish)
signal.signal(signal.SIGINT, finish)
for work in (follow_focus, follow_log, follow_files, follow_game, take_shots):
    threading.Thread(target=work, daemon=True).start()
emit("WATCH", "started")
watch_input()
if "unload" in state:
    state["unload"]()
emit("WATCH", "stopped")
