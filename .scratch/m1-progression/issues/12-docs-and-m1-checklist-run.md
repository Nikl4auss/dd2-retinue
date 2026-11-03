# 12: Docs and M1 in-game checklist run

Parent: [M1 spec](../spec.md) (§ Compatibility, § Done when)

**What to build:** M1 is finished and documented. The README gets a compatibility note (exp already scaled by
Bestiary / SimpleDifficultyTweaks, mod-originated grants covered, do not combine with another mod that lifts the
hired-pawn exp gate) and an updated status. `CHANGELOG.md` gets an Unreleased → Added entry and the roadmap marks M1
done. Then the user and an agent run the M1 checklist in `docs/testing.md` together and record the results in a
findings note.

**Blocked by:** [09: Notifications name the hired pawn](09-notifications-name-hired-pawn.md),
[10: Toggle persists in `config.json`](10-toggle-persists-in-config.md),
[11: Menu status line](11-menu-status-line.md)

**Status:** ready-for-human

- [ ] README compatibility note and status, CHANGELOG entry and roadmap updated. No version bump (0.1.0 = M1 + M2).
- [ ] Backup taken (`m1-checklist`), and the experiment script is not deployed.
- [ ] Every non-opportunistic checklist item passes. Each opportunistic item is recorded as passed or not reached.
- [ ] A findings note with probe snapshots under the findings data folder. Any failure becomes a new ticket, not a
      silent fix.
