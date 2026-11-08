# M2 plan: ticket 23 (Native notices)

Source: [issues/23-native-notices.md](issues/23-native-notices.md), [spec.md](spec.md) § Status (native). Base commit: `41fa057`.
(Plans of earlier tickets are in git history.)

- [x] Slice 1: spike in game, read-only: which game state means "a dialog or menu is up", and how to tell the notice is ours. Tier: **Opus, inline** (the outcome is unknown, and Slice 2's design rests on it).
- [x] Slice 2: pure `labels.lua` and `notices.lua`, glue `game/notice_screen.lua`, wiring, tests, docs. Tier: **Sonnet** (`implementer`).
- [x] Slice 3: in-game verification with the mod (ticket's last box). Tier: **Opus, inline**, keys; the user only if a step cannot be driven.

Cross-review: skipped (Sol and Astra unavailable on this account); Opus `reviewer` only.

## Slice 1: Spike (done)

Two runs, 2026-11-07, driven by keys from another session. Results in findings 0009 § P6. The panel is modal, so the user chose
(2026-11-07): native with guards, 3 s instead of ~4.

## Slice 2: Notices

**Goal**: the player sees "<name> returned — Lv N restored" (or kept, on a guard skip) in the game's centred panel for 3 s, and one
notice per load when the roster is locked, read-only or the slot unknown. Without the needed game methods: log only.

**Context**: read `lifecycle.lua`, `departure.lua`, `reconcile.lua` (`new_gate`), `roster.lua`, `slot.lua`, `game/roster_store.lua`,
`game/slot_hooks.lua`, `Retinue.lua`, `tests/lifecycle_test.lua`, findings 0009 P1 and P6 (read P6 first: it is why the guards exist). The game calls run on the game thread
(`UpdateBehavior`), like the restore writes.

**Design**

New pure `Retinue/labels.lua`, the home of the player-facing strings (tickets 24 and 26 add theirs):

```lua
labels.returned(name, level)      -- "<name> returned — Lv N restored"
labels.kept(name, level)          -- "<name> returned — kept Lv M, newer than the backup"
labels.roster_problem(r, unit)    -- text | nil. unit is the session's unit (not the roster unit)
--   r nil, unit nil  -> "Retinue is off: the save slot is unknown"
--   r nil, unit set  -> nil  (a new game waits for its first save: no roster, and nothing is wrong)
--   LOCKED           -> "The Retinue roster is locked: <r.reason>\nSee the Retinue menu."
--   READ_ONLY        -> "The Retinue roster is read-only: written by a newer Retinue (<r.reason>)"
--   OK               -> nil
```

Levels print like `departure.lua`'s `num` (integral floats without `.0`).

New pure `Retinue/notices.lua`:

```lua
notices.HOLD_SECONDS = 3
notices.SETTLE_SECONDS = 1
notices.new(hold_seconds, settle_seconds) -> queue
queue:push(text)
queue:sync(generation)    -- a new generation drops what waits; a notice on screen stays and still gets closed
queue:step(now, can_show, is_mine) -> nil | "show", text | "hide", text
--   one notice at a time, oldest first.
--   can_show false restarts the settle. Nothing showing, something waiting, can_show true for settle seconds without a break
--     -> "show", text; deadline = now + hold.  (The settle bridges the gap between two cutscenes, about 0.5 s, and fades.)
--   showing, before the deadline -> nil.
--   showing, deadline reached -> is_mine(text): true -> "hide", text; false -> nil, showing ends; nil (unreadable) -> keeps showing, asked again next step.
--   a failed hide -> queue:reopen(text, now). notices.drive(queue, screen, now, in_world) is the tick.
notices.new_once() -> once;  once:due(generation, ready) -> true on the first ready call of each generation
```

`can_show` is false out of the world or while the screen is busy; closing does not depend on it. It is computed in the same
`UpdateBehavior` callback that shows, and `is_mine` in the one that hides: a show or a hide over a game dialog softlocks the game.

New glue `game/notice_screen.lua`:

- `new(report)` resolves everything at load, and every name must exist: on `app.GuiManager` the methods
  `requestNoButtonDialog(System.String, System.UInt32)`, `requestHideDialog()`, `IsDispDialogGui()`, `IsOpenMainFlowUI()`, `isDispMovieScreen()`
  and the fields `Dialog`, `NetworkErrorDialog`; on `app.ui010101` `get_IsDisp()` and the fields `IsNoButton`, `MainText`; on `app.TalkEventManager`
  the field `_IsTalkingAny`; on `app.DemoMediator` `get_IsPlayingDemo()`. Anything missing: `available = false`, one report line naming it, the game
  is never called, and each text goes to the log as `[Retinue] notice (not shown): <text>`.
- `busy()` -> true when any of these is true: `IsDispDialogGui`, `IsOpenMainFlowUI`, `isDispMovieScreen`, `NetworkErrorDialog.get_IsDisp`,
  `_IsTalkingAny`, `get_IsPlayingDemo`. A nil singleton or widget, or a throw, counts as busy. **Not** `PauseManager.isPausedAny`: it stays true for a
  whole Rift visit, where a Return happens. Not `TalkSelect.IsDisp`: it sticks.
- `is_mine(text)` -> `Dialog.get_IsDisp() == true and Dialog.IsNoButton == true and Dialog.MainText == text`, read in that call. `MainText` may
  arrive as a Lua string or a managed string: compare through a helper taking both (`:call("ToString")` for userdata). All three matter:
  `MainText` and `IsNoButton` keep their values after a hide, and a dialog that replaces ours leaves `IsDisp` true. Three values: true, false (proven not ours), nil (a read failed, reported). A notice is never given up on an unreadable read, and a hide needs true. A script reset closes a notice that is still ours.
- `show(text)`, `hide()`: under pcall; a throw is reported and sets `available = false`. Called only with the game thread's `UpdateBehavior`.

`lifecycle.lua`: new dep `notify(text)`. In `attempt`: after the `SKIP_GUARD` log line `notify(labels.kept(m.name, game_level))`, after the
restore's `log_line` `notify(labels.returned(m.name, b.level))`. Nothing on no backup, time-out or mismatch (spec lists two texts).

`Retinue.lua`, in the `UpdateBehavior` callback after `flow.tick`, one pcall, reported as "notices":

```lua
queue:sync(retinue.generation)
if once:due(retinue.generation, state.in_world and flow.settled()) then
    local text = labels.roster_problem(retinue.roster, tracker.session.unit)
    if text then queue:push(text) end
end
-- available: local can_show = state.in_world and not screen.busy(); step with screen.is_mine; "show" -> screen.show, "hide" -> screen.hide
-- not available: pop each text to the log
```

Update the header comment of `Retinue.lua`. `tests/run.sh` picks up the new files.

**Acceptance criteria**

- [ ] `tests/labels_test.lua`: every string exactly, integral floats, a roster problem for each mode, nil during a new game's wait.
- [ ] `tests/notices_test.lua`: order, one at a time, deferred while `can_show` is false, the settle (a 0.5 s gap in `busy` does not show; a break restarts it), hide only when mine, a closed-by-the-game notice
      makes room for the next, `sync` drops the queue and keeps the deadline, `due` once per generation and only when ready.
- [ ] `tests/lifecycle_test.lua`: a restore notifies with the backup's level, a guard skip with the game's, no backup, time-out and mismatch
      do not notify.
- [ ] A missing method never calls the game: the text reaches the log.

**Verify**: `tests/run.sh`; `luac5.4 -p` on the changed files.

**Out of scope**: Adopt/Release refusals and every other string of ticket 24; moving `roster.ERRORS`; the mod menu.

## Slice 3: In game

Backup first. Keys, with screenshots: a Return in the Rift (dismiss, re-hire): the notice shows after the talk, inside the Rift, and closes (never
tried in the Rift: if it does not draw, stop and decide); a guard skip; a roster with `not json`: one notice on load; read-only; a notice held while the
pause menu is open (check 33); a new game's prologue gives no "slot unknown". Tick the ticket's boxes, record the runs in the ticket's comments, close it.

Also check, on that Return: the interaction prompt (`Hail (Hold to Talk)`, `Examine (Hold)`) stays visible and can overlap the panel (seen in the spikes; the player stands next to the hired pawn, so it is likely here). Does it hurt the reading, and does F act on it while the notice is up? Cosmetic only: stop and decide only if F starts a talk under the notice.

Same Return: press F, and in another pass hold it across the close, with `Hail` available. Does it fire when the notice closes? The user saw the answering press of a Yes/No dialog reach the game on close (spike G1, G3; known input leak, findings 0007, ticket 24's fallback). The notice has no buttons, so this case is untested, not assumed.
