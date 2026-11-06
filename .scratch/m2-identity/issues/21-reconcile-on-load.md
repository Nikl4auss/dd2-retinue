# 21: The roster reconciles with the loaded save

Parent: [M2 spec](../spec.md) (§ Reconciliation on load)

**What to build:** on entering the world after each load, the mod runs one reconciliation pass that brings the roster in line with
the loaded party, including a Return made while the mod was not installed (recognised by a new CharacterID).

**Blocked by:** [19: Dismiss and Return restore an adopted pawn's progress](19-dismiss-return-restore.md)

**Status:** ready-for-agent

- [ ] Pure `reconcile` module with a test per table row of the spec, including the kept-CharacterID discriminator (same → present, save wins; different or none → `returning` and restore under the guard).
- [ ] One pass per load, on entering the world, before the party diff and the poll act.
- [ ] Switching slots in one session cancels the previous slot's pending work without writing to it.
- [ ] Read-only: in memory only; locked: no pass; slot unknown: none. One log line per correction.
- [ ] Verified in game (checklist 19, 20): rollback keeps the save's level; each hand-edited roster case gives the expected result.

## Comments

From ticket 18's final review: the reconciliation row present / in party has no CharacterID discriminator. A member
dismissed and re-hired with the mod removed comes back on reinstall as present at its first-hire level, and the poll lowers
its backup. Compare the CharacterID there, as the away rows do.

From ticket 19's in-game run: **a re-hire can keep the same CharacterID** (Folken: 1601809365 before the dismiss and after the re-hire, check 12). So "away, in
party, same CharacterID → rollback, present, no restore" is not safe alone: a Return made with the mod absent that lands on the same ID would read as a
rollback and stay at its first-hire level. Find a better discriminator before building that row, or compare levels too (a pawn at or below the first-hire
state with exp 0 and a higher backup).
