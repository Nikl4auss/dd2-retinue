# 25: A full retinue offers to release an away member

Parent: [M2 spec](../spec.md) (§ Adopt and Release (native): Retinue full)

**What to build:** when the roster is full because a member is away and the player picks Adopt on a new pawn, a dialog lists each
away member ("Release <name> (away, Lv N)") and Cancel; choosing one and confirming releases it and adopts the new
pawn.

**Blocked by:** [24: Adopt and Release from the pawn's talk menu](24-talk-menu-adopt-release.md)

**Status:** ready-for-agent

- [ ] Lists every away member with its backup's level; Cancel changes nothing.
- [ ] Second confirmation "Release <name>? Their progress will be lost."; Yes deletes the member and backup, then adopts.
- [ ] Verified in game (checklist 13).
