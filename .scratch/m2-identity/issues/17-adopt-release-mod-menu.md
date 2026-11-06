# 17: Adopt and release from the mod menu; only adopted pawns progress

Parent: [M2 spec](../spec.md) (§ Identity, § Roster file, § Progression (M1 narrowed), § Mod menu)

**What to build:** the player can adopt a hired party pawn and release a member from the *Retinue* menu, with an inline confirm. The
roster is stored per save slot. Only present adopted pawns progress; ordinary hired pawns are vanilla again. A damaged
roster locks, a newer one is read-only, and an unknown slot means no roster.

**Blocked by:** [16: The mod knows which save slot is loaded](16-save-slot-known.md)

**Status:** resolved

- [x] Pure `roster` module with tests: resolve/merge (structural errors lock, soft errors corrected per field, higher version read-only, unknown keys kept), operations adopt / release / refresh cache, errors `full`, `already_adopted`, `locked`, `read_only`, `no_offline_id`; the cap 2 is one constant.
- [x] Adoptable = party slot 1–2, owner `CAPCOM`, non-nil non-zero `_OfflineID`; identity by OfflineID only, CharacterID a cache.
- [x] Ambiguous member (two party pawns with its OfflineID): excluded, one warning.
- [x] Roster read when a unit becomes active, written on every change; never written while locked or read-only; nothing when the slot is unknown. Missing file → empty, created on first adopt.
- [x] The M1 target predicate is replaced: present, non-ambiguous members of the active roster; locked or unknown slot → none.
- [x] Menu: slot and roster state (ok / locked: reason / read-only), one line per member, Adopt per party pawn and Release per member with an inline confirm; errors shown with their reason.
- [x] Verified in game: adopt one of two hired pawns; in a fight only it levels; release it: it keeps its level and stops levelling; a `not json` roster locks with the reason and is left untouched.

## Answer

Shipped in `aed2de0` (pure `roster.lua` + tests, narrowed `targets.build(views, roster, is_hired)`), `d91f37b`
(`game/jsonfile`, party views with cached Offline IDs, `game/roster_store`, `game/roster_menu`, wiring), `7156e2d`
(final-review nits) and `23aa697` (re-read the roster on every start/load request, not only on a unit change; level
shown next to adoptable pawns). Plan: [../plan.md](../plan.md).

Decisions beyond the spec: a missing `members` reads as empty (REFramework writes an empty array as `null`); a strict
read that cannot tell missing from damaged (no `fs.read`, or `fs.read` throws / returns nil) locks the roster; a
read-only roster reads members leniently (bad ones skipped, first `CAP` kept); glue-side errors `not_adopted`,
`no_slot`, `not_in_party`; targets still require `isSubPawn`.

In game (2026-11-05, user, slot 2): fresh slot → `Slot 2 · roster ok (0/2)` (so `fs.read` returns `""` for a missing
file); adopt one of two hired pawns → only it levels, the level-up notice names it; release → it keeps its level and
stops levelling, the file holds `"members": null`; `not json` roster → locked with the reason in menu and log, Adopt
answers `locked`, file byte-identical afterwards; title → reload slot 2 after restoring the file → `roster ok (0/2)`
without *Reset scripts*.
