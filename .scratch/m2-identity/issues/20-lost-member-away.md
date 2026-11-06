# 20: A lost member becomes away

Parent: [M2 spec](../spec.md) (§ Departure and Return (any other departure))

**What to build:** a member that leaves the party without a dismiss (lost, or any other cause) becomes away, detected by a party
check every ~1 s in the world; its backup is the last poll.

**Blocked by:** [19: Dismiss and Return restore an adopted pawn's progress](19-dismiss-return-restore.md)

**Status:** ready-for-agent

- [x] Pure tests of the miss counter: 3 consecutive misses → away; a reappearance resets; no counting outside the world.
- [x] Diff compares party slots 1–2 OfflineIDs with present members; independent of the toggle.
- [x] Log line `present→away (absence)`.
- [ ] Verified in game (checklist 14): *Kill pawns* until Folken leaves; away within ~3 s; re-hire restores him.

## Comments

Implemented (pending check 14). Plan: [../plan.md](../plan.md).

Decisions beyond the spec: leaving the world drops the counts; the first check is a full second after entering it; an incomplete party read
holds the diff (a zero GUID is a complete read); a false away is not repaired within the session, ticket 21 repairs it on the next load.

Gates for closing this ticket, from the run files: going to the title, hired pawns leave the party 5.6 to 8.7 s before the main pawn, and the data does
not show whether `FlowPhase` has left `InGame` by then. Check 14's "No false absence" settles it. If it fails, add a guard here before closing.

From the final review, unverified: `PawnManager.keepPartyPawn`, `comebackPartyPawn` and `standbyPartyPawn` exist in the dump and no doc mentions them. If one takes
hired pawns out of `_PartyPawnList` with the main pawn still there, that is a false away. A diff held by an unreadable party logs nothing.
