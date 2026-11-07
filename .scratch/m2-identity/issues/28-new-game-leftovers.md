# 28: New game leftovers: Start from Beginning, NG+ with a backup

Parent: [M2 spec](../spec.md) (§ Save slot (new playthrough, NG+))

**What to build:** settle what the two new-game paths left open by [ticket 22](22-new-game-archives-roster.md) do, and fix what
they show. All three are checks in game; only the first may need code.

**Blocked by:** [22: A new game archives the slot's roster; NG+ keeps it](22-new-game-archives-roster.md)

**Status:** needs-triage

- [ ] "Start from Beginning" on a cleared slot (new since findings 0010, offered after the difficulty choice): which `StartType`
  it sends. If `RedoNewGame`, the roster is archived at once: decide whether that is a new playthrough or the same one.
- [ ] NG+ with a member that has a valid backup: away, backup unchanged. Ticket 22's fixture read as damaged.
- [ ] A new game given up inside the session (back to the title, then a load): the line
  `slot: new game given up before its first save; the roster stays`. Closing the game was tested; this path was not, because
  going back to the title by keys is unproven. Covered by `tests/slot_test.lua`.

## Comments

- Each is a test on a backup: the first two convert slot 1, the only cleared slot recorded. Fixtures CRLF, with `version`.
