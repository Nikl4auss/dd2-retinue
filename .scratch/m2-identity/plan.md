# M2 plan: ticket 21 (The roster reconciles with the loaded save)

Source: [issues/21-reconcile-on-load.md](issues/21-reconcile-on-load.md), [spec.md](spec.md) § Reconciliation on load. Base commit: `53dd7e3`.
(Plans of earlier tickets are in git history.)

Two slices, sequential.

- [x] Slice 1: pure decisions (`reconcile.lua`, `roster.apply_corrections`, `hire_time` in the backup) and their tests. Tier: **Sonnet** (`implementer`).
- [ ] Slice 2: the pass in the game (lifecycle gate, store hold, `_HireTime` read, wiring), lifecycle tests, docs. Tier: **Sonnet** (`implementer`).

Cross-review: skipped (Sol and Astra unavailable on this account); Opus `reviewer` only.

Facts the design rests on (run files `docs/findings/data/2026-11-03-m2-lifecycle/`, `2026-11-04-m2-restore/`):

- **`SubPawnDataContext._HireTime` marks one hire.** Folken: 37991.99912477005 in the fixture across every run and reload; a new value on each re-hire (c 39276.41967765521, d 38927.32584851235,
  restore-c 41038.68011890445); the value survives save and reload to the last digit (c2 and c3, and the four restore-c files). Diamonds, never dismissed: 32135.22838183213 in all 12 files.
  It is the save's clock (c is larger than d though it ran earlier), so it rolls back with a rollback.
