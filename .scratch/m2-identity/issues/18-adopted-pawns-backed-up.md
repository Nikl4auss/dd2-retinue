# 18: Adopted pawns are backed up

Parent: [M2 spec](../spec.md) (§ Backups)

**What to build:** every present member has a backup file mirroring its progress: written on adopt, refreshed by a ~10 s poll only
when a value changed, deleted on release. Within a slot the save wins: a member below its backup lowers it.

**Blocked by:** [17: Adopt and release from the mod menu; only adopted pawns progress](17-adopt-release-mod-menu.md)

**Status:** resolved

- [x] Pure `backup` module with tests: serialise / validate, changed-or-not comparison, level-guard decision (equal / lower / higher).
- [x] Contents as the spec: restored fields (level, exp, all eight `_IncreaseParams`, extra boost, discipline, whole `CulmativeExp`), recorded-only fields (vocation bits, item IDs, skills per vocation), display fields.
- [x] One file per member under the slot's `backups/`, own `version`; written on adopt and by the poll (in the world, present members only); deleted on release; orphans ignored.
- [x] A missing or damaged backup affects only its pawn (warning), never locks the roster.
- [x] A present member below its backup (rollback): the poll lowers the backup, one warning with both levels.
- [x] Backups run with the progression toggle off; nothing written when locked, read-only or slot unknown.
- [x] Verified in game: level an adopted pawn, the file follows within ~10 s; 30 s idle, or a fight with no kill, leaves the file untouched.

## Comments

Done: `2864ed8` (pure `backup` module, backup note in the menu), `aa207d9` (`game/pawn_state`, `game/backup_store`,
`jsonfile.delete`, `tracker.in_world`, wiring), `a35d7f8` (final review). Plan: [../plan.md](../plan.md).

Decisions beyond the spec: a damaged, missing or newer backup of a present member is rewritten by the poll, an away or
returning member's stays untouched; a failed recorded-only read carries the last value, a failed restored-field read
writes nothing; a failed first backup does not undo the adopt; the poll waits a full interval after every roster reload
and on entering the world. "In the world" adds `get_FlowPhase() == Phase.InGame`.

In game (2026-11-06, user, slot 2, Alder): adopt writes the file, skills read as real names. `FlowPhase` stayed `InGame`
through 22 minutes of play and left it only on a load. Loading a manual save from before a level-up: `save has Lv 18,
backup had Lv 19 -> backup lowered, save wins`, once. Loading the autosave: the file followed to Lv 19 on the first poll, 11 s
after entering the world. No write from 01:33:55 to 01:44:16 (no change), then writes on the ~10 s cadence as exp changed. With the
toggle off the file still followed exp (4217 to 7477, banked), discipline and culmative exp stopped. Release: `(backup emptied)`, 0 bytes.

**REFramework has no working file delete here**: `os.remove` did not remove the file, the `fs.write` fallback ran.

Not run in game (stubbed REFramework only): locked, read-only and unknown slot write nothing; a damaged backup.
