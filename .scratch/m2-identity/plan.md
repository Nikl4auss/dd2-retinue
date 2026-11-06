# M2 plan: ticket 20 (A lost member becomes away)

Source: [issues/20-lost-member-away.md](issues/20-lost-member-away.md), [spec.md](spec.md) § Departure and Return. Base commit: `e0fd4ee`.
(Plans of earlier tickets are in git history.)

One slice.

- [x] Slice 1: the party diff (pure, tests), wiring, docs. Tier: **Sonnet** (`implementer`).

Cross-review: skipped (Sol and Astra unavailable on this account); Opus `reviewer` only.

Facts the design rests on (run files `docs/findings/data/2026-11-03-m2-lifecycle/`, game logs):

- **On a load the hired pawns register with the main pawn** (same timestamp, in runs b, c, e; hired first in c and e), so entering the world
  does not see a member missing.
- ***Kill pawns* removes the main pawn too** (e: `lost` and `unregistPawn` for all three at 197.3); it comes back at a Rift stone (`hirePawn` of
  the main pawn at 486.2). "In the world" needs the main pawn, so the member stays `present` until then: away comes ~3 s after the main pawn
  is back, not ~3 s after the kill. The ticket's check 14 is reworded. A re-hire inside those seconds is covered (cause `hire`).
- **Unknown, checked in game:** going to the title, the hired pawns leave the party 5.6 s (b) to 8.7 s (c) before the main pawn. If `FlowPhase` is
  still `InGame` in that gap, the diff marks members away and writes the roster. The log only shows `in the world: no (phase 43)` on the way
  out, not which came first. Check 14 includes this. If it happens, the guard goes in before this ticket closes. Ticket 21's row "away, in party,
  same CharacterID → present" would repair the roster on the next load, so the damage is bounded either way.
- Not observed: fast travel. Runs show no party `unregistPawn` around Rift use. Check 14 includes one ferrystone.

Decided here (the spec leaves them open):

- **Leaving the world drops the counts**, as a new generation does: "consecutive" means consecutive checks in the world.
- **The first check is a full second after entering the world** (the timer is `backup.new_poll`, which re-arms there): away comes ~3 s after entering at the earliest.
- `retinue.found` is the diff's input. It matches any party slot, which equals slots 1–2 because the main pawn has no Offline ID.
- **Read-only**: the diff runs in memory, like the dismiss transition; `save` writes nothing. **Locked** or no roster: no check. **Ambiguous**: never missing.
- **Only `present` counts.** A `returning` member that is absent is ticket 21's row.
- **An unreadable party holds the diff** (reviewer, round 1): an identity read that did not complete, or a list entry with a pawn but no readable character or ID, is not an absence. The check counts as out of the world, so the counts drop. `party.lua` gains `all_read()`. A zero GUID (online pawn) is a complete read, and an empty list entry is not unread.
- **A false away is not repaired within the session** (a pawn in the party with status away): out of scope, ticket 21 repairs it on the next load.

---

## Slice 1: The party diff

**Goal**: a present member missing from the party for 3 consecutive checks, about 1 s apart, in the world, becomes away, logged as
`<name>: present→away (absence)`, whatever the progression toggle says.

**Context** (read first): `src/autorun/Retinue/departure.lua`, `lifecycle.lua`, `backup.lua` (`new_poll`), `tests/departure_test.lua`,
`tests/lifecycle_test.lua` (style: plain `assert`s in `do ... end`, Lua 5.4; `setup` builds the fakes), `src/autorun/Retinue.lua`. Pure means no REFramework globals.

**Design**:

1. `departure.lua`: remove "(Ticket 20 adds the miss counter here.)" from the header and say what the file now holds. Add:
   ```lua
   M.CHECK_SECONDS = 1
   M.MISS_LIMIT = 3

   -- new_diff(interval, limit) -> diff; the counts of the party diff, per member.
   -- diff:check(now, in_world, generation, missing) -> ids that just became absent, in missing's order (usually {})
   --   missing() -> array of ids missing right now; called only when a check is due.
   --   A check is due every `interval` in the world (backup.new_poll: re-armed on entering the world and on a new generation).
   --   Each id in missing gains 1; an id not in it loses its count (a reappearance resets); an id reaching `limit` is returned and loses its count.
   --   Not in the world, or a new generation: every count is dropped.
   ```
   Implementation: a metatable object holding `poll = backup.new_poll(interval)`, `limit`, `generation`, `counts`. `check` drops the counts first when
   `generation ~= self.generation or not in_world` (recording the generation), then `if not self.poll:tick(now, in_world, generation) then return {} end`,
   then builds a new `counts` table from `missing()`.

