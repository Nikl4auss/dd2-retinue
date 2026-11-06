# 18: Adopted pawns are backed up

Parent: [M2 spec](../spec.md) (§ Backups)

**What to build:** every present member has a backup file mirroring its progress: written on adopt, refreshed by a ~10 s poll only
when a value changed, deleted on release. Within a slot the save wins: a member below its backup lowers it.

**Blocked by:** [17: Adopt and release from the mod menu; only adopted pawns progress](17-adopt-release-mod-menu.md)

**Status:** ready-for-agent

- [ ] Pure `backup` module with tests: serialise / validate, changed-or-not comparison, level-guard decision (equal / lower / higher).
- [ ] Contents as the spec: restored fields (level, exp, all eight `_IncreaseParams`, extra boost, discipline, whole `CulmativeExp`), recorded-only fields (vocation bits, item IDs, skills per vocation), display fields.
- [ ] One file per member under the slot's `backups/`, own `version`; written on adopt and by the poll (in the world, present members only); deleted on release; orphans ignored.
- [ ] A missing or damaged backup affects only its pawn (warning), never locks the roster.
- [ ] A present member below its backup (rollback): the poll lowers the backup, one warning with both levels.
- [ ] Backups run with the progression toggle off; nothing written when locked, read-only or slot unknown.
- [ ] Verified in game: level an adopted pawn, the file follows within ~10 s; 30 s idle, or a fight with no kill, leaves the file untouched.
