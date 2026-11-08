# M2 plan: ticket 25 (a full retinue offers to release an away member)

Source: [issues/25-retinue-full-release-away.md](issues/25-retinue-full-release-away.md), [spec.md](spec.md) § Adopt and Release (native),
[findings 0007](../../docs/findings/0007-m2-talk-ui.md) § Follow-up. Base commit: `dd6e340`.
(Plans of earlier tickets are in git history.)

- [x] Slice 1: the "full" sub-menu in the talk: pure decisions, labels, glue, tests, spec and checklist 13. Tier: **Sonnet** (`implementer`). One review round, APPROVE; nits (a guard for more than 2 away members, a stale labels comment) applied inline.
- [ ] Slice 2: in-game run, checklist 13, headless by the peer session `dd2-own-pawns-ee`; then the user's feel pass. Tier: **Opus, inline** (driving the peer).

Cross-review: skipped (Sol and Astra unavailable on this account); Opus `reviewer` only.

Decisions:

- **No dialog.** The spec's `requestDialog` flow leaks input (pad A, F held; ticket 24 manual pass). The choice lives in the Talk sub-menu,
  like ticket 24's confirm.
- **One step after Adopt** (the user, 2026-11-08): the sub-menu lists one row per away member, "Release <name> (away, Lv N)", then Cancel;
  picking a member row releases it and adopts the pawn. No separate "Their progress will be lost" step: the Talk route gives one sub-menu
  per root pick, and a second one would need a second root pick. Same depth as ticket 24's Release (root row, then the confirm row).
  The ticket's second criterion and the spec change accordingly.
- **Away** means status `away` only. `returning` and a `present` member missing from the party are not offered. Full with no away member
  keeps today's refusal: notice "Cannot adopt <name>: the retinue is full (2 members)", the talk ends.
- Level N is the backup's (`backups.level(id)`); unknown level prints "Release <name> (away)".
- CAP is 2, so at most 2 away rows: they take the sub-menu's rows 0 and 1 (Matters of import, Small talk) in place; with one away member,
  row 1 is removed as in ticket 24. Cancel stays the game's row 2 either way, so the same Cancel write and the same nextNode guard apply.

## Slice 1: The "full" sub-menu

**Goal**: with the roster full (2 members) and at least one member away, talking to a hired party pawn that is not a member and picking
"Adopt" goes into the Talk sub-menu, shown as "Release <name> (away, Lv N)" per away member (in roster order) and Cancel. Cancel changes
nothing and returns to the root menu. Picking a member releases it (roster entry removed, backup deleted, as `store:release`) and adopts the
talked-to pawn (as `store:adopt`), then returns to the root menu, which shows "Release (Retinue · Lv N)" for the new member. Full with no
away member: refused as today.

**Context**: read first `src/autorun/Retinue/talk_menu.lua` (pure: `row`, `refusal`, `confirm_pick`), `src/autorun/Retinue/game/talk_menu.lua`
(glue: `show_confirm`, `watch_offer`, `watch_confirm`, `act`, the re-show check in `on_req_disp`, the nextNode guards), `labels.lua`,
`roster.lua` (`CAP`, `AWAY`, `find`, `error_text`), `game/roster_store.lua` (`store:release(id)`, `store:adopt(view)`, `store.generation`),
`game/backup_store.lua` (`backups.level(id)`), `src/autorun/Retinue.lua` l. 114 (wiring of `talk_menu.new`), `tests/talk_menu_test.lua`,
`tests/talk_menu_glue_test.lua` (fake sdk; the adopt and release scenarios to copy), `tests/labels_test.lua`. Findings 0007 § Follow-up for
the game facts (SelectedIndex is the *shown* row index; writing 2 returns to the root through Cancel).

**Design**

`labels.lua`:

```lua
-- "Release <name> (away, Lv N)"; level nil -> "Release <name> (away)". num() as the other labels.
function M.release_away(name, level) end
```

`talk_menu.lua` (pure):

```lua
-- away_members(store, level_of) -> { { offline_id, name, level } } in roster order: members with status roster.AWAY.
-- level_of(id) -> number | nil (the backup's level). store.roster nil -> {}.
function M.away_members(store, level_of) end

-- refusal(store, action, level_of) -> err | nil, plus a second result:
--   adopt with #members >= CAP: away = away_members(...) non-empty -> nil, away (the pick goes to the full sub-menu);
--   empty -> "full". Everything else as today (no_slot, locked, read_only first). level_of may be nil for release.
function M.refusal(store, action, level_of) end

-- full_pick(sel, n) -> { kind = "release" | "cancel", index = i | nil, write = M.CANCEL_INDEX }: the pick on the full
-- sub-menu showing n (1 or 2) member rows then Cancel. 0 <= sel < n -> release member index sel + 1; anything else
-- (Cancel, nil, out of range) cancels.
function M.full_pick(sel, n) end
```

