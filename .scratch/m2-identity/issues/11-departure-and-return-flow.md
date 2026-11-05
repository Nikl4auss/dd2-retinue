# How does the mod notice a member leaving and returning, and when does it act?

Type: grilling
Status: resolved
Blocked by: 10

## Question

Per "Can a backup be written into a re-hired pawn?" the restore itself is settled: one frame after `hirePawn` post,
into the live contexts, no save needed. Per "Run the dismiss / lost / re-hire experiment in game", dismiss has a reliable
`dismissPawn` pre, while lost has no single hook (with *Kill pawns*, `returnSubPawnItems` + `removeEquipData` fire at the
kill and the pawn leaves the party; the record lingers for minutes). Decide the mod's member status transitions and their
triggers: how a present member becomes away (dismiss hook; lost by a party diff in the 10 s poll, by
`returnSubPawnItems`/`removeEquipData`, or both), what the last backup read is in the lost case, how a Return is detected
and applied (the `hirePawn` post path, retries if the actor or contexts are not ready, the level guard), and what the mod
logs or shows at each step. The load-time case already decided in "What does a pawn's backup hold, and when is it
written?" (present in the save while the roster says away → present, no restore) stays as is.

## Answer

Resolved 2026-11-04 (grilling); every recommendation accepted. Builds on "What identifies an adopted pawn across dismiss
and re-hire?", "What does a pawn's backup hold, and when is it written?" and "Can a backup be written into a re-hired
pawn?".

- **Member status** gains a third value: `present`, `away`, `returning` (persisted in the roster).
- **Dismiss**: `dismissPawn` pre forces the last backup read; `dismissPawn` post marks the member away (CharacterID
  cache cleared, roster written) only if the pawn is really gone from the party, so a failed dismiss leaves no lie.
- **Any departure (lost and unknown causes)**: a **party diff** every ~1 s compares the OfflineIDs in slots 1–2 with
  the present members. A present member missing from the party for **3 consecutive checks**, checked only while in the
  world (main pawn present; not loading, not at the title), becomes away. No hook on `returnSubPawnItems` /
  `removeEquipData` (they also fire on dismiss; arguments unknown). The 10 s backup poll is separate.
- **Last backup on lost**: the last 10 s poll; up to ~10 s of progress (even a level-up) can be lost. Known limit,
  documented; no read from the lingering ContextDBMS record.
- **Return**: `hirePawn` post with an away member's OfflineID → member becomes **returning**: backup frozen, the poll
  never writes it. The restore runs one frame later and is retried every frame for up to ~10 s if the actor or contexts
  are not ready. Success → present, CharacterID cache set, the poll mirrors the game again. Timeout → stays `returning`
  in the roster, warning, retried on the next save load (same guard).
- **Level guard**: restore when the game's level ≤ the backup's (equal level still restores exp, discipline, vocation
  exp); skip when greater, with a warning; then the game wins and the poll overwrites the backup.
- **On load**: away in the roster but in the party → present, no restore (unchanged); present in the roster but not in
  the party (e.g. dismissed with the mod off) → away with its last backup; `returning` → retry the restore. Odd cases
  from older saves belong to "Roster vs. save drift".
- **Which states track transitions**: independent of the `progression` toggle (transitions and backups run with it
  off). Locked roster: nothing tracked or written. Read-only roster: nothing written (no roster, no backups), so no
  restore, warning in the log. Ambiguous member: excluded.
- **Feedback**: one log line per transition (present→away with cause dismiss/absence, away→returning,
  returning→present with "restored Lv a→b" or "skipped: guard", retry timeout), via `log.error` like the rest of the
  mod. Native messages are decided with native roster status.
- Glossary: `CONTEXT.md` gains **Returning** under Adopted pawn.

**Revised 2026-11-05** by "How is the uninstall guarantee verified for adopted and away pawns?": an away member keeps its
last `character_id` (not cleared on dismiss); on load, away in the roster and in the party with a different CharacterID
→ `returning` and restored under the level guard (a Return the mod did not see); same CharacterID → present, no restore.
