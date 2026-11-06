# M2 plan: ticket 18 (Adopted pawns are backed up)

Source: [issues/18-adopted-pawns-backed-up.md](issues/18-adopted-pawns-backed-up.md), [spec.md](spec.md) § Backups,
§ Mod menu, § Code layout. Base commit: `ee1ab2d`. (Plans of earlier tickets are in git history.)

Two slices, sequential (slice 2 uses slice 1's module).

- [x] Slice 1: Pure `backup` module and the menu's backup note, with tests. Tier: **Sonnet** (`implementer`).
- [ ] Slice 2: Game glue: pawn read, backup store, delete, in-the-world signal, wiring. Tier: **Sonnet** (`implementer`).

Cross-review: skipped (Sol and Astra unavailable on this account); Opus `reviewer` only.

Facts the design rests on:

- **No file delete is confirmed in REFramework.** The installed LeovvayGore mod states "REFramework has no os.rename/os.remove"
  (`core/log.lua`); the delete path of the restore experiment never ran (no `delete_backup` action in any run file). The
  sandbox wraps `fs.read`/`fs.write`/`io.open`, and `jsonfile.read` already counts an empty file as missing. So "deleted"
  means: `os.remove` when it exists, else **emptied** with `fs.write(path, "")`: a 0-byte file reads as missing, and an
  orphan is ignored anyway. Deviation from the spec's "Release deletes the file" in the worst case only; the release log
  line says which path ran. Ticket 22's "move to archive" has the same problem (noted in that ticket).
- Field types (dump): `_Level`, `_Exp`, `_AcquiredExtraStatusBoost`, the eight `_IncreaseParams`, `ConsumableExp` and
  `CulmativeExp` elements are Int32; `QualifiedJobBits`, `ChangedJobBits` UInt32; `CurrentJob` enum (reads as a number).
  So a snapshot is all integers plus strings, and JSON round-trips it exactly.
- `HumanSkillContext.EquipedSkills` elements have `Skills: app.HumanCustomSkillID[]`. The lifecycle reader
  (`get_elements`, then `ToString` per element) gave real names (`Job01_BlinkStrike`, `None`), 6 per entry; the restore
  experiment's `read_numbers_any` stored `"nil"` for all of them on the same pawn. Copy the **lifecycle** reader, not that one.
- `ItemManager.hasEquipData(id)` then `getEquipData(app.CharacterID)` then `getItemIds()` (`List<Int32>`); the overload needs
  the experiment's `find_method` fallback (`td:get_method` may fail on the enum parameter).
- REFramework's json writes an empty `{}`/`[]` as `null`, which reads back as nil: an empty `item_ids` must compare
  equal to a missing one.
- "No load in progress" (spec § Terms): `MainFlowManager.get_FlowPhase()` equals the `Phase.InGame` static. **Unverified that
  it holds during normal play**: fails closed (no backups), the in-game check catches it, and a log line per change of
  in-the-world names the phase.
- A load request can precede the phase change by a few frames, and a just-loaded party may still settle: the poll timer
  re-arms on every roster reload and on entering the world, so the first poll is a full interval later.

Decided here (the spec leaves them open):

- A damaged, missing or newer-version backup of a **present** member is rewritten by the poll (the game is the authority
  while present); warning once. Of an away or returning member it stays untouched (frozen).
- A failed recorded-only read (skills, items, vocation bits) never blocks a backup: the value is carried from the last
  backup, reported once. A failed restored-field read writes nothing (never replace a good backup with a bad one).
- A failed backup at adopt does not undo the adopt: no `last`, so the next poll writes it.

---

## Slice 1: Pure backup module and the menu's backup note

**Goal**: the decisions behind backups exist as a pure, tested module: the file's shape, validating a file read
from disk, "did anything change", the level guard, and the poll timing. `roster.member_text` can show a backup note. No
game code changes.

**Context** (read first): spec § Backups; `src/autorun/Retinue/roster.lua` (`resolve`/`serialize`/`matches` pattern,
`canonical_id`), `src/autorun/Retinue/slot.lua` (`dir`, `to_int`), `tests/roster_test.lua` (test style: plain `assert`s in
`do ... end` blocks, `LUA_PATH` = `src/autorun/?.lua`, run by `tests/run.sh`, Lua 5.4). Pure means no REFramework globals.

**Design**: new `src/autorun/Retinue/backup.lua` requiring `Retinue.slot` and `Retinue.roster`.

```lua
M.VERSION = 1
M.POLL_SECONDS = 10
M.EQUAL, M.LOWER, M.HIGHER = "equal", "lower", "higher"
M.NONE, M.WRITE, M.LOWERED = "none", "write", "lowered"
M.INCREASE_KEYS = { "hit_point", "stamina", "attack", "defence", "magic_attack", "magic_defence", "blow", "weight" }
M.RECORDED_KEYS = { "current_job", "qualified_job_bits", "changed_job_bits", "item_ids", "skills" }

function M.path(unit, offline_id) end   -- slot.dir(unit) .. "/backups/" .. offline_id .. ".json"
```

The backup / snapshot (one flat table; also the file's content):

```lua
-- { version = 1, offline_id = <canonical>, name = string,
--   -- restored
--   level = int, exp = int, increase_params = { <M.INCREASE_KEYS> = int }, extra_status_boost = int,
--   discipline = int, culmative_exp = { int, ... },
--   -- recorded, never restored (any may be nil)
--   current_job = int, qualified_job_bits = int, changed_job_bits = int,
--   item_ids = { int, ... }, skills = { { string|int, ... }, ... } }   -- skills: one list per EquipedSkills entry
```

Functions:

- `M.invalid(b) -> nil | why`: nil when `b` is a usable backup: table; `offline_id` is `roster.canonical_id`-valid;
  `level`, `exp`, `extra_status_boost`, `discipline` integers (`slot.to_int`), `level >= 1`; `increase_params` a table with
  all eight integer; `culmative_exp` a non-empty sequence of integers. `why` is a short phrase naming the first bad field
  (`"level is missing or invalid"`). Recorded fields are not checked. The glue calls it on a fresh read too.
- `M.resolve(status, data, offline_id) -> backup | nil, problem`. `status`/`data` as `jsonfile.read`:
  `"missing"` → `nil, "missing"`; `"unparseable"` → `nil, "damaged: not valid JSON"`; any other non-`"ok"` status →
  `nil, "damaged: cannot be read"`; `"ok"`: non-table → `"damaged: not an object"`; `version` not an integer ≥ 1 →
  `"damaged: version is missing or invalid"`; `version > M.VERSION` → `"newer version <n>"`; `M.invalid` → `"damaged: <why>"`;
  `data.offline_id`'s canonical form ≠ `offline_id` → `"damaged: belongs to another pawn"`. On success returns `data`.
- `M.same(a, b) -> boolean`: deep comparison; numbers by `==` (1 and 1.0 are equal), strings by `==`, tables recursively over
  the union of keys, and nil equals an empty table at any depth (the json null caveat). Different types → false.
- `M.carry_recorded(fresh, last)`: mutates and returns `fresh`: each `M.RECORDED_KEYS` key that is nil in `fresh` is copied
  from `last` (`last` nil → unchanged).
- `M.guard(game_level, backup_level) -> M.EQUAL | M.LOWER | M.HIGHER`: the game's level relative to the backup's.
- `M.decide(last, fresh) -> M.NONE | M.WRITE | M.LOWERED`: `same` → NONE; `last` non-nil and `guard(fresh.level, last.level) ==
  LOWER` → LOWERED; else WRITE (a nil `last` is WRITE).
- `M.lowered_text(name, game_level, backup_level)` →
  `"<name>: save has Lv <g>, backup had Lv <b> -> backup lowered, save wins"`.
- `M.new_poll(interval) -> poll` with `poll:tick(now, in_world, generation) -> boolean`. Rules, in order:
  `generation` differs from the stored one (first call included) → store it, clear the deadline. Not `in_world` → clear
  the deadline, false. No deadline → deadline = `now + interval`, false. `now >= deadline` → deadline = `now + interval`,
  true. Else false.

`src/autorun/Retinue/roster.lua`: `member_text`'s `info` gains optional `backup_note` (string): appended last as
`", backup <note>"` after every other part, ambiguous included. Update the comment above it.

**Acceptance criteria**:
- [ ] `tests/backup_test.lua` (new) covers: `path`; `resolve` for every status and each problem above, one case per
  missing restored field, the other-pawn case, recorded fields absent still valid; `invalid`: `level = 0`, float `1.5`,
  integral float `27.0` valid; `same`: equal, one field differs (top, nested in `increase_params`, in `culmative_exp`, in
  `skills`), nil vs `{}` equal at top and nested, `1` vs `1.0`, a list of different length; `carry_recorded` including a
  nil `last` and a real value left alone, an empty `item_ids` not replaced; `guard` at equal / lower / higher; `decide` on
  all four paths (nil last, same, higher, lower; and exp lower at the same level is WRITE); `lowered_text`; `poll:tick`:
  first in-world tick false then true after the interval and false until the next, leaving the world and coming
  back re-arms, a generation change re-arms.
- [ ] `tests/roster_test.lua` covers `backup_note` alone and with level, `not in party` and ambiguous; existing cases unchanged.
- [ ] `tests/run.sh` passes.

**Verify**: `tests/run.sh`.

**Out of scope**: any glue, file I/O, restore, `dismissPawn`, away transitions (ticket 19).

---

## Slice 2: Game glue

**Goal**: every present member in the party has a backup file: written on adopt, refreshed about every 10 s only if a
value changed, emptied or deleted on release. A member below its backup lowers it, with one warning. The menu shows a
member's level from the backup when it is not in the party, and a note when its backup is missing or damaged. Runs with
the progression toggle off; nothing written when locked, read-only or slot unknown.

**Context** (read first): spec § Backups, § Mod menu, § Terms ("in the world"); `src/autorun/Retinue.lua`,
`game/party.lua`, `game/roster_store.lua`, `game/roster_menu.lua`, `game/jsonfile.lua`, `game/slot_hooks.lua`;
`tools/experiments/Retinue_Exp_Restore.lua` (`find_method`, `read_num_array`, `read_equip`, `read_fields`) and
`tools/experiments/Retinue_Exp_Lifecycle.lua` (`read_int_array`, `str`, the skills read at `context_fields`). The plan's
Facts above are binding. Lines go to `log.error` with the `[Retinue]` prefix, like the rest of the mod; repeatable failures
go through `report` (logs once).

**Design**:

1. `game/jsonfile.lua` gains `delete(path) -> "removed" | "emptied" | nil, err`:
   ```lua
   -- REFramework may have no os.remove (paths are relative to the game folder there, reframework/data here).
   if os and os.remove then pcall(os.remove, "reframework/data/" .. path) end
   -- without fs.read: nil, "cannot verify"
   -- fs.read returns "" for missing and empty alike: a file that is gone reads "" -> "removed".
   -- else, with fs.write: pcall(fs.write, path, ""), read again, "" -> "emptied". Else nil, "file still there".
   ```

2. `game/party.lua`: export `M.holder_context(holder, type_name)` (the `Contexts` dictionary lookup → `get_CurrentContext`,
   nil when absent; throws like the experiment's) and use it in `read_identity`. No behaviour change.

3. New `game/pawn_state.lua`, `M.new(report)` → `{ read = function(view) -> snapshot | nil, why }`. Field reads:
   - `chara:call("get_Human")`, `:call("get_StatusContext")`, `:call("get_JobContext")`. Status: `get_Level`, `get_Exp`,
     `_IncreaseParams` (`get_field`) with `_HitPoint _Stamina _Attack _Defence _MagicAttack _MagicDefence _Blow _Weight`
     to `backup.INCREASE_KEYS`, `_AcquiredExtraStatusBoost`. Job: `ConsumableExp`, `CulmativeExp` (the restore experiment's
     `read_num_array`, boxed elements), `CurrentJob`, `QualifiedJobBits`, `ChangedJobBits`.
   - Items: as `read_equip` (`find_method` fallback for `getEquipData(app.CharacterID)`, resolved once), `{}` when
     `hasEquipData` is false.
   - Skills: `party.holder_context(chara:call("get_Context"), "app.HumanSkillContext")`, then per `EquipedSkills` element
     the lifecycle's `read_int_array(e:get_field("Skills"))` (keep its `str`). Do not read `getEnableNormalSkillIDs`.
   - Restored reads under one pcall; each recorded read (the three job fields, items, skills) under its own: on failure
     that key stays nil and `report("backup <key>", err)`.
   - Fills `version`, `offline_id` (canonical from `view`), `name` (`view.name`; the store overrides it, see below); integer
     values through `slot.to_int`. Runs `backup.invalid`: returns `nil, why` when not usable.

4. New `game/backup_store.lua`, `M.new(report, read_pawn)`:
   ```lua
   -- backups.last     { [offline_id] = backup }   this activation's view of each member's file (nil: none usable)
   -- backups.problem  { [offline_id] = string }   backup.resolve's problem, or "write failed"; cleared on a good write
   -- backups.activate(unit, r)   clear both, then for each member read the file (jsonfile.read strict, backup.resolve),
   --                             log "[Retinue] <Slot n> backup of <name>: <problem>" once per problem. Reads for any r
   --                             with members (read-only too). r nil or locked: stays empty.
   -- backups.capture(unit, m, view, opts) -> nothing. pcall'd read_pawn(view) (failure: report("backup read", why)
   --                             and return). fresh.name = m.name; backup.carry_recorded(fresh, last[id]);
   --                             opts.force skips decide (always writes, never LOWERED); else decide: NONE -> return.
   --                             jsonfile.write(path, fresh, function(back) return backup.same(fresh, back) end).
   --                             ok: last[id] = fresh, problem[id] = nil, on LOWERED one log.error(backup.lowered_text(...)).
   --                             Fail: problem[id] = "write failed", report("backup write", err); last unchanged.
   -- backups.poll(retinue, in_world, now)  poll:tick(now, in_world, retinue.generation); when due and
   --                             roster.writable(retinue.roster): capture every member with status PRESENT in
   --                             retinue.found (found already excludes ambiguous members).
   -- backups.remove(unit, id) -> how | nil, err   clear last/problem; jsonfile.delete(backup.path(unit, id)).
   -- backups.level(id)        last[id] and last[id].level
   -- backups.note(id)         problem[id]
   ```
   Away and returning members are never captured here: that is the freeze.

5. `game/roster_store.lua`: `M.new(report, backups)`.
   - In `update`, in the reload branch, after the state is assigned: `backups.activate(unit, r)`.
   - `store:adopt`: after `save()`: `backups.capture(self.unit, m, view, { force = true })` (an orphan file of a re-adopted
     pawn is overwritten without a rollback warning). Under pcall, reported, never fails the adopt.
   - `store:release`: after `save()`: `backups.remove`; log line `released <name> (backup removed)` /
     `(backup emptied)`; on failure `report("backup delete", err)` and the line says `(backup left in place)`.
     `store:release` still returns true (an orphan is ignored).

6. `game/slot_hooks.lua`: `tracker.in_world(has_main_pawn) -> boolean`: main pawn present and `get_IsTitleMenuPhase() ==
   false` and `get_FlowPhase() ==` the `InGame` value (static field of `app.MainFlowManager.Phase`, cached once read; unreadable
   → false + `report`). Under pcall; a throw is false. One `log.error` per change: `[Retinue] in the world: yes` /
   `no (phase <n>)`.

7. `Retinue.lua`: require and build `pawn_state`, `backup_store` (before `roster_store.new(report, backups)`). In `re.on_frame`,
   after the roster update and only if `ok_roster`: `pcall(backups.poll, retinue, tracker.in_world(party.has_main_pawn()),
   os.clock())`, failure `report("backup", err)`. Independent of `state.enabled`. Pass `backups` to `menu:draw`. Update the
   header comment and the layout paragraph.

8. `game/roster_menu.lua`: `menu:draw` takes `backups`. In the member line: `level = (view and party.level(view)) or
   backups.level(m.offline_id)`, `backup_note = backups.note(m.offline_id)`. Update the `draw` signature comment.

9. Docs: `CHANGELOG.md` Unreleased → Added, one entry for backups. `spec.md` § Backups: "Release deletes the file" gains
   "(emptied when REFramework has no file delete: an empty file reads as missing)". `issues/22-…md`: a `## Comments` note that
   REFramework likely has no `os.rename`/`os.remove`, so the archive is copy + empty.

**Acceptance criteria**:
- [ ] Adopt writes `slots/<n>/backups/<offline_id>.json`; a failed read or write there does not fail the adopt.
- [ ] The poll runs about every 10 s, only in the world, for present members in the party, whatever the progression toggle.
- [ ] A poll with no change writes nothing (no `json.dump_file` call).
- [ ] A member below its backup: file lowered, exactly one `lowered_text` line.
- [ ] Release empties or deletes the file and the log says which; a failure leaves the release done.
- [ ] Nothing written when locked, read-only or slot unknown; away and returning members never written.
- [ ] A missing or damaged backup: one log line, a note in the menu, the roster and the other member unaffected.
- [ ] Unit switch or reload re-reads `last`, and pending polls wait a full interval.
- [ ] `tests/run.sh` passes; `luac5.4 -p` (or `lua5.4 -e "loadfile(...)"`) parses every changed glue file.

**Verify**: `tests/run.sh`; `for f in src/autorun/Retinue.lua src/autorun/Retinue/game/*.lua; do lua5.4 -e "assert(loadfile('$f'))"; done`.
There is no harness for the glue: it is verified in game after the final pass.

**Out of scope**: `dismissPawn` hooks, departure, Return, restore (ticket 19); native row and dialogs; archive on new game
(ticket 22); reconciliation (ticket 21). No new `report` wrappers, no atomic write.
