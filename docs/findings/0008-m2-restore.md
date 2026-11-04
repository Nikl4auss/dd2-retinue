# 0008 — M2: writing a backup into a re-hired pawn

Date: 2026-11-04 · Ticket: [Can a backup be written into a re-hired pawn?](../../.scratch/m2-identity/issues/10-restore-experiment.md)
(step-by-step run log there) · Script: `tools/experiments/Retinue_Exp_Restore.lua` (built at `6ed1c2d`, array write fixed
during the run) · Decision it tests: [ADR 0002](../adr/0002-restore-writes-hired-pawn-contexts.md) · Run files
(xz-compressed JSON) and screenshots: [data/2026-11-04-m2-restore/](data/2026-11-04-m2-restore/)

Offline play, mod active, deployed `--probe --lifecycle --restore`. Fixture `fixture-levelled-pawn`: Folken (OfflineID
`426f7888-0cc8-44a4-86b2-1ed445367596`, Warrior), hired at Lv 23, raised to Lv 27 (exp 9610, discipline 1930, Warrior
culmative exp 11130, rank 6). Baseline Status page (base values): Health 1837, Stamina 855, Strength 239, Defense 170,
Magick 55, Magick Defense 44, Knockdown Power 46, Knockdown Res 400.

| Step | What | Data |
|---|---|---|
| 0 | Baseline screenshots | `0-baseline/` |
| a, b | Give a helmet from storage, capture, native dismiss (from the field), save | `b/` |
| c | Re-hire from the Rift with auto-restore one frame after `hirePawn` post; fix the array write in-session; save, reload, relaunch | `c/` |
| e | Mod and experiments unlinked; load, save, reload | (user report) |
| f | Fixture again; give the helmet, capture, Nick's Devtools *Kill pawns* | `f/` |

## Results

**The OfflineID is readable in `hirePawn` post** (and pre) from the hired Character's `PawnOwnerContext._OfflineID`. In
post the pawn already stands at its first-hire state (Lv 23, exp 0) with a new CharacterID, record lookups false.

**The restore works, written to the live contexts one frame after `hirePawn` post, before any record exists.**

| Field | Write | Result |
|---|---|---|
| `_Level`, `_Exp` | `set_Level`, `set_Exp` | read back equal |
| `_IncreaseParams` (8 values) | `set_field` on the existing object (`ReadOnly` was false) | read back equal |
| `_AcquiredExtraStatusBoost` | `setExtraStatusBoost` | equal (0) |
| `ConsumableExp` (discipline) | `set_ConsumableExpProp` | read back equal |
| `CulmativeExp` (Int32[]) | index assignment `arr[i] = v`, 0-based | read back equal |

Nothing was overwritten by the game at +1 s or +10 s. For the array, `arr:set_element` does not exist (REFramework
`SystemArray` has no such method) and `arr:call("SetValue", sdk.create_int32(v), i)` returns without changing the array;
index assignment works. The game-method fallback (`set_NowJobCulmativeExpProp` / `addJobExp`) was not reached, so it is
untested. The `setIncreaseParam(new object)` variant was not needed and is untested.

**The Status page matches the baseline exactly** (all base values above, Lv 27, Warrior rank 6): `_IncreaseParams` is what
the page shows, and restoring it gives the levelled stats. Totals differ only by equipment. Exp and discipline show "-"
for a hired pawn on the native pages. `calcMaxHp(job)` gives 1637.5 against the 1837 shown: not usable as a display check.

**Persistence**: the record became visible at the next save (`CharacterID2Keys` and `hasRecord` true), `IsRestore` turned
true at the reload. After save + reload, and after a full relaunch with no write in that session, the pawn compares equal
to the backup on every restored and verification field; only `item_ids` differ (regenerated equipment). **No save is
needed before the write.**

**Uninstall**: with nothing of Retinue linked, the save loads normally and the pawn keeps the restored level and Status
page through a save and reload. The restored pawn is an ordinary saved hired pawn (ADR 0001 and 0002 hold).

**Equipment the player gives a hired pawn is lost on dismiss and on lost.** Dismiss: `dismissPawn` pre →
`returnSubPawnItems` → `removeEquipData` → posts, no storage hook fires; `getHaveAllNum` drops from 1 to 0 for every
equipped item (including the given helmet) within 1 s. *Kill pawns*: the same `returnSubPawnItems` + `removeEquipData` at
the kill, for both hired pawns, before reaching a Rift; the helmet is nowhere. This matches the game's own warning when
equipping a hired pawn (the gear goes to its owner). In the lost case the pawn left the party at the kill.

## Conclusions

1. Restore as decided in ADR 0002 is feasible: on a Return, one frame after `hirePawn` post, write the backup into the live
   `HumanStatusContext` and `JobContext`; the next save stores it. No waiting for a save, no record writes.
2. Write `CulmativeExp` by index assignment and verify by read-back; the other fields through the setters above.
3. Gear given to an adopted pawn is lost on dismiss and on lost, like for any hired pawn. The mod does not restore
   equipment (ADR 0002); whether the player should be warned is a UX question for native roster status.

## Open

- `setIncreaseParam(new object)` and the game-method `CulmativeExp` path are untested (not needed).
- Natural lost (down timer, rest sweep) still not observed; *Kill pawns* only.
