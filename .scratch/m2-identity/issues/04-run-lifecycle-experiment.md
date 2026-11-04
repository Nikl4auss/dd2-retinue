# Run the dismiss / lost / re-hire experiment in game

Type: task
Status: resolved
Blocked by: 03

## Question

With the M1 mod active and a hired pawn levelled past its Rift level: dismiss it and re-hire it; let a pawn be lost;
save/load between steps. Answer, with data: is the re-hired pawn recognised by `_OfflineID` (same or new
CharacterID)? Which state survives (level, exp, discipline, vocation ranks, equipment) and which is lost?
Does a lost pawn ever come back? `tools/saves.sh backup <label>` first; findings note after.

## Run log

- Step 0 (2026-11-03): backup `m2-lifecycle-start`, deployed `--probe --lifecycle`; all hooks installed, pawn data visible.
- Step 1 (a): pawn **Folken**, CharacterID 1601809365, OfflineID `426f7888`, Warrior (5), party slot 3.
  Lv 23 (exp 210) → Lv 27 via Grant exp. Snapshot `a-levelled`, saved, backup `fixture-levelled-pawn`.
- Step 2 (b): real dismiss of Folken through the Rift menu. Snapshot labels: `b0-before-dismiss` before touching the
  stone; the post-dismiss snapshot was **also labelled b0** (take the later one, or `auto:dismiss`), then `b2-saved`,
  `b3-after-reload`. On screen: no item-return message, nothing odd. Live table after dismiss and after reload:
  Folken "record gone"; dismissed list count 7.
- **Run files of steps 1–2 are unusable for the dismiss** (`docs/findings/data/2026-11-03-m2-lifecycle/b-flooded/`, 21 MB each before xz):
  at load `StrayPawnFactoryProductOffline.restorePastInformation` filled the 20000-call cap in ~6 s (pre+post, not
  capped per hook), and a lost-group hook fired an `auto:lost` snapshot ~10/s, filling the 400-snapshot cap within
  ~40 s of load. Every later call and every manual snapshot (incl. the dismiss) was dropped. Step 2 must be redone
  from `fixture-levelled-pawn` after a script fix.
