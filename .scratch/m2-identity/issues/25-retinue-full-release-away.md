# 25: A full retinue offers to release an away member

Parent: [M2 spec](../spec.md) (§ Adopt and Release (native): Retinue full)

**What to build:** when the roster is full because a member is away and the player picks Adopt on a new pawn, the Talk sub-menu lists
each away member ("Release <name> (away, Lv N)") and Cancel; picking one releases it and adopts the new pawn.

**Blocked by:** [24: Adopt and Release from the pawn's talk menu](24-talk-menu-adopt-release.md)

**Status:** ready-for-agent

- [ ] Lists every away member with its backup's level; Cancel changes nothing.
- [ ] Picking a member row deletes the member and backup, then adopts (one step, no second confirmation).
- [ ] Verified in game (checklist 13).

## Comments

- 2026-11-08, the user: no dialog (it leaks input); the choice is in the Talk sub-menu, one row per away member, and one pick releases and
  adopts. The second confirmation goes (a second sub-menu would need a second root pick).
