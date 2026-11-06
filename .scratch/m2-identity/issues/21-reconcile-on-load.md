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
- [ ] Verified in game (checklist 19, 20): rollback keeps the save's level; each hand-edited roster case gives the expected result.

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
