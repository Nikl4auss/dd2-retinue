# 23: Native notices

Parent: [M2 spec](../spec.md) (§ Status (native): Notices)

**What to build:** the mod tells the player about Returns and roster problems with the game's own centred notice: "<name> returned —
Lv N restored" (or kept, on a guard skip), and once per load when the roster is locked, read-only or the slot unknown.
Every player-facing string lives in one place.

**Blocked by:** [19: Dismiss and Return restore an adopted pawn's progress](19-dismiss-return-restore.md)

**Status:** ready-for-agent

- [x] `requestNoButtonDialog` notice, closed by the mod after 3 s with `requestHideDialog()`, only if it is still the mod's notice on screen.
- [x] A notice is deferred while a game dialog or menu is up.
- [x] Pure `labels` module with tests for every string (Return, guard skip, locked / read-only / no slot reasons).
- [x] Fails closed: missing methods → log only.
- [ ] Verified in game: Return notice shows and closes; a locked roster gives one notice on load.

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
