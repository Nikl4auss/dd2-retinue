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
