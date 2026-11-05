# 20: A lost member becomes away

Parent: [M2 spec](../spec.md) (§ Departure and Return (any other departure))

**What to build:** a member that leaves the party without a dismiss (lost, or any other cause) becomes away, detected by a party
check every ~1 s in the world; its backup is the last poll.

**Blocked by:** [19: Dismiss and Return restore an adopted pawn's progress](19-dismiss-return-restore.md)

**Status:** ready-for-agent

- [ ] Pure tests of the miss counter: 3 consecutive misses → away; a reappearance resets; no counting outside the world.
- [ ] Diff compares party slots 1–2 OfflineIDs with present members; independent of the toggle.
- [ ] Log line `present→away (absence)`.
- [ ] Verified in game (checklist 14): *Kill pawns* until Folken leaves; away within ~3 s; re-hire restores him.
