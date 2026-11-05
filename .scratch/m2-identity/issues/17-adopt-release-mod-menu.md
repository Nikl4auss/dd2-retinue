# 17: Adopt and release from the mod menu; only adopted pawns progress

Parent: [M2 spec](../spec.md) (§ Identity, § Roster file, § Progression (M1 narrowed), § Mod menu)

**What to build:** the player can adopt a hired party pawn and release a member from the *Retinue* menu, with an inline confirm. The
roster is stored per save slot. Only present adopted pawns progress; ordinary hired pawns are vanilla again. A damaged
roster locks, a newer one is read-only, and an unknown slot means no roster.

**Blocked by:** [16: The mod knows which save slot is loaded](16-save-slot-known.md)

**Status:** ready-for-agent

- [ ] Pure `roster` module with tests: resolve/merge (structural errors lock, soft errors corrected per field, higher version read-only, unknown keys kept), operations adopt / release / refresh cache, errors `full`, `already_adopted`, `locked`, `read_only`, `no_offline_id`; the cap 2 is one constant.
- [ ] Adoptable = party slot 1–2, owner `CAPCOM`, non-nil non-zero `_OfflineID`; identity by OfflineID only, CharacterID a cache.
- [ ] Ambiguous member (two party pawns with its OfflineID): excluded, one warning.
- [ ] Roster read when a unit becomes active, written on every change; never written while locked or read-only; nothing when the slot is unknown. Missing file → empty, created on first adopt.
- [ ] The M1 target predicate is replaced: present, non-ambiguous members of the active roster; locked or unknown slot → none.
- [ ] Menu: slot and roster state (ok / locked: reason / read-only), one line per member, Adopt per party pawn and Release per member with an inline confirm; errors shown with their reason.
- [ ] Verified in game: adopt one of two hired pawns; in a fight only it levels; release it: it keeps its level and stops levelling; a `not json` roster locks with the reason and is left untouched.
