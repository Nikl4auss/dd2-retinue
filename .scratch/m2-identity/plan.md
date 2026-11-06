# M2 plan: ticket 19 (Dismiss and Return restore an adopted pawn's progress)

Source: [issues/19-dismiss-return-restore.md](issues/19-dismiss-return-restore.md), [spec.md](spec.md) § Departure and
Return, § Backups, § Code layout. Base commit: `ef43795`. (Plans of earlier tickets are in git history.)

Two slices, sequential (slice 2 uses slice 1's modules).

- [x] Slice 1: Pure decisions: roster transitions, `departure`, read-back compare, the `lifecycle` driver, with tests. Tier: **Sonnet** (`implementer`).
- [x] Slice 2: Game glue: the four hooks, the restore writes, backup and roster store changes, wiring, menu, docs. Tier: **Sonnet** (`implementer`).

Cross-review: skipped (Sol and Astra unavailable on this account); Opus `reviewer` only.

Facts the design rests on (checked in the findings, the run files and the dump):

- `dismissPawn(CharacterID)` calls `dismissPawn(Pawn)`: nested, one dismiss fires both (run `2026-11-03-m2-lifecycle/b`). The `Character`
  overload never fired in a run but exists; hook all three. All the work is synchronous inside: `unregistPawn` is done when the
  inner call returns, and the `pre` of the outermost call still reads the full state (findings 0006).
- `hirePawn(app.Character, System.Boolean) : bool` never fires on a load: no call in the runs that only loaded a save; it also fires for the main pawn after a loss (no Offline ID, so no member)
  (`2026-11-04-m2-restore/c`). It returned true in the one recorded Return. The OfflineID is readable in its post (findings 0008).
- The restore worked one frame after `hirePawn` post, in the `UpdateBehavior` callback; nothing overwrote it at +1 s or +10 s
  (0008). `setExtraStatusBoost` is proven only with value 0: keep the experiment's `set_field` fallback for it and for discipline.
  `arr:call("SetValue", ...)` silently does nothing; index assignment `arr[i] = v`, 0-based, works.
- `re.on_frame` may run on the render thread, and hooks and `UpdateBehavior` on the game thread. So game **writes** go in `UpdateBehavior`,
  as the experiment did. Between a `pre` and its `post`, `on_frame` can run: a queue fed by `pre` could see the pawn still in the party. Feed it from `post`.
- `FlowPhase` stayed `InGame` through 22 minutes of play (ticket 18); not observed during a Rift hire, so the restore budget
  starts on the first tick in the world (then runs on the clock; a load resets it), and a stuck Return shows in the log rather than failing silently.

Decided here (the spec leaves them open):

- **No file I/O inside a hook** (the spec's rule for new-game archiving). `dismissPawn` pre reads the snapshot; the update loop writes it.
- **A Return with no usable backup** (missing, damaged, newer version) becomes present with a warning, `skipped: no backup`: the
  game wins and the pawn progresses again. The poll then rewrites the file, as ticket 18 decided for any present member.
  A damaged file is therefore not kept for repair by hand.
- **A failed restore does not retry within the session** after a read-back mismatch: it stays `returning` with a warning until the next
  load. A thrown write counts as "not ready" and retries until the budget ends. A `CulmativeExp` length different from the backup's is a
  mismatch, found before anything is written.
- **A member dismissed while `returning`** becomes away, its backup untouched.
- **Retry on the next load** needs no extra code: a `returning` member in the party is picked up after any roster reload. Ticket 21 adds "returning / absent → away".
- A `dismissPawn` on an **ambiguous** pawn, or a hire of one, does nothing (excluded). Ticket 20's diff catches what a missing hook misses.
- Read-only: the transitions happen in memory, `save` already writes nothing, no restore runs. A Return there stays `returning` for the session.

A hire of a member still `present` proves it left unseen (a pawn in the party cannot be hired): it goes away (cause `hire`) then `returning`, so its backup is never lowered, ticket 20 or not.

---

## Slice 1: Pure decisions

**Goal**: everything Departure and Return decide exists as pure, tested code: which transitions are legal, what a restore attempt does
next, the retry budget, whether a read-back matches, the log lines, and the driver that applies hook events and runs restore attempts.
No game code changes.

**Context** (read first): spec § Departure and Return; `src/autorun/Retinue/roster.lua`, `backup.lua`, `tests/roster_test.lua`,
`tests/backup_test.lua` (style: plain `assert`s in `do ... end`, Lua 5.4, `tests/run.sh`). Pure means no REFramework globals (`log`, `sdk`, `re`).

**Design**:

1. `roster.lua`, after `release`. All three: LOCKED → `nil, "locked"`; not a member → `nil, "not_adopted"`. They work in memory for READ_ONLY.
   They never touch files.
   ```lua
   -- mark_away(r, id) -> member, previous_status | nil, err. PRESENT or RETURNING -> AWAY; AWAY -> nil, "already_away". character_id is kept.
   -- mark_returning(r, id) -> member | nil, err. AWAY -> RETURNING; else nil, "not_away". character_id is kept.
   -- mark_present(r, id, character_id) -> member | nil, err. RETURNING -> PRESENT; else nil, "not_returning".
   --    character_id goes through valid_character_id; nil or invalid leaves the old value.
   ```
   `member_text`: `info` gains optional `restore_note` (string), appended after the ambiguous / not-in-party note and before the backup
   note as `", restore <note>"`.

2. `backup.lua`:
   ```lua
   -- restored_mismatch(b, back) -> nil | field. Compares level, exp, each increase_params key, extra_status_boost, discipline and
   -- culmative_exp (length and elements), numbers by ==. field: "level", "increase_params.attack", "culmative_exp[3]", "culmative_exp length"...
   -- recorded_mismatch(b, fresh) -> { key, ... } the keys among current_job, qualified_job_bits, changed_job_bits, skills that are non-nil on
   -- both sides and not M.same, in that order; empty when none. item_ids are not compared (regenerated on every hire).
   ```

3. New `src/autorun/Retinue/departure.lua` (spec § Code layout; ticket 20 adds the miss counter here):
   ```lua
   M.RETRY_SECONDS = 10
   M.WAIT, M.RESTORE, M.SKIP_GUARD, M.SKIP_NO_BACKUP, M.TIMEOUT = "wait", "restore", "skip_guard", "skip_no_backup", "timeout"

   -- step{ in_party = boolean, game_level = number|nil, backup = table|nil, expired = boolean } -> action
   --   not in_party, or game_level nil or < 1 -> TIMEOUT when expired, else WAIT
   --   backup nil -> SKIP_NO_BACKUP
   --   backup.guard(game_level, backup.level) == HIGHER -> SKIP_GUARD; else RESTORE
   -- (expired only ends the wait: a pawn that is ready on the last frame still restores.)

   -- new_budget(seconds) -> budget; one entry per member, all of them dropped when the generation changes:
   --   budget:sync(generation)
   --   budget:expired(id, now) -> boolean   the first call for an id starts its deadline; true once now >= deadline
   --   budget:close(id, note)               no more attempts this generation; note says why
   --   budget:closed(id) -> boolean
   --   budget:forget(id)                    drops the entry
   --   budget:note(id) -> nil | "pending" | the close note   nil: never started

   -- Log texts, without the [Retinue] prefix:
   --   away_text(name, from, cause)          "<name>: <from>→away (<cause>)"
   --   returning_text(name, level)           "<name>: away→returning (backup Lv <n>)"; "(no backup)" when level is nil
   --   restored_text(name, a, b)             "<name>: returning→present restored Lv <a>→<b>"
   --   guard_text(name, game, backup)        "<name>: returning→present skipped: guard (game Lv <g>, backup Lv <b>)"
   --   no_backup_text(name, problem)         "<name>: returning→present skipped: no backup (<problem>)"
   --   timeout_text(name)                    "<name>: restore timed out, stays returning"
   --   mismatch_text(name, field)            "<name>: restore read-back differs at <field>, stays returning"
   --   recorded_text(name, keys)             "<name>: restored, differs from its backup in <k1, k2>"
   --   still_here_text(name, status)         "<name>: dismissed but still in the party, stays <status>"
   ```
   Integral floats print without `.0` (`slot.to_int`, like `lowered_text`). `→` is UTF-8 in the source: `docs/testing.md` reads these lines.

4. New `src/autorun/Retinue/lifecycle.lua`: pure, everything injected, so `tests/lifecycle_test.lua` drives it with fakes.
   ```lua
   -- M.new{ retinue, backups, pawns, party, drain, log_line, report } -> flow
   --   retinue:   .unit .generation .roster .found .ambiguous, retinue:mark_away(id) -> member, from | nil, err
   --              retinue:mark_returning(id) -> member | nil, err; retinue:mark_present(id, character_id) -> member | nil, err
   --   backups:   .store(unit, m, snapshot), .get(id) -> backup | nil, .note(id) -> problem | nil
   --   pawns:     .restore(view, b) -> "done" | "wait", why | "mismatch", field;  .read(view) -> snapshot | nil, why
   --   party:     .failed, .has_main_pawn(), .level(view) -> number | nil
   --   drain():   returns and empties the hook queue (array of events, oldest first):
   --              { kind = "dismiss", id = <canonical>, generation = n, snapshot = table|nil }
   --              { kind = "hire",    id = <canonical>, generation = n }
   --   log_line(text): the [Retinue] prefix is the caller's.
   --
   -- flow.update()  -- on_frame, after retinue.update, before the backup poll. Calls drain() each time and keeps what it got in its own FIFO; a new
   --                   generation drops queued events of the old one. Processes the FIFO in order, only when party.failed is false and
   --                   party.has_main_pawn() is true (else they wait: an empty party must not read as "the pawn left").
   -- flow.tick(now, in_world)  -- UpdateBehavior, game thread: runs the restore attempts.
   -- flow.note(id)  -- budget:note(id): the menu's restore note.
   ```
   Event rules (event dropped when `generation ~= retinue.generation`, or no member with that id, or `retinue.roster` nil):
   - `dismiss`: `snapshot` present → `pcall(backups.store, retinue.unit, m, snapshot)`, failure through `report("backup", err)`; the
     transition still runs. `retinue.ambiguous[id]` or `retinue.found[id]` → `log_line(still_here_text)`, no transition. Else `mark_away`,
     `budget:forget(id)`, `log_line(away_text(m.name, from, "dismiss"))`. `already_away`: nothing.
   - `hire`: ambiguous → nothing. `mark_returning` succeeds → `budget:forget(id)`, `log_line(returning_text(m.name, backup's level))`. A present member
     first goes through `mark_away` (`away_text(m.name, from, "hire")`). Returning: nothing.

   `flow.tick`: `budget:sync(retinue.generation)` first. Then return unless `in_world` and `roster.writable(retinue.roster)`. For each
   member with status RETURNING, not ambiguous, not `budget:closed`: `view = found[id]`; `action = departure.step{ in_party = view ~= nil,
   game_level = view and party.level(view), backup = backups.get(id), expired = budget:expired(id, now) }`.
   - WAIT: nothing.
   - TIMEOUT: `budget:close(id, "timed out")`, `log_line(timeout_text)`.
   - SKIP_NO_BACKUP: `mark_present(id, view.character_id)`, `forget`, `log_line(no_backup_text(m.name, backups.note(id) or "missing"))`.
   - SKIP_GUARD: `mark_present`, `forget`, `log_line(guard_text)`.
   - RESTORE: `pawns.restore(view, b)`. `"done"`: `mark_present`, `forget`, `log_line(restored_text(m.name, game_level, b.level))`, then under pcall
     `pawns.read(view)` and `backup.recorded_mismatch`: non-empty → `log_line(recorded_text)`. `"wait"`: `report("restore", m.name .. ": " .. why)`.
     `"mismatch"`: `budget:close(id, "differs at " .. field)`, `log_line(mismatch_text)`.
   Each member's attempt runs under its own pcall, failure
   through `report("restore", err)`; one member never blocks the other.

**Acceptance criteria**:
- [ ] `tests/roster_test.lua`: each `mark_*` from each status, locked, unknown id, read-only in memory, the kept `character_id` on away and
  returning, `mark_present` with new / nil / invalid id; `member_text` with `restore_note` alone and next to a backup note.
- [ ] `tests/backup_test.lua`: `restored_mismatch` equal, each kind of field different, array length, `1` vs `1.0`; `recorded_mismatch` equal, one different,
  nil on either side ignored, `item_ids` ignored.
- [ ] `tests/departure_test.lua` (new): `step` on every row, the guard at equal / lower / higher level, ready at expiry restores; the budget's deadline start,
  expiry, close, forget, note, generation change; every text, with `27.0` printing `27`.
- [ ] `tests/lifecycle_test.lua` (new), with fakes built on the real `roster`: dismiss with the pawn gone → away, roster mark called, snapshot stored first, kept
  `character_id`; dismiss with the pawn still in `found` → no transition, the snapshot still stored; a store that throws still transitions; a dismiss
  while returning → away; events held while `party.failed` or no main pawn, then applied in order (dismiss then hire of one id ends returning); stale generation dropped;
  hire of away / present / unknown / ambiguous; tick: out of the world nothing runs and the budget does not start, read-only nothing runs, ambiguous skipped,
  restore next tick after the hire, wait until ready then done with `character_id` set, timeout closes once with one line and no later attempts, a new generation retries it,
  mismatch closes, guard, no backup, equal level restores, one member's throw leaves the other restored, recorded mismatch logged.
- [ ] `tests/run.sh` passes.

**Verify**: `tests/run.sh`.

**Out of scope**: anything under `game/`, `Retinue.lua`, docs, the party diff (ticket 20), reconciliation (ticket 21), notices (ticket 23).

---

## Slice 2: Game glue

**Goal**: dismissing a member at the Rift saves a last backup and marks it away; hiring it again restores its progress one frame later;
the menu shows the status. Nothing else changes for ordinary pawns.

**Context** (read first): this plan's Facts; `src/autorun/Retinue.lua`, `game/progression_hooks.lua`, `game/slot_hooks.lua` (hook entry shape, `tracker.missing`),
`game/party.lua`, `game/pawn_state.lua`, `game/backup_store.lua`, `game/roster_store.lua`, `game/roster_menu.lua`, `hooks.lua`;
`tools/experiments/Retinue_Exp_Restore.lua` lines 760-950 (`write_array`, `do_restore`) and 1088-1160 (pre/post of hire and dismiss).

**Design**:

1. `game/party.lua`: export `M.offline_id(chara) -> canonical | nil`: `get_Context`, `M.holder_context(holder, OWNER_CONTEXT)`, `_OfflineID` through `as_string`, `roster.canonical_id`;
   nil when the holder or context is absent, throws when a read fails. `read_identity` is unchanged.

2. `game/pawn_state.lua`: `reader.restore(view, b) -> "done" | "wait", why | "mismatch", field`, for the game thread only:
   - Under pcall get `get_Human`, status and job contexts, `_IncreaseParams`, `CulmativeExp`. Anything nil or a throw → `"wait", why`, nothing written.
   - `arr:call("get_Length") ~= #b.culmative_exp` → `"mismatch", "culmative_exp length"`, nothing written.
   - Under one pcall (a throw → `"wait", why`; writes are idempotent): `st:call("set_Level", ...)`, `st:call("set_Exp", ...)`; on `ip`: `was_ro = ip:get_field("ReadOnly") == true`, `setReadOnly(false)` if
     so, `ip:set_field(INCREASE_FIELDS[key], v)` per key, `setReadOnly(true)` if so; `setExtraStatusBoost` then, when `_AcquiredExtraStatusBoost` differs,
     `set_field`; `set_ConsumableExpProp` then, when `ConsumableExp` differs, `set_field`; `for i = 0, n - 1 do arr[i] = b.culmative_exp[i + 1] end`. Every value through `slot.to_int`.
   - Read back with `read_restored(chara, back)` (a throw → `"wait"`), then `backup.restored_mismatch(b, back)`: a field → `"mismatch", field`; else `"done"`.

3. `game/backup_store.lua`: split `capture`, with no behaviour change for its callers:
   ```lua
   -- backups.eligible(retinue, m) -> view | nil   writable roster, unit known, m PRESENT, in retinue.found. The one gate of poll and dismiss.
   -- backups.read(m, view) -> snapshot | nil      the read half of capture: the note and report on failure, fresh.name, carry_recorded.
   -- backups.store(unit, m, fresh, opts)          the write half: decide (or opts.force), write, last, problem, the lowered line.
   -- backups.capture(unit, m, view, opts)         read then store.
   -- backups.get(id) -> last[id]
   ```
   `poll` uses `eligible`. Update the header comment.

4. `game/roster_store.lua`: add `store:mark_away(id)`, `store:mark_returning(id)`, `store:mark_present(id, character_id)`: call `roster.mark_*(self.roster, ...)`, on success `save()`, return
   the roster function's results unchanged (`nil, err` passes through). `self.roster` nil → `nil, "no_slot"`. Update the header comment.

5. New `game/lifecycle_hooks.lua`, `M.install(report, retinue, backups)`, returning `{ available, missing, begin_update(), drain() }`. Own entries through `hooks.install`, all or nothing:
   ```lua
   { key = "dismissPawn(CharacterID)", type = "app.PawnManager", sig = "dismissPawn(app.CharacterID)", pre, post }
   { key = "dismissPawn(Character)",   ... sig = "dismissPawn(app.Character)",   pre, post }
   { key = "dismissPawn(Pawn)",        ... sig = "dismissPawn(app.Pawn)",        pre, post }
   { key = "hirePawn",                 ... sig = "hirePawn(app.Character, System.Boolean)", pre, post }
   ```
   Instance methods: the first parameter is `args[3]`. Hooks only read the game and never change an argument.
   - `dismissing` (one table or nil), `hiring` (a Character or nil), `queue` (array).
   - Dismiss pre: `if dismissing then return end` (the nested overload). Character ID of the argument: `hooks.arg_u32(args[3])`; `sdk.to_managed_object(args[3]):call("get_CharaID")` through `hooks.to_u32`; or
     `:call("get_CachedCharacter")` first for the `Pawn` overload (a nil object: return). Find the `id, view` in `retinue.found` with that `character_id`; `m = roster.find(retinue.roster, id)`. No
     member or `m.status == roster.AWAY`: return. Set `dismissing = { kind = "dismiss", id = id, generation = retinue.generation }` **before** reading, so a failed read still departs. When
     `backups.eligible(retinue, m)`: `dismissing.snapshot = backups.read(m, view)`.
   - Dismiss post: `if dismissing then queue it; dismissing = nil end`.
   - Hire pre: `hiring = sdk.to_managed_object(args[3])`.
   - Hire post: take and clear `hiring`. Nil, or `sdk.to_int64(retval) & 1 ~= 1`: return. `id = party.offline_id(chara)`; when `roster.find(retinue.roster, id)`, queue `{ kind = "hire", id = id, generation = retinue.generation }`.
   - `begin_update()` clears `dismissing` and `hiring`: a game exception skips a post, and the next `pre` would be taken for a nested one.
   - `drain()` returns the queue and starts a new one.
   - Missing methods: `log.error("[Retinue] departure tracking unavailable: <method> not found")` per method, like `slot_hooks`.

6. `Retinue.lua`:
   - Build order: `backups`, `retinue`, then `life_hooks = lifecycle_hooks.install(report, retinue, backups)`, `flow = lifecycle.new{ retinue = retinue, backups = backups, pawns = pawns, party = party, drain = life_hooks.drain,
     log_line = function(text) log.error("[Retinue] " .. text) end, report = report }`.
   - `state.in_world = false`. In `re.on_frame`, after the roster update and only if `ok_roster`: `local world = tracker.in_world(party.has_main_pawn())`, `state.in_world = world`, `pcall(flow.update)` (failure:
     `report("lifecycle", err)`), then the existing poll with `world`. A failed roster update sets `state.in_world = false`.
   - In the `UpdateBehavior` callback, after `clear_calls`: `life_hooks.begin_update()`, then `pcall(flow.tick, os.clock(), state.in_world)`, failure `report("lifecycle", err)`.
   - Independent of `state.enabled`. Pass `flow` to `menu:draw`. Menu: `for _, method_name in ipairs(life_hooks.missing)` a line "Departure tracking unavailable: <method> not found (game update?)".
   - Update the header comment (dismiss, Return and restore, in two or three sentences) and the layout paragraph.

7. `game/roster_menu.lua`: `draw` gains `flow`; the member line passes `restore_note = m.status == roster.RETURNING and flow.note(m.offline_id) or nil`. Update the signature comment.

8. Docs:
   - `CHANGELOG.md` Unreleased → Added: dismiss marks away, Return restores.
   - `spec.md` § Departure and Return: "A Return with no usable backup becomes present with a warning; the poll then rewrites the file." and "A dismiss while `returning` → away, backup untouched."
   - `docs/testing.md` check 26: after "on its Return no restore", add "it becomes present at the game's level (log `skipped: no backup`) and the poll rewrites the file".
   - `CONTEXT.md` only if a term changes (none expected).

**Acceptance criteria**:
- [ ] A dismiss of a present member stores its last state from the frame loop, not the hook, and marks it away only when it left the party; `character_id` kept.
- [ ] A hire whose OfflineID is an away member's makes it `returning`, roster written, backup frozen (the poll skips it).
- [ ] The restore runs in `UpdateBehavior`, one frame later at the earliest, retried up to ~10 s, with the writes and read-back of findings 0008, and the fallbacks for boost and discipline.
- [ ] Nothing depends on the progression toggle. Locked: nothing happens. Read-only: no file written, no restore. Ambiguous: excluded.
- [ ] A missing hook method installs none of the four, says so in the log and menu, and leaves the rest of the mod working.
- [ ] The hooks do no file I/O and never change an argument or a return value.
- [ ] `tests/run.sh` passes; every changed glue file parses.

**Verify**: `tests/run.sh`; `for f in src/autorun/Retinue.lua src/autorun/Retinue/*.lua src/autorun/Retinue/game/*.lua; do lua5.4 -e "assert(loadfile('$f'))"; done`. There is no harness for the glue: it is verified in game after the final pass.

**Out of scope**: party diff, `PawnManager.lost` (ticket 20); reconciliation (ticket 21); notices, `labels` (ticket 23); Rift marks (ticket 26); new-game archive (ticket 22).
