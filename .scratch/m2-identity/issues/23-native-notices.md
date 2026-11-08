# 23: Native notices

Parent: [M2 spec](../spec.md) (§ Status (native): Notices)

**What to build:** the mod tells the player about Returns and roster problems with the game's own centred notice: "<name> returned —
Lv N restored" (or kept, on a guard skip), and once per load when the roster is locked, read-only or the slot unknown.
Every player-facing string lives in one place.

**Blocked by:** [19: Dismiss and Return restore an adopted pawn's progress](19-dismiss-return-restore.md)

**Status:** resolved

- [x] `requestNoButtonDialog` notice, closed by the mod after 3 s with `requestHideDialog()`, only if it is still the mod's notice on screen.
- [x] A notice is deferred while a game dialog or menu is up.
- [x] Pure `labels` module with tests for every string (Return, guard skip, locked / read-only / no slot reasons).
- [x] Fails closed: missing methods → log only.
- [x] Verified in game: Return notice shows and closes; a locked roster gives one notice on load.

## Comments

- 2026-11-07, `0b9de66`, partial in-game run; the user stopped it for time, the last box stays open.
  - Passed: Return on load (the notice waited for the server dialog, then showed about 2 s after it closed); Return in the Rift, twice (waited for the
    talk's last line, drew inside the Rift about 2 s after it, closed at about 3 s); the `Hail` prompt sits above the panel without covering the text;
    a short F with the notice up opened no talk.
  - Not run: F held across the close; guard skip; locked (one notice on load); read-only; a notice held by the pause menu (check 33); New Game with no
    "slot unknown"; a notice waiting for a talk opened after it was queued. Deferral by the pause menu is covered only by tests so far.
  - Rerun: locked and read-only need only a file edit and a load, so start there. Dismiss from the talk: F on Dismiss, right click on the gift screen, Yes,
    F on the rating, F on the last line. Then re-hire through a new summon: it appears behind the stone. Leaving the Rift autosaves (global 5), which is how a
    dismissal reaches the save for the guard skip. Each Rift cycle takes several minutes.
- 2026-11-07, `0b9de66`, rerun test 1 (locked): FAILED. First load: one notice, closed by itself, no level-up, files unchanged.
  Return to Title Without Saving, then Load from Last Saved Data: the server-error dialog came up, and after the user
  closed it the game stopped responding (closed with SIGTERM); our notice was never seen. The log has no show/hide lines.
  A second notice on that reload is by design (once per load); the rerun guide wrongly said it would not repeat.
  Leading guess: an invisible notice of ours, left up (modal, blocks input) because the deadline read it as not ours.
  Next build logs every dialog-state change while a notice waits or shows, and each show/hide/gone, and adds a
  "Close notice (game stuck)" button to the REFramework menu.
- 2026-11-07, `83b4485`, test 1 rerun (locked, two loads in one session): passed, no freeze. On each load the notice waited
  for the server-error dialog (seen only through `netErr`; `dialogGui` and `D.disp` stay false while it is up), showed
  about 1 s after it closed, and was hidden at 3 s while still ours. Files unchanged. The first freeze did not reproduce;
  that run also had a fight, an exp grant and a system-menu save before the title. Logging stays on for tests 2-8.
- 2026-11-07, `83b4485`, rest of the run: 1-6 and 8 pass, 7 skipped. Ticket closed.
  - Locked: after the fix and Reset scripts, "roster ok (1/2)", no notice.
  - Read-only (`"version": 2`): one notice per load, after the server error closed; Folken levelled; `slots/2` unchanged.
  - Reset scripts with the notice up: the old instance closed it (the new one first read `D.disp=false`), and the game was not
    stuck. The new instance counts as a new load and shows the notice once more. Accepted: Reset scripts is a developer action.
  - New Game: "the roster waits for the new game's first save", no notice; no `slots/3` created.
  - Guard skip: `skipped: guard (game Lv 23, backup Lv 22)`, notice "Folken returned — kept Lv 23, newer than the backup", hidden
    at 3 s; the backup is then Lv 23.
  - F held through the close: nothing opened, no turn, input normal.
  - Pause menu (check 33): open about 22 s, the notice showed 1 s after it closed. A game Yes/No (`dialogGui=true`, `D.noButton=false`)
    stayed open about 20 s and was left alone; the notice came 1 s after it closed.
  - Talk opened after queueing: skipped (no time to open a talk within the 1 s settle). The talk wait is still covered by the
    Rift run on `0b9de66` (the notice waited for the talk's last line). It also re-ran Return on load: restored Lv 23→28, and
    the notice waited for two pause-menu openings.
  - Open: the freeze on `0b9de66` (reload in the same session after a fight, an exp grant and a save) did not reproduce. The
    state logging and the "Close notice (game stuck)" button stay in for now; decide in ticket 27 whether to keep them.