- **Unknown, checked in game:** no run has `_HireTime` for a re-hire that kept its CharacterID (ticket 19's checks did not record it). A hire sets it, so the design assumes it changes. Check 29b records it.
- A re-hire comes back at exp 0, discipline 0 (findings 0006).
- On a load the hired pawns register with the main pawn (ticket 20's plan), but a zero GUID reads as a complete identity read, and the pass has no 3-miss protection of its own.
- `roster_store.update` refreshes the cache on the frame of the load request and on every party change, so by world entry the present member's kept CharacterID has been overwritten by the loaded one.
  The present row cannot compare anything unless that refresh waits for the pass.
- A load request bumps `generation` at once, while the old party can still be in the list and `in_world` still true (a load from the pause menu). A pass on that frame would judge the old party.

Decided here:

- **The discriminator is the hire time, kept in the backup** (recorded, never restored, frozen while away, so it already has the right lifetime and needs no party or roster change). Stored as integer milliseconds:
  backup files are verified after write with `==`, and an integer survives JSON exactly.
- **Different hire time → Return; equal → same hire, save wins.** Not "later": a false Return only gives a pawn its backup back; a false rollback lowers the backup for good. So a rollback to before an earlier
  Return restores the backup, the one case that departs from "save wins".
- **Fallback when either hire time is unknown** (backups written before this ticket, an unreadable context): CharacterID as the spec says, plus the first-hire signature for the same-ID case: exp 0, discipline 0 and behind the backup → Return.
- **The present row uses the same test** (ticket 18's comment): a Return the mod did not see, on a member still marked present, goes `returning`, so the poll never lowers the backup. A present member with no hire times and no kept CharacterID stays present: nothing says it left.
- **Gate:** the pass runs once per generation, after the game has left the world since the generation changed (or after a 20 s grace, so a start request that never leaves the world cannot hold the session), and after 3 s in the world with a complete party read.
  While it is pending the hook events wait, and the diff, the poll, the restore attempts and the cache refresh hold. `party.all_read` false only delays it.
- **`pawns.read` failing for a member** does not hold the pass: its level, exp and hire time count as unknown, and it is reported.
- **Read-only:** corrections apply in memory (`save` writes nothing). Locked: no plan, the gate still opens. Unknown slot: no roster, the gate still opens.
- **Returning / in party** is not a correction: no change and no line, `flow.tick` retries once the gate opens (its budget was dropped by the new generation).
- **Ambiguous** members get no correction.
- One roster write per pass (`store:correct`), not one per correction.

## Slice 1: Pure decisions

**Goal**: the reconciliation table, including the discriminator, as pure tested code. Nothing in the game changes yet.

**Context**: `src/autorun/Retinue/{roster,backup,departure}.lua`, `tests/{roster,backup,departure}_test.lua`, spec § Reconciliation on load (spec text is updated in slice 2; this plan wins where they differ). Modules are pure Lua 5.4: no REFramework globals.

**Design**:

1. `backup.lua`: add `"hire_time"` to `M.RECORDED_KEYS`, and to the shape comment: `hire_time = int -- SubPawnDataContext._HireTime in ms; marks one hire`. It stays out of `recorded_mismatch` (its list is explicit) and `invalid`. Adding it to `RECORDED_KEYS` gives `carry_recorded` (a failed read keeps the last value); `same` makes `decide` write when it changes, so an older backup gains it on the next poll.

2. `roster.lua`:
   ```lua
   -- apply_corrections(r, corrections) -> count. corrections: array of { id = <canonical>, to = status }. Sets each listed member's status
   -- (any status to any status: reconcile.plan decided); a listed id that is not a member is skipped. LOCKED or nil r -> 0. Never touches files;
   -- works in memory for READ_ONLY too. character_id is left alone.
   ```

3. New `src/autorun/Retinue/reconcile.lua`, header comment saying what it holds:
   ```lua
   M.SETTLE_SECONDS = 3   -- in the world with a complete party, before the pass: the party diff's 3 checks
   M.GRACE_SECONDS = 20   -- a generation that never leaves the world stops waiting for it

   -- first_hire_state(p, b) -> boolean: p.exp == 0, p.discipline == 0, and p is behind b: p.level < b.level, or equal level with b.exp > 0 or b.discipline > 0.
   --   Any of p.level, p.exp, p.discipline nil, or b nil -> false.

   -- rehired(m, p, b) -> boolean. m member, p party entry, b backup|nil.
   --   hire = slot.to_int(b and b.hire_time), seen = slot.to_int(p.hire_time). Both non-nil: hire ~= seen.
   --   Otherwise: m.character_id nil -> m.status ~= roster.PRESENT. p.character_id ~= m.character_id -> true. Else first_hire_state(p, b).

   -- plan(r, party, ambiguous, backup_of) -> corrections, in roster order
   --   party:     { [offline_id] = { character_id = int|nil, level = int|nil, exp = int|nil, discipline = int|nil, hire_time = int|nil } }
   --   ambiguous: { [offline_id] = true }
   --   backup_of(id) -> backup | nil
   --   correction: { id = <canonical>, name = string, from = status, to = status, text = string }
   --   nil r or LOCKED -> {}. An ambiguous member -> none.
   ```
   | status | in `party`? | rehired | to | text |
   |---|---|---|---|---|
   | present | yes | no | none | |
   | present | yes | yes | returning | `reconcile.unseen_text` |
   | present | no | | away | `reconcile.absent_text` |
   | away | yes | no | present | `reconcile.rollback_text` |
   | away | yes | yes | returning | `reconcile.unseen_text` |
   | away | no | | none | |
   | returning | yes | | none | |
   | returning | no | | away | `reconcile.absent_text` |

   Log texts, without the prefix, `L` from `level_text(n)`: `Lv<n>`, or `Lv?` when nil (use `slot.to_int(n) or n`); `B` from the backup: `backup Lv<n>`, or `no backup`:
   ```
   rollback_text: "<name>: roster away, save has it <L> (<B>) → present, save wins"
   unseen_text:   "<name>: roster <from>, save has it <L> (<B>) → returning, re-hired unseen"
   absent_text:   "<name>: roster <from>, not in the save's party (<B>) → away, backup kept"
   ```

   The gate:
   ```lua
   -- new_gate(settle, grace) -> gate; one reconciliation per generation.
   -- gate.pending: true from a new generation until check returns true.
   -- gate:check(now, in_world, party_ready, generation) -> true on the one call that should run the pass
   ```
   Fields: `generation=nil`, `pending=false`, `left=false`, `born=nil`, `since=nil`, `was_world=false`. `check`:
   - `generation ~= self.generation`: record it, `pending = true`, `left = not self.was_world`, `born = now`, `since = nil`.
   - `self.was_world = in_world == true`.
   - not pending: return false.
   - not in_world: `left = true`, `since = nil`, return false.
   - not `left` and `now < born + grace`: return false. (The old party may still be there.)
   - not party_ready: `since = nil`, return false.
   - `since = since or now`; `now < since + settle`: return false.
   - `pending = false`, return true.

   `was_world` is updated after the generation test, so the frame of the bump reads the previous frame's world.

**Acceptance criteria**:
- [ ] `tests/reconcile_test.lua`: one test per row of the table above, with exact texts and `from` / `to`; roster order kept; ambiguous skipped; nil and locked roster give `{}`; a read-only roster still plans.
- [ ] `rehired`: equal hire times → false even with a different CharacterID; different → true even with the same CharacterID; a backup without `hire_time`, or a party entry without it → CharacterID rule; different CharacterID → true; none kept → true for away and returning, false for present; same CharacterID + first-hire state → true; same CharacterID + exp > 0 → false; no backup → false.
- [ ] `first_hire_state`: lower level; equal level with backup exp or discipline; equal level with both 0 → false; higher level → false; nil fields → false.
- [ ] Gate: a first generation out of the world opens `settle` after entering; a generation bumped in the world waits while the world stays on, opens after leaving and re-entering; the same, staying in the world, opens at `born + grace + settle`; leaving during the settle restarts it; `party_ready` false restarts it; true exactly once per generation; a second bump while pending restarts; a later generation pends again.
- [ ] `tests/roster_test.lua`: `apply_corrections` sets statuses, skips unknown ids, leaves `character_id`, returns the count, 0 for locked and nil, works for read-only.
- [ ] `tests/backup_test.lua`: `carry_recorded` carries `hire_time`; `decide` is WRITE when only `hire_time` differs, including nil in `last`; `recorded_mismatch` ignores it; `invalid` ignores a bad one.

**Verify**: `tests/run.sh`; `luac5.4 -p src/autorun/Retinue/*.lua` if `luac5.4` exists.

**Out of scope**: `lifecycle.lua`, anything under `game/`, docs.

## Slice 2: The pass in the game

**Goal**: on entering the world after each load the roster matches the save, with one log line per correction, a Return made without the mod is restored, and nothing else acts first.

**Context**: slice 1's `reconcile.lua`; `src/autorun/Retinue/{lifecycle,Retinue}.lua` (`src/autorun/Retinue.lua` is the main file); `game/{roster_store,pawn_state,party}.lua`; `tests/lifecycle_test.lua`; the plan's facts above.

**Design**:

1. `game/pawn_state.lua`, `reader.read`: after `skills`:
   ```lua
   recorded("hire_time", function()
       local holder = chara:call("get_Context")
       local sub = holder and party.holder_context(holder, "app.SubPawnDataContext")
       if sub == nil then error("no SubPawnDataContext") end
       local v = sub:get_field("_HireTime")
       if type(v) ~= "number" then error("_HireTime is not a number: " .. str(v)) end
       return math.floor(v * 1000)
   end)
   ```
   `party` here is `require("Retinue.game.party")` (`M.holder_context` is a module function; check for a require cycle, there is none today: `party.lua` does not need `pawn_state`). Add `hire_time` to the list in the `read` comment.

2. `game/roster_store.lua`:
   - New local `hold = false`, `refresh_due = false`. In the reload branch: `hold = true`, `refresh_due = false`, replacing `forced = true` (remove `forced`).
   - The refresh at the end of `update` becomes:
     ```lua
     if not hold and (refresh_due or party.changed()) then
         refresh_due = false
         if roster.refresh_cache(r, views) then save() end
     end
     ```
     So a present member's kept CharacterID survives to the pass; `store:adopt` is unaffected.
   - `store:correct(corrections)`: `nil` roster returns 0; `roster.apply_corrections`, `save()` once when the count is above 0, returns the count.
   - `store:settle()`: `hold = false`, `refresh_due = true`. Document both in the header list.

3. `lifecycle.lua`: `local gate = deps.gate or reconcile.new_gate(reconcile.SETTLE_SECONDS, reconcile.GRACE_SECONDS)` (document `gate` in `M.new`'s comment: the tests replace it).
   ```lua
   local function party_entry(m, view)
       -- pawns.read under pcall; failure goes through report("reconcile", m.name .. ": " .. why) and gives { character_id = view.character_id }
       -- success: { character_id = view.character_id, level = s.level, exp = s.exp, discipline = s.discipline, hire_time = s.hire_time }
   end
   local function reconcile_pass()
       -- r = retinue.roster; nil or LOCKED -> return
       -- party = entries for every member in retinue.found
       -- corrections = reconcile.plan(r, party, retinue.ambiguous, backups.get)
       -- if #corrections > 0: retinue:correct(corrections); log_line(c.text) each, in order
   end
   ```
   `flow.update(now, in_world)`:
   ```lua
   local ready = party complete: not party.failed and party.has_main_pawn() and party.all_read()
   if gate:check(now, in_world, ready, retinue.generation) then
       local ok, err = pcall(reconcile_pass)
       if not ok then report("reconcile", err) end
       retinue:settle()
   end
   apply_events()
   -- then the diff, with `and not gate.pending` added to its ready test
   ```
   A failed pass still settles: a throw must not hold the session. In `apply_events`, the early return also fires on `gate.pending` (events wait; stale ones are still filtered first). `flow.tick`: after `budget:sync`, `if gate.pending then return end`. New `function flow.settled() return not gate.pending end`.

4. `Retinue.lua`: `pcall(backups.poll, retinue, world and flow.settled(), os.clock())`. Header comment: one sentence after the lost-member sentence on the pass. Add `reconcile` to the Layout list.

5. `tests/lifecycle_test.lua`: `setup` passes `gate = opts.gate or { pending = false, check = function() return false end }`, and adds `retinue:correct` (order entry `"correct"`, one per call, `roster.apply_corrections`) and `retinue:settle` (counts `t.settles`). Existing tests stay as they are. New tests use `opts.gate = reconcile.new_gate(reconcile.SETTLE_SECONDS, reconcile.GRACE_SECONDS)`.

6. Docs:
   - `spec.md` § Reconciliation on load: replace the table with slice 1's rows and a paragraph on the discriminator (hire time, fallback, why different and not later); note the gate. § Backups: add `hire_time` to Recorded. § Code layout: `reconcile.lua`'s inputs. § Identity: CharacterID's "only compared on load" gains "when the hire time is unknown".
   - `CONTEXT.md` § Identity: **Hire time** (`SubPawnDataContext._HireTime`): marks one hire; changes on a re-hire, survives save and load. Never identifies a pawn.
   - `docs/findings/0006-m2-dismiss-lost-rehire.md`: a row `_HireTime` in the re-hire table, with the plan's values. `docs/findings/api-map.md`: `_HireTime` role.
   - `docs/testing.md`, check 20: the backup now decides, so the second case becomes "roster `away`, Folken in party, **`hire_time` removed from his backup and `character_id` changed** → `returning`..."; first case unchanged; add a case: roster `present`, backup `hire_time` changed to another number → `returning`, restored. Check 19 unchanged. Check 29: expected log gets the `re-hired unseen` line; add 29b: note `hire_time` in the backup before and read the new one after; if the CharacterID was kept, record whether the time changed.
   - `CHANGELOG.md`: one entry under Unreleased.
   - The ticket: tick boxes for what is done, leave the in-game box open, comment with decisions and commit SHAs.

**Acceptance criteria**:
- [ ] `tests/lifecycle_test.lua`: nothing happens before the gate opens: no `correct`, no restore from `tick`, no absence, events held, `flow.settled()` false; then the pass runs once.
- [ ] A row end-to-end through `flow`: away + same hire time → present, line logged, no restore; away + different → `returning`, then `tick` restores; present + different → `returning`; returning + absent → away, no store; present absent → away.
- [ ] One `correct` call per pass; none when there are no corrections; `settle` called exactly once, also for locked, nil roster, and a throwing `pawns.read` or `retinue:correct`.
- [ ] `pawns.read` failing: reported, other members still judged, the member with an equal CharacterID stays where it is.
- [ ] A new generation: the gate pends again, a queued event of the old generation is dropped, the old roster object is not written (no `correct`, no `mark_*`).
- [ ] Read-only: corrections applied through `correct`; `tick` restores nothing.
- [ ] Locked: no `correct`, `settle` called. Ambiguous: no correction.
- [ ] The diff and `flow.tick` act again after the pass.

**Verify**: `tests/run.sh`; `luac5.4 -p src/autorun/Retinue.lua src/autorun/Retinue/*.lua src/autorun/Retinue/game/*.lua` if `luac5.4` exists.

**Out of scope**: ticket 22's archive; notices (ticket 23: restored ones stay log lines); forcing a backup right after a restore (the poll covers it within 10 s, and a false Return from that gap restores equal values); `_HireInGameTime`; `party.lua`.
