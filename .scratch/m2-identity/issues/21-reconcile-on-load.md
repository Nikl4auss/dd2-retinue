# 21: The roster reconciles with the loaded save

Parent: [M2 spec](../spec.md) (§ Reconciliation on load)

**What to build:** on entering the world after each load, the mod runs one reconciliation pass that brings the roster in line with
the loaded party, including a Return made while the mod was not installed (recognised by a new CharacterID).

**Blocked by:** [19: Dismiss and Return restore an adopted pawn's progress](19-dismiss-return-restore.md)

**Status:** ready-for-agent

- [x] Pure `reconcile` module with a test per table row of the spec, including the kept-CharacterID discriminator (same → present, save wins; different or none → `returning` and restore under the guard).
- [x] One pass per load, on entering the world, before the party diff and the poll act.
- [x] Switching slots in one session cancels the previous slot's pending work without writing to it.
- [x] Read-only: in memory only; locked: no pass; slot unknown: none. One log line per correction.
- [x] Verified in game (checklist 19, 20): rollback keeps the save's level; each hand-edited roster case gives the expected result.

## Comments

From ticket 18's final review: the reconciliation row present / in party has no CharacterID discriminator. A member
dismissed and re-hired with the mod removed comes back on reinstall as present at its first-hire level, and the poll lowers
its backup. Compare the CharacterID there, as the away rows do.

From ticket 19's in-game run: **a re-hire can keep the same CharacterID** (Folken: 1601809365 before the dismiss and after the re-hire, check 12). So "away, in
party, same CharacterID → rollback, present, no restore" is not safe alone: a Return made with the mod absent that lands on the same ID would read as a
rollback and stay at its first-hire level. Find a better discriminator before building that row, or compare levels too (a pawn at or below the first-hire
state with exp 0 and a higher backup).

From ticket 20: a false away (a member in the party, marked away by the diff during a temporary absence) stays away for the session; this ticket's row
"away, in party, same CharacterID → present" is its only repair.

Decisions beyond the spec (plan: [plan.md](../plan.md)):

- **The discriminator is the hire time**, not the CharacterID: `SubPawnDataContext._HireTime`, kept in the backup as integer milliseconds (recorded, never restored, frozen while away). A different hire time than the backup's means a
  re-hire (`returning`); an equal one means the same hire, and the save wins. Not "later": a false Return only gives a pawn its backup back, a false rollback lowers the backup for good. The CharacterID rule and the
  first-hire signature (exp 0, discipline 0, behind the backup) are the fallback when either hire time is unknown (backups written before this ticket, an unreadable context).
- **The present row uses the same test** (ticket 18's comment): a present member that was re-hired unseen goes `returning`, so the poll never lowers its backup. A present member with no hire times and no kept CharacterID stays present.
- **Gate**: the pass runs once per generation, after the game left the world since the generation changed (or after a 20 s grace) and after 3 s in the world with a complete party read. Until then the hook events, the party diff,
  the restore attempts, the backup poll and the cache refresh wait (the refresh would overwrite the kept CharacterID the fallback compares). This also covers a load requested from inside the world (not the pause menu: the game has no load there, per the user), where the old party is still in the list.
- **Equal hire times are not proof of "save wins"**: after an unseen Return the restore writes the new hire time onto a backup holding restored progress, while the disk save still has that hire at first-hire level until the next game
  save. The backup therefore records `restored_from` (the game's level the last restore started from); on equal times a save at or below it and behind the backup (lower level, or equal level with less exp) is a Return, else the first-hire signature decides.
- **A queued dismiss is left to the dismiss**: the events are collected before the gate check and the pass skips every member with a queued dismiss, so the dismiss logs its own cause after the pass. Its snapshot is dropped: taken before the pass, it may be a save that predates a restore, and storing it would lower the backup for good.
- **The backup is written right after a restore**, so the hire time and the floor are on disk for a load before the next poll.
- A failed pawn read for a member does not hold the pass (its level, exp and hire time count as unknown, reported), but with the CharacterID it kept it gets no correction: nothing proves a rollback or a re-hire, and a false rollback lowers the backup. A failed pass still releases the hold. Ambiguous members get no correction. One roster write per pass.
- Ticket 20's false away (a member marked away by the diff during a temporary absence) is repaired by the `away, in party, same hire time → present` row, as that ticket's comment expected.
- Open for the in-game run: whether a re-hire that keeps its CharacterID changes `_HireTime` (the design assumes it does; check 29b records it).

Commits: `45e1471` (pure), `fd0126b` (the pass in the game), then the final review's fixes. Plan: [../plan.md](../plan.md).

In game (2026-11-06, user, Slot 2, `m2-adopted-folken`), check 19: passed. Grant exp to Lv 30, then back to the title and load (no load in the pause menu). `in the world: yes` at 17:51:18.444,
`Folken: save has Lv 28, backup had Lv 30 -> backup lowered, save wins` at 17:51:31.685 (13.2 s: 3 s settle plus the 10 s poll), no `roster ...` line, roster `present`, backup Lv 28.
First reading of `hire_time` from the game: 37991999, the fixture's `_HireTime` in ms, written and verified through JSON with no write error.

Check 20a (same run conditions, roster hand-edited to `away`, CharacterID kept, backup without `hire_time`): passed. `in the world: yes` at 20:52:10.287, `Folken: roster away, save has it Lv28 (backup Lv28) → present, save wins` at 20:52:13.313 (3.03 s), no `restored` line, roster `present`, backup Lv 28 with `hire_time` 37991999 written by the poll at 20:52:23.

Check 20b (roster `away` with another `character_id`, backup without `hire_time`): passed. `in the world: yes` at 21:18:44.720, `Folken: roster away, save has it Lv28 (backup Lv28) → returning, re-hired unseen` at 21:18:47.796, `Folken: returning→present restored Lv 28→28` 12 ms later. Roster `present` with the real `character_id` 1601809365; backup written at once by the restore (21:18:47.810) with `hire_time` 37991999 and `restored_from` 28.

Check 20c (roster `returning`, CharacterID kept; run by another Claude session with the user's go-ahead, without the user; log, roster and backup re-read here): passed. `in the world: yes` at 21:30:33.296, `Folken: returning→present restored Lv 28→28` at 21:30:36.346 (3.05 s), no `Folken: roster ...` line, roster `present`, backup written at 21:30:36 at Lv 28 with `restored_from` 28. The game was ended with SIGTERM from a server-error dialog that ignored the window close; no save was written (`data00-1.bin` still 08:37:24).

Check 20d (Folken dismissed at the Rift with the mod removed, saved, mod reinstalled, roster still `present`): passed. `in the world: yes` at 21:55:27.896, `Folken: roster present, not in the save's party (backup Lv28) → away, backup kept` at 21:55:30.919 (3.02 s), no `restored` line, roster `away` (written 21:55:30), backup file untouched at Lv 28.

Check 20e (roster `present`, `hire_time` in the backup changed by hand; run by another Claude session, without the user; log, roster, backup and saves re-read here): passed. First run wrote `hire_time` 37991999 by the poll, no save made (the same hire in the disk save, so the step is equivalent); backup edited to 11111111 with the game closed. `in the world: yes` at 22:03:22.531, `Folken: roster present, save has it Lv28 (backup Lv28) → returning, re-hired unseen` at 22:03:25.548 (3.02 s), `Folken: returning→present restored Lv 28→28` at 22:03:25.558. Roster `present`, `character_id` 1601809365; backup written at 22:03:25 at Lv 28 with the game's `hire_time` 37991999 and `restored_from` 28.

Check 20 complete. Open before resolving: 29 and 29b, the only real re-hire, which records whether a re-hire changes `_HireTime` (the design's assumption; 20e faked it by hand).

Check 29 (run by another Claude session, the re-hire included, with two pointers from the user; log, roster and backup of step 9 re-read here, output in `docs/findings/data/2026-11-06-m2-load-checks/`): log and files passed, one question open. Shortcut: `20261106-215809-pre-restore` (the 20d save, Folken dismissed **without** the mod, roster `away`) with `hire_time` 37991999 added to the backup by hand. Real re-hire with the mod removed (Lv 23), saved, state kept as `20261106-225612-m2-folken-rehired-lv23`.

- Load (`in the world: yes` 22:58:54.844): `Folken: roster away, save has it Lv23 (backup Lv28) → returning, re-hired unseen` at 22:58:57.849, `restored Lv 23→28` at 22:58:57.857, roster `present`, backup Lv 28 with `restored_from` 23.
- Same save again, by relaunch instead of the title, nothing saved (`in the world: yes` 23:02:15.439): `Folken: roster present, save has it Lv23 (backup Lv28) → returning, re-hired unseen`, `restored Lv 23→28`, backup still Lv 28. The `restored_from` floor works on the real case.
- 29b: `hire_time` 37991999 → 39611074, `character_id` 1601809365 → 372209474. This re-hire did **not** keep its CharacterID, so the case the check asks about (same ID) was not observed; a new hire time is confirmed only for a new ID. If a same-ID re-hire kept its time, the first-hire signature still catches it.

**Open:** the HUD shows Folken Lv.28 with 1722 health after the restore on load, the Lv 23 value (1838 at Lv 28 in check 20c). Not known yet whether only the live HP is stale until the next load, or the restore misses something on this path. Findings 0008 and check 12 saw the Status page match, but on the `hirePawn` path. No snapshot taken, so "equals `m2-a`" is unchecked. Stays open until a save and reload settles it.
