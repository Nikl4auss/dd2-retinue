# 25: A full retinue offers to release an away member

Parent: [M2 spec](../spec.md) (§ Adopt and Release (native): Retinue full)

**What to build:** when the roster is full because a member is away and the player picks Adopt on a new pawn, the Talk sub-menu lists
each away member ("Release <name> (away, Lv N)") and Cancel; picking one releases it and adopts the new pawn.

**Blocked by:** [24: Adopt and Release from the pawn's talk menu](24-talk-menu-adopt-release.md)

**Status:** done

- [x] Lists every away member with its backup's level; Cancel changes nothing.
- [x] Picking a member row deletes the member and backup, then adopts (one step, no second confirmation).
- [x] Verified in game (checklist 13).

## Comments

- 2026-11-08, the user: no dialog (it leaks input); the choice is in the Talk sub-menu, one row per away member, and one pick releases and
  adopts. The second confirmation goes (a second sub-menu would need a second root pick).
- 2026-11-08, `725bbe9`, run 1 (headless, by the peer session). Setup: from the post-t24 state (Folken present, Diamonds hired, not a
  member), with the game closed, a fake away member "Ghost" was added to roster.json with a copy of Folken's backup at Lv 31. Results:
  - Diamonds' root shows "Adopt" 4th. The pick shows exactly "Release Ghost (away, Lv 31)" / Cancel. The cursor moves only between the
    two rows and B lands on Cancel.
  - Cancel returns to the root and leaves roster and backups byte-identical.
  - The member row: Ghost is gone and his backup emptied (0 bytes); Diamonds is present with `character_id`, backup written. The root
    shows "Release (Retinue · Lv 24)" at once. No movement.
  - No guard fired, no report line. Shaira (main pawn) shows no row.
  - Not reachable headless: full with no away member (needs a third hired pawn while both members are present).
  - Backup `20261108-115059-m2-t25-run1`. Saves were restored to `m2-t25-pre`, because Ghost is fake.
  - Left for the user's pass: the real route (dismiss, Rift hire), full with no away member, pad A, and the feel.
- 2026-11-08, `725bbe9`, manual pass by the user (real route: adopt the second pawn, dismiss Folken, Rift hire, pad and keyboard): all pass.
  Full with no away member (optional) not done: the code path is the ticket 24 `full` refusal, covered by the unit and glue tests.
  Ticket closed.
