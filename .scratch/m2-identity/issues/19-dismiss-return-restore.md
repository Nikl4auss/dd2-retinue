# 19: Dismiss and Return restore an adopted pawn's progress

Parent: [M2 spec](../spec.md) (§ Departure and Return)

**What to build:** dismissing a member marks it away with its last backup; hiring it again from the Rift by any route is a Return:
the member becomes `returning`, its backup is written into the re-hired pawn one frame later (with retries and the
level guard), and it becomes present again with its progress. The menu shows each member's status.

**Blocked by:** [18: Adopted pawns are backed up](18-adopted-pawns-backed-up.md)

**Status:** ready-for-agent

- [ ] `dismissPawn` pre forces a last backup read; `dismissPawn` post marks away only if the pawn really left the party; the CharacterID is kept.
- [ ] `hirePawn` post with an away member's OfflineID → `returning`, backup frozen; roster written.
- [ ] Restore one frame later, retried each frame up to ~10 s; writes and read-back as findings 0008 (`CulmativeExp` by 0-based index assignment). Success → present, cache set; timeout or mismatch → stays `returning`, warning.
- [ ] Level guard: restore when game level ≤ backup's; skip with a warning when greater (then the game wins).
- [ ] Runs with the toggle off; locked: nothing; read-only: no writes, no restore; ambiguous: excluded.
- [ ] One log line per transition (away with cause, returning, restored Lv a→b / skipped: guard, timeout).
- [ ] Verified in game (checklist 10, 12, 15): Folken Lv 28 dismissed and re-hired comes back at Lv 28 with identical Status page, through save, reload and relaunch.

## Comments

From ticket 18's final review:

- `backups.capture` writes unconditionally: the gates (writable roster, `PRESENT`, in `found`) live in `backups.poll`.
  The `dismissPawn` pre forced read needs those gates too (a read-only roster must not write): extract them into one
  function that both call.
- Until this ticket lands, dismissing and re-hiring a member lowers its backup (the pawn comes back present at its
  first-hire level and the poll follows it).

Implemented: `f6a9d10` (pure), `1d52e38` (glue), then the final review's fix. Plan: [../plan.md](../plan.md). In-game checks 10, 12 and 15 are pending,
so the ticket stays open.

Decisions beyond the spec: a Return with no usable backup becomes present with a warning (`skipped: no backup`) and the poll rewrites the
file; a read-back mismatch stays `returning` until the next load; a dismiss while `returning` goes away, backup untouched; a hire of a
member still `present` goes away (cause `hire`) then `returning`; no file I/O in the hooks: the update loop writes the dismiss snapshot.

Watch at check 10: the line `dismissed but still in the party` would mean the pawn leaves `_PartyPawnList` later than one frame after
`dismissPawn`. That is untested at one frame (earliest sample +0.3 s). The next hire still restores it, but until then the member stays present.