2. `lifecycle.lua`: `local diff = departure.new_diff(departure.CHECK_SECONDS, departure.MISS_LIMIT)`. `flow.update` becomes `flow.update(now, in_world)`:
   ```lua
   local function missing()   -- members with status PRESENT, not in retinue.found, not in retinue.ambiguous, in roster order
   local function absence(id) -- m = roster.find; local member, from = retinue:mark_away(id); member non-nil -> log_line(departure.away_text(m.name, from, "absence"))
   ```
   Move the current body of `flow.update` into a local `apply_events()`. Its early return must not skip the diff. Then `flow.update` is:
   ```lua
   apply_events()
   local r = retinue.roster
   local ready = in_world and r ~= nil and r.mode ~= roster.LOCKED and not party.failed and party.has_main_pawn()
   for _, id in ipairs(diff:check(now, ready, retinue.generation, missing)) do
       -- pcall(absence, id), failure through report("lifecycle", err)
   end
   ```
   Events run first, so a queued dismiss wins and logs cause `dismiss`. Update the `flow.update` comment and the file header to say it also runs the party diff.
   `in_world` nil (the existing tests' `flow.update()`) means no check. Do not change them.

3. `Retinue.lua`: `pcall(flow.update, os.clock(), world)`. Header comment: after the Dismissing/Hiring sentences add that a member that leaves
   any other way (lost) is noticed by a party check about every second in the world and marked away after 3 misses; its backup is the last poll.

4. Docs. `CHANGELOG.md`: extend the Departure and Return entry with one sentence. `docs/testing.md` check 14 becomes:
   ```
   14. **Lost**: restore `m2-adopted-folken`. *Kill pawns* (Nick's Devtools): the main pawn leaves too, so the log shows
       `in the world: no` and Folken stays `present`. Travel to a Rift stone: within ~3 s of the main pawn's return (`in the world: yes`), log
       `present→away (absence)`; backup = the last poll (Lv 28). Re-hire: restored as in check 12. Natural lost (down timer or rest) *(opportunistic)*:
       the main pawn stays, so away comes ~3 s after the pawn leaves.
       **No false absence**: from a save with Folken present, use a ferrystone, then go to the title and load: no `absence` line in the log, `present` in the roster.
   ```
   Keep the file's wrapping and the numbering of the other checks.

**Acceptance criteria**:
- [ ] `tests/departure_test.lua`, `new_diff`: first check due only after `interval`; 3 consecutive misses return the id exactly once, on the third; 2 misses, a reappearance, 2 misses:
  nothing; not due between checks (and `missing` not called); out of the world: not called, counts dropped (2 misses, world off, world on, 2 misses: nothing); a new generation drops the counts; two ids count independently and return in `missing`'s order.
- [ ] `tests/lifecycle_test.lua`, extended `setup` usage: a present member absent for 3 checks → away, roster written through `retinue:mark_away`, exact log line `Ana: present→away (absence)`; `character_id` kept.
- [ ] Same file: found again before the third check → stays present; away and returning members never go through it; ambiguous never; read-only → away in memory; locked and nil roster → nothing; out of the world, `party.failed` and no main pawn → nothing and counts dropped; a queued dismiss in the same update logs `(dismiss)` only; a throwing `mark_away` for one member is reported and the other member still goes away.
- [ ] Toggle independence: nothing in the diff reads it (no parameter exists).
- [ ] `backups.store` is not called by the diff; the backup stays the last poll.

**Verify**: `tests/run.sh`; `luac5.4 -p src/autorun/Retinue.lua src/autorun/Retinue/*.lua` if `luac5.4` exists.

**Out of scope**: ticket 21's reconciliation; a same-session repair of a false away; hooks on `lost` or `unregistPawn`; `lifecycle_hooks.lua`, `roster_store.lua`; the title-exit guard (only if the in-game check needs it).