Glue (`game/talk_menu.lua`):

- `deps.backups` (game/backup_store's; optional: nil -> no level). `Retinue.lua` passes `backups = backups`.
- `watch_offer`: `local err, away = talk_menu.refusal(store, row.action, level_of)`. With `away`, arm as today but with `full = away` in the
  armed record (`armed = { row, generation, deadline, full = away }`); log line `picked (full: <n> away)`.
- `show_confirm`: when `c.full`, relabel row 0 to `labels.release_away` of `full[1]`; with two away members relabel row 1 to `full[2]`
  (set `_IsDecideEnable = true` on both) and keep it; with one, `RemoveAt(1)` as today. `menu = { mode = "full", widget, row, generation,
  full, label = <row 0's label> }`. The count-3 check stays.
- Re-show check in `on_req_disp`: accept `prev.mode == "full"` as well as `"confirm"` (same first-row label test).
- `watch_menu`: `mode == "full"` -> `watch_full`, like `watch_confirm` (guard set first, unreadable SelectedIndex -> nothing, write Cancel at the
  end) but with `talk_menu.full_pick(sel, #m.full)`:
  - `release`: generation unchanged -> log `confirmed (release <member>)`, then `pcall(act_full, row, member)`; changed -> `dropped (the roster changed)`.
  - `cancel`: log `cancelled`.
- `act_full(row, member)`: re-check `roster.find(store.roster, member.offline_id)` is still `AWAY` (else notify `labels.refused("release",
  member.name, "not_adopted")` and stop); find the view (`view_by_id(row.offline_id)`, else notify refused adopt `not_in_party` and stop,
  **before** releasing); `store:release(member.offline_id)` (on failure notify `labels.refused("release", member.name, err)` and stop);
  then `store:adopt(view)` (on failure notify `labels.refused("adopt", row.name, err)`). Log lines through `line()` for each.
- The nextNode guard for the sub-menu applies unchanged to `full` mode (any index but Cancel becomes Cancel).
- Update the module header comment for the new mode.

Docs:

- `spec.md` § Adopt and Release (native): replace the **Retinue full** bullet with the decided flow (no dialog; the Talk sub-menu; one row per
  away member, Lv from the backup; picking one releases and adopts; Cancel; full with no away member is refused). In the **Adopt** bullet,
  `full` refuses only when no member is away.
- `docs/testing.md` check 13: the sub-menu instead of the dialog: "Release Folken (away, Lv 28)" and Cancel; Cancel changes nothing and
  returns to the root; again, pick Folken: Folken's member gone, backup gone or 0 bytes, the new pawn adopted, the root shows its Release row.
  Add: no movement or attack on the picks (pad A and F).
- Ticket 25: second criterion reworded to the one-step pick (keep the checkbox unticked); a comment line with the decision (2026-11-08, the user).

**Acceptance criteria**:
- [ ] `away_members`, `refusal` (both results), `full_pick`, `release_away` unit-tested, including level nil, one and two away members, a
      `returning` member excluded, full with no away -> `"full"`, CAP not full -> no `away`.
- [ ] Glue test scenarios: full with one away member (row 0 relabelled, row 1 removed, Cancel shown second; the member pick releases then
      adopts, writes 2); two away members (rows 0 and 1 relabelled, 3 rows; picking row 1 releases the second); Cancel (nothing acted,
      writes 2); full with no away (refused, nothing written, notice); the roster changed before the pick (dropped, writes 2); the nextNode
      guard on a failed write in full mode; the member not away any more at the pick (no release, notice); adopt fails after release (notice).
- [ ] Ticket 24 behaviour unchanged: every existing test passes untouched (edits only if a shared helper's signature must change).
- [ ] Spec, checklist 13 and ticket 25 updated as above.

**Verify**: `tests/run.sh` (all PASS). `luac5.4 -p` on every changed `.lua` if available.

**Out of scope**: the mod menu (it already has Release per away member), notices beyond the refusals listed, the Previous Hires and status
marks, any dialog code, gear.

## Slice 2: In-game run (checklist 13)

Headless, by the peer session `dd2-own-pawns-ee` (gamescope, XTEST keys). Then the user's feel pass (pad A on the member row, the cursor, B
on Cancel). Results go into ticket 25's comments and findings 0007 § Follow-up.
