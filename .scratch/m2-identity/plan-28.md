# Plan: ticket 28, a restart over a cleared slot keeps the roster

Decision (user, 2026-11-09): "Start from Beginning" on a cleared save slot is the same playthrough, like Vernworth NG+.
Both send `RedoNewGame` for a restart; only the clear state tells them apart. Cross-review: skipped (unavailable, see memory).

Spike (peer, 2026-11-09, logs in ticket 28): at `requestStartType` / `requestLoadGameData`, pre and post, all of
`app.GuiManager._IsGameClearData`, `_IsRestartData`, `IsGameClearData()`, `isGameClearOrRestartData()` are false. On the first
frame after the start (~0.7 s): cleared slot Beginning `G=true R=true`; uncleared restart `G=false R=true`; Vernworth
(`RedoNewGameSkip`) `G=true R=true`. At the title all false again.

## Slice 1: decide a RedoNewGame from the game's clear flag — implementer (Sonnet) — [ ]

**Goal**: a `RedoNewGame` restart over a cleared slot ("Start from Beginning") keeps the slot's roster, like NG+; a restart over
an uncleared slot still archives. If the flag cannot be read, it archives (as today; the archive is never deleted).

**Context**: read `src/autorun/Retinue/slot.lua` (Session), `src/autorun/Retinue/game/slot_hooks.lua` (tracker, `call_on`,
`report`, log lines), `src/autorun/Retinue.lua` (`re.on_pre_application_entry("UpdateBehavior")` and `re.on_frame`;
`archive_store.run` runs in on_frame before `retinue.update`), `src/autorun/Retinue/game/archive_store.lua`,
`tests/slot_test.lua` (style: plain asserts in `do` blocks). Spec section: `.scratch/m2-identity/spec.md` § Save slot (lines ~71-80).
Hooks run on the game thread; `re.on_frame` may run on the render thread; the `UpdateBehavior` callback runs on the game thread.
So the decision runs in `UpdateBehavior` (no race with the start/load hooks), and only sets `archive_pending`, which
`archive_store.run` already takes in on_frame.

**Design**:
- `slot.lua`:
  - New constant `M.RESTART_WAIT = 10` (seconds of `os.clock()`).
  - Session gains `restart_pending` (boolean, false in `new_session`) and `restart_since` (number|nil).
  - `on_start_request`: for `"RedoNewGame"` set `restart_pending = true`, `restart_since = nil`, and `archive_pending = false`
    (no longer true). Every other start sets `restart_pending = false`. Keep the existing assignment order rule: the unit
    first, the flags last (`restart_pending` before `archive_pending`, both after unit/source). Update the order test.
  - `roster_unit()`: nil while `first_save_pending` or `restart_pending`; else `unit`.
  - New `Session:decide_restart(clear, restart_data, now) -> nil | "kept" | "archived" | "timeout"`:
    - not `restart_pending` → nil.
    - `unit == nil` (its load request not seen yet) → nil, nothing changes.
    - first call with a unit: `restart_since = now` if nil.
    - `restart_data == true and clear == true` → `restart_pending = false`; return `"kept"` (the roster stays: NG+).
    - `restart_data == true and clear == false` → `archive_pending = true`, then `restart_pending = false`; return `"archived"`.
    - `restart_data == true` and `clear` is not a boolean → treat as archived (fail closed), return `"archived"`.
    - otherwise (`restart_data` not true, includes nil = unreadable) → if `now - restart_since >= M.RESTART_WAIT`:
      `archive_pending = true`, `restart_pending = false`, return `"timeout"`; else nil (wait).
    - Order: set `archive_pending` before clearing `restart_pending`, so `roster_unit()` never shows the old roster active
      before the archive is flagged.
  - `classify` is unchanged (`RedoNewGame` is still `NEW_PLAYTHROUGH` by name; the session decides). Update the
    comments (Session field list, on_start_request) to say so.
- `slot_hooks.lua`: add `tracker.decide_restart(now)`, called every game update. When `session.restart_pending` is false it
  returns at once (no game read). Otherwise read `sdk.get_managed_singleton("app.GuiManager")`; nil singleton → pass
  `nil, nil` (wait). Read the fields `_IsGameClearData` and `_IsRestartData` with `get_field` under pcall; an error → `nil`
  for that value and `report("slot", err)` once per restart (not per frame). Call `session:decide_restart(clear, rd, now)` and
  log one line by result:
  - `"kept"`: `[Retinue] slot: <label> restart over a cleared slot; the roster stays (NG+)`
  - `"archived"`: `[Retinue] slot: <label> restart over a slot not cleared; the roster is archived` (when clear was not a
    boolean, say `clear flag unreadable; the roster is archived` instead)
  - `"timeout"`: `[Retinue] slot: <label> restart: no clear flag after 10 s; the roster is archived`
  (`<label>` = `slot.label(session.unit)`; log.error like the other slot lines.) Update the module header comment.
- `Retinue.lua`: call `tracker.decide_restart(os.clock())` under pcall (report "slot") in the `UpdateBehavior` callback.
  Update the header paragraph about restarts: a restart over a cleared slot ("Start from Beginning") keeps the roster like NG+,
  decided from `GuiManager._IsGameClearData` a frame or so after the start; until then no roster is active; unreadable or
  no flag within 10 s archives.
- Check that `retinue.update` reactivates the roster when `tracker.unit()` goes from nil to the unit in the "kept" case
  (read `retinue.update`/the roster store). If it would not reload, fix it there in the smallest way and say so.
- Docs: `.scratch/m2-identity/spec.md` § Save slot: `RedoNewGame` bullet says cleared → kept (NG+), otherwise archive at once
  after the flag; `CONTEXT.md` Save slot entry: NG+ (from Vernworth or from the beginning) over a cleared save slot continues the
  same playthrough; `CHANGELOG.md` unreleased entry (follow its style); README only if it describes restarts (grep).

**Acceptance criteria**:
- [ ] Unit tests in `tests/slot_test.lua`: kept (no archive, roster_unit becomes the unit), archived (take_archive gives the
  unit once), clear unreadable with restart_data true → archived, wait before the load (unit nil) → nil and no timer,
  timeout after RESTART_WAIT → archived and before it → nil, a later start cancels the wait (no archive), roster_unit nil
  during the wait, decide_restart a no-op when nothing pending. Existing RedoNewGame tests updated to go through
  decide_restart.
- [ ] Assignment-order test covers restart_pending.
- [ ] `tests/run.sh` all PASS.
- [ ] No other behaviour changes (NewGame first-save path, NG+ path untouched).

**Verify**: `tests/run.sh`; `luac5.4 -p` (or `luac -p`) on every changed .lua file if available.

**Out of scope**: persisting the clear flag across sessions (makeLoopSaveData); any in-game run (the orchestrator sends it to the
peer); deploy.sh; experiments.