- Salvaged facts: `StrayPawnPastInformationMax` = 100, `RelationPawnDismissNum` = 30. The dismissed list held 7 entries
  *before* the step-2 dismiss, Folken already among them at **Level 23** while he was hired at Lv 23–27 (a past
  dismissal of him; his entry's `CharaID` 1857826560 is the same for all 7 entries, probably not a real id).
- **Step 2 redo (b)**, run file `docs/findings/data/2026-11-03-m2-lifecycle/b/lifecycle_20261103_234211.json.xz` (caps held:
  12.7k logged, manual snapshots `b0`×2, `b1-after-dismiss`, `b2-saved`, `b3-after-reload`). Real Rift dismiss of Folken:
  - Call chain, all synchronous inside one `dismissPawn(CharacterID)` → `dismissPawn(Pawn)`: `unregistPawn`,
    `ItemManager.returnSubPawnItems`, `NPCManager.addStrayPawn_HireTime_DismissNotInstance` (→ `eventStrayPawnLost`),
    `Human.setDisableContextStoreOnDissmissPawn`, `ContextDBMS.deleteRecord(CharacterID)`. **The record is deleted inside
    dismissPawn** (by_charid/by_uniqid false from the `auto:dismiss` snapshot on). Items were returned (call fired) though
    no message showed.
  - **`addStrayPawn_DisMissList` did NOT fire on dismiss.** The dismissed list stayed at 7 entries with Folken at
    **Level 23** (his level when hired), unchanged after save and reload. So that list is not updated with the current
    level on dismiss; it may be filled at hire time.
  - The `pre` of dismissPawn captured the full state (Lv 27, exp 9610, discipline 1930, Warrior rank 6, culmative exp,
    4 equipped item IDs, skills). Bug: equipment `slots` decoding errors (`sd` nil at Lv:448-449); `item_ids` fine.
  - Flood sources (calls seen): `restorePastInformation` 137k, `pawnLost(Character)`/`(InstanceInfo)` 8.6k each with
    no pawn lost (a per-frame check, not the lost event), `deleteRecord(UniqueID)` 1.6k, `restoreContextsToHolder` 1.5k.
- **Step 3 (c)**, run file `docs/findings/data/2026-11-03-m2-lifecycle/c/lifecycle_20261103_235903.json.xz` (data dir
  dated 11-04: copied after midnight). Restored the newest `m2-after-dismiss`; Folken found in the Rift's
  "previously hired" list, shown at **Lv 23** before and after hiring. Re-hired:
  - **Same OfflineID `426f7888`, new CharacterID 372209474** (was 1601809365). `getUnusedOfflineCharacterID` returned the
    new id; built by `StrayPawnFactory.preOrderFromRecord` → `makeRimSearchedOfflineProduct` from the list record
    (`Level` 23, `Job` 5). `restorePastInformation`/`restoreContextsToHolder` did not fire for him.
  - **`addStrayPawn_DisMissList` fires right before `hirePawn`** (not on dismiss): the "dismissed list" is the game's
    previously-hired list, written at hire time with the hire-time level.
  - State on arrival: **Lv 23, exp 0, discipline 0**, Warrior rank 6 (ranks `[1,1,1,1,6,1,…]`, culmative Warrior 9200 vs
    11130 before dismiss), **different equipment** (item IDs 3311, 6122, 5007, 4019, 1203 vs 3329, 6123, 5132, 1203 before):
    generation data, not what he had. All progress since hire is lost; confirms the backup is required.
  - Record lookup: `by_charid`/`by_uniqid` false right after hire, true after saving (`c2-saved`); `is_restore` false →
    true after reload. Retinue M1 status shows him as an ordinary hired pawn (Lv 23, Disc 0).
- **Step 4 (d)**, run file `docs/findings/data/2026-11-03-m2-lifecycle/d/lifecycle_20261104_001621.json.xz`. From the fixture,
  panel action *Dismiss slot 3* on Folken (Lv 27):
  - **Same call chain as the real Rift dismiss**, in the same order (`dismissPawn(CharacterID)` → `(Pawn)` → `unregistPawn`,
    `returnSubPawnItems`, `addStrayPawn_HireTime_DismissNotInstance` → `eventStrayPawnLost`,
    `setDisableContextStoreOnDissmissPawn`, `deleteRecord(CharacterID)`). The panel dismiss is a valid shortcut.
  - Re-hired from "previously hired": **another new CharacterID, 3147318785** (step 3 gave 372209474), same OfflineID,
    Lv 23, exp 0, and **different equipment again** (3339, 6122, 5016, 1203 vs step 3's 3311, 6122, 5007, 4019, 1203):
    the re-hired pawn's equipment is regenerated, not stable. The CharacterID is not deterministic per OfflineID.
- **Step 5 (e), lost via Nick's Devtools *Kill pawns*** (run file `docs/findings/data/2026-11-03-m2-lifecycle/e-kill/lifecycle_20261104_002638.json.xz`).
  *Kill pawns* removes the whole party at once (no downed state, no lost timer), so this is not the timer path and the
  rest-sweep cycle cannot be set up with it.
  - At the kill (t≈197): for each hired pawn `returnSubPawnItems`, `unregistPawn`, `SoundVoiceManager.onDismissUnloadPawnEvent`,
    `addStrayPawn_HireTime_DismissNotInstance` → `eventStrayPawnLost` (main pawn: the same minus item return). **No
    `PawnManager.lost`, no `dismissPawn`, no `deleteRecord(CharacterID)`, no lost timer.**
  - **The record survives the kill**: `e1-killed` reads Folken and Diamonds from their ContextDBMS record (`source=record`,
    record present, Lv 27 intact). By `e4-rift` (taken before touching the stone, ~4.5 min later, after travelling) both
    records were gone; the deleting call is not identified (likely `deleteRecord(UniqueID)`, capped as chatty).
  - At the Rift stone `startRim` → `lostDeadPawns`; the main pawn came back (`resetPawnLostTimer`), the hired pawns did not.
  - User: Folken appears in the Rift's "previously hired" list at **Lv 23**: a lost pawn can be re-hired like a
    dismissed one, with the same loss of progress. No equipment came back (`returnSubPawnItems` returns carried items,
    not equipment; same in dismiss).
  - `pawnLost(Character)` (b1=b2=true) / `pawnLost(InstanceInfo)` fired ~4000× for the main pawn only, between t 108 and
    172, before the kill: not tied to the lost event observed here.
- **Step 6 (f)**, run file `docs/findings/data/2026-11-03-m2-lifecycle/f/lifecycle_20261104_004428.json.xz`. Panel
  *Force lost slot 3* (`lost(id, false, false)`): the call threw (`Invoke threw an exception`) after `returnSubPawnItems`;
  ~9 s later `unregistPawn` removed Folken (record intact, `away (record present)`); ~58 s later `registPawn` brought him
  back, same CharacterID, Lv 27. A direct `lost` call is not a usable shortcut. Rift not visited.

## Answer

Done 2026-11-04. Findings note: `docs/findings/0006-m2-dismiss-lost-rehire.md` (run files in
`docs/findings/data/2026-11-03-m2-lifecycle/`, xz-compressed).

- **Recognised by `_OfflineID`, never CharacterID**: each re-hire gets a new, non-deterministic CharacterID (372209474,
  then 3147318785, for old 1601809365); the OfflineID is the same.
- **Nothing survives dismiss or lost**: the record is deleted inside `dismissPawn` (lost: later, at an unidentified
  moment). The re-hired pawn comes back at its first-hire level (Lv 23, not 27), exp 0, discipline 0, with regenerated
  equipment. Vocation rank 6 came from the generation data.
- **A lost pawn does come back**: it is offered in the Rift's "previously hired" list (the game's `DisMiss` list, written
  at hire time with the hire-time level), like a dismissed one.
- Backup timing: `dismissPawn` pre reads everything; lost has no such hook, so the backup must be kept current while the
  pawn is in the party.
- Not observed: natural lost via the down timer and the rest sweep (*Kill pawns* never leaves a downed pawn).
