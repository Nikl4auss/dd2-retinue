# 0006 — M2: what the game does to a hired pawn on dismiss, lost and re-hire

Date: 2026-11-03/04 · Ticket: [Run the dismiss / lost / re-hire experiment in game](../../.scratch/m2-identity/issues/04-run-lifecycle-experiment.md)
(step-by-step run log there) · Script: `tools/experiments/Retinue_Exp_Lifecycle.lua` at `8ab4ee1` · Research input:
`research-m2-dismiss-lost-rehire.md` (branch `research/m2-dismiss-lost-rehire`) · Run files (xz-compressed JSON):
[data/2026-11-03-m2-lifecycle/](data/2026-11-03-m2-lifecycle/)

Offline play, M1 mod active, deployed `--probe --lifecycle`. Party: main pawn Shaira (2283028347), hired Diamonds
(743846891, Mage) and **Folken** (CharacterID 1601809365, OfflineID `426f7888-0cc8-44a4-86b2-1ed445367596`, Warrior),
hired at Lv 23 and raised to **Lv 27** (exp 9610, discipline 1930, Warrior rank 6) with the panel's *Grant exp*; that
state is the fixture `fixture-levelled-pawn`, restored before each cycle.

## Procedure

| Step | What | Run file |
|---|---|---|
| b | Real dismiss of Folken in the Rift menu; save; title; reload | `b/` (first attempt flooded the log: `b-flooded/`) |
| c | From the post-dismiss save: re-hire Folken from the Rift's "previously hired" list; save; reload | `c/` |
| d | From the fixture: panel *Dismiss slot 3*; re-hire from the Rift | `d/` |
| e | From the fixture: Nick's Devtools *Kill pawns*; travel to a Rift stone; look for Folken | `e-kill/` |
| f | From the fixture: panel *Force lost slot 3* (`lost(id, false, false)`) | `f/` |

The planned timer and rest-sweep lost paths could not be set up: *Kill pawns* never leaves a downed pawn.

## Results

**Dismiss** (b, d: identical call chain, so the panel dismiss is a valid shortcut). All synchronous inside one
`PawnManager.dismissPawn(CharacterID)` → `dismissPawn(Pawn)`: `unregistPawn`, `ItemManager.returnSubPawnItems`,
`NPCManager.addStrayPawn_HireTime_DismissNotInstance` → `eventStrayPawnLost`, `Human.setDisableContextStoreOnDissmissPawn`,
`ContextDBMS.deleteRecord(CharacterID)`. **The record is gone when `dismissPawn` returns.** The `pre` of `dismissPawn`
still reads the full state (level, exp, discipline, ranks, culmative exp, equipped item IDs, skills).
`addStrayPawn_DisMissList` does **not** fire on dismiss.

**The "dismissed list" is the previously-hired list.** `NPCManager` `DisMiss` list (`getStrayPawn_DisMissList`) is written
by `addStrayPawn_DisMissList` right **before `hirePawn`**, with the pawn's generation data and its hire-time `Level`.
Folken's entry stayed at Lv 23 throughout. It survives save and reload. Limits: `StrayPawnPastInformationMax` = 100,
`RelationPawnDismissNum` = 30.

**Re-hire** (c, d). Folken is offered in the Rift's "previously hired" list at Lv 23 and comes back with:

| | Before dismiss | Re-hire (c) | Re-hire (d) |
|---|---|---|---|
| OfflineID | `426f7888…` | same | same |
| CharacterID | 1601809365 | 372209474 | 3147318785 |
| Level / exp / discipline | 27 / 9610 / 1930 | 23 / 0 / 0 | 23 / 0 / 0 |
| `SubPawnDataContext._HireTime` | 37991.99912477005 | 39276.41967765521 | 38927.32584851235 |
| Warrior rank (culmative exp) | 6 (11130) | 6 (9200) | 6 |
| Equipped item IDs | 3329, 6123, 5132, 1203 | 3311, 6122, 5007, 4019, 1203 | 3339, 6122, 5016, 1203 |

He is rebuilt by `StrayPawnFactory.preOrderFromRecord` → `makeRimSearchedOfflineProduct` from the list record; nothing
of the old record is restored (`restorePastInformation` / `restoreContextsToHolder` did not fire for him). **The
CharacterID is new and not deterministic; only the OfflineID is stable. Equipment is regenerated on each hire.** Right
after the hire the record lookups (`CharacterID2Keys`, `hasRecord`) are false; they turn true after a save. `IsRestore`
turns true after a reload.

`SubPawnDataContext._HireTime` marks one hire: Folken's is 37991.99912477005 in the fixture across every run and
reload, and each re-hire gets a new value; it survives save and reload to the last digit (c, reloaded). It is the
save's clock (c is larger than d though it ran earlier), so it rolls back with a rollback. Diamonds, never dismissed:
32135.22838183213 in all 12 files. Unknown: whether a re-hire that keeps its CharacterID changes it (no run recorded it).

**Lost via *Kill pawns*** (e). The whole party is removed at once. For each hired pawn: `returnSubPawnItems`,
`unregistPawn`, `SoundVoiceManager.onDismissUnloadPawnEvent`, `addStrayPawn_HireTime_DismissNotInstance` →
`eventStrayPawnLost`. **No `PawnManager.lost`, no lost timer, no `dismissPawn`, no `deleteRecord(CharacterID)`.** The
record **survives** the kill (read from ContextDBMS, Lv 27 intact) and was gone ~4.5 min later, while travelling to the
Rift; the deleting call was not identified (likely `deleteRecord(UniqueID)`, which the script caps as chatty). At the
stone `startRim` → `lostDeadPawns`; the main pawn returned, the hired pawns did not. Folken was then in the
"previously hired" list at Lv 23: **a lost pawn can be re-hired like a dismissed one, with the same loss**.
`returnSubPawnItems` returns carried items, not equipment (nothing came back).

**Panel `lost(id, false, false)`** (f). The call threw (`Invoke threw an exception`) after `returnSubPawnItems`; ~9 s
later `unregistPawn` removed Folken from the party with his record intact; ~58 s later `registPawn` brought him back with
the same CharacterID and Lv 27. A direct `lost` call leaves a half-done state: not usable as a shortcut.

## Conclusions

1. **Key the roster on OfflineID.** CharacterIDs can change on a re-hire (ticket 19 saw one keep it) (and are reused by other pawns, research 02).
2. **The game keeps no progress past dismiss or lost**; it re-offers the pawn at its first-hire level with regenerated
   equipment. The mod's backup is required and must hold level, exp, discipline, ranks/culmative exp and equipment.
3. **Timing**: on dismiss, `dismissPawn` pre is a reliable last read. On lost there is no single hook; the record lingers
   for an unknown time and then disappears. The backup must therefore be kept current while the pawn is in the party
   (e.g. on save, on level-up), not taken only at the departure event.
4. **Coming back** is native: the Rift's "previously hired" list, for both dismiss and lost. The mod recognises the
   pawn on `hirePawn` (post) by OfflineID; its record may not be queryable until the next save.
5. `pawnLost(Character)` / `pawnLost(InstanceInfo)` and `restorePastInformation` fire thousands of times without any
   lost or re-hire: not usable as event signals.

## Open

- A natural lost (downed in combat, timer runs out) and the rest sweep were not observed: opportunistic check for the M2
  checklist.
- Which call deletes a lost pawn's record, and when.
- Script bugs, not affecting the results: `world.lost_timers` read errors (`Retinue_Exp_Lifecycle.lua:247`), equipment
  `slots` decoding errors (`:448-449`; `item_ids` fine).
