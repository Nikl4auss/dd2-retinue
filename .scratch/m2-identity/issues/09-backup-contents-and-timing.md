# What does a pawn's backup hold, and when is it written?

Type: grilling
Status: resolved
Blocked by: 07

## Question

Per "Run the dismiss / lost / re-hire experiment in game", the game keeps no progress past dismiss or lost, a re-hired
pawn returns at its first-hire level with regenerated equipment, and lost has no reliable last-read hook. Decide:
which fields the backup holds (level, exp, discipline, per-vocation ranks and culmative exp, current vocation,
equipment, skills, anything for display), when it is written (on save, on level-up, on a timer, at `dismissPawn` pre),
where it lives relative to the roster file, and what is restored versus only shown. Whether writing these into a
re-hired pawn's contexts stays within ADR 0001 or needs a new ADR is part of the question.

## Answer

Resolved 2026-11-04 (grilling); every recommendation accepted. Key fact from the il2cpp dump: per-level stat growth is
stored, not derived from `_Level`: `HumanStatusContext._IncreaseParams` (`app.IncreaseStatus`: `_HitPoint`, `_Stamina`,
`_Attack`, `_Defence`, `_MagicAttack`, `_MagicDefence`, `_Blow`, `_Weight`). Restoring the level alone would give a
Lv 27 pawn Lv 23 stats.

- **Restored**: `HumanStatusContext` `_Level`, `_Exp`, `_IncreaseParams` (all eight values), `_AcquiredExtraStatusBoost`;
  `JobContext` `ConsumableExp` (discipline) and the whole `CulmativeExp` array (all vocations; ranks derive from it).
- **Stored for verification only**: `CurrentJob`, `QualifiedJobBits`, `ChangedJobBits` (no vocation change in M2: the
  pawn returns with its own).
- **Equipment: recorded, never restored.** Equipped item IDs are kept for display and the log; the mod never creates
  items (duplication risk). The player re-equips from storage.
- **Skills: recorded, never restored.** Equipped skills per vocation are kept; they come back from the Rift's
  generation data, so on Return they are only compared and a mismatch is logged. Stored now for M3.
- **Display data**: name, current vocation, level (and the item IDs above), so native roster status can show
  "Folken — away — Lv 27 Warrior" without reading the game. No timestamps (left to "Roster vs. save drift").
- **When written**: while present the game is the authority and the backup mirrors it.
  - first backup on **adopt**;
  - a **poll** every ~10 s while present reads the state and writes the file only if something changed (covers lost,
    which has no hook but leaves the record for minutes; avoids a write per kill);
  - a forced last read at **`dismissPawn` pre**;
  - **frozen** while away. No extra hooks on `checkLevelUp` or on save.
- **Where**: one file per member, `reframework/data/Retinue/backups/<offline_id>.json`, with its own `version`. A
  missing or damaged backup affects only that pawn (not restored, warning); it never locks the roster. Release deletes
  the file; orphan backups (no roster member) are ignored and never deleted automatically. Pure, tested module
  `src/autorun/Retinue/backup.lua` (serialise/validate), I/O in `Retinue.lua`, as with `roster.lua`.
- **When restored**: only on a Return seen at `hirePawn` post (the game always regenerates the pawn at its first-hire
  level there): the whole backup is applied. A pawn found in the party on load while the roster says away (e.g. a save
  from before the dismiss) is **not** restored: it becomes present, the save's state wins and the backup is refreshed.
  Guard: if at `hirePawn` the game's level is above the backup's, no restore and a warning.
- **ADR**: [0002](../../../docs/adr/0002-restore-writes-hired-pawn-contexts.md): restore writes a returned pawn's
  own hired-pawn contexts, only values the game itself could reach; consistent with ADR 0001.
- Glossary: `CONTEXT.md` gains **Backup** and **Restore**.
- To verify in "Can a backup be written into a re-hired pawn?": that `_IncreaseParams` sticks and shows on the Status
  page (HP, stamina), and where equipment the player gave the pawn goes on dismiss and on lost.
