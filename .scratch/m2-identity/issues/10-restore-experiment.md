# Can a backup be written into a re-hired pawn?

Type: task
Status: resolved
Blocked by: 09

## Question

Extend the lifecycle experiment (or add one) to write a stored backup (the fields chosen in "What does a pawn's backup
hold, and when is it written?") into a pawn just re-hired from the Rift, matched by OfflineID on `hirePawn` post, then
run it in game: do level, exp, stat growth (`_IncreaseParams`: HP and stamina on the Status page), extra status boost,
discipline and `CulmativeExp` (ranks) stick, survive save/reload and a full relaunch, and does the save still load with
the mod removed? Equipment and skills are not written (only compared); find out where equipment the player gave the
pawn goes on dismiss and on lost. Note when the pawn's record becomes writable (the lookups were false until a
save), and confirm `PawnOwnerContext._OfflineID` is readable in `hirePawn` post (see "What identifies an adopted
pawn across dismiss and re-hire?"). Findings note after.

## Run log

Data: `docs/findings/data/2026-11-04-m2-restore/<step>/`.

**0 Baseline** (2026-11-04, fixture `20261103-214905-fixture-levelled-pawn`, deployed `--probe --lifecycle --restore`;
screenshots in `0-baseline/`). Folken, Warrior: Lv 27; Health 1837 (base 1837); Stamina 855 (855); Strength 446 (239);
Defense 283 (170); Magick 55 (55); Magick Defense 124 (44); Knockdown Power 342 (46); Knockdown Res 430 (400);
Max Encumbrance 49.00 kg; Warrior rank 6, other vocations rank 1. Experience and Current Discipline show "-" for a
hired pawn (not visible natively: discipline is checked from the panel and the run file only).

**a Capture** (15:51). All hooks installed (both experiments). Folken was given the helmet "Meloieran Cyclops Veil" from
storage (item id 4018: new in `item_ids`, which are 3329, 6123, 5132, 4018, 1203), then *Capture backup of slot 3*. Backup:
Lv 27, exp 9610, discipline 1930, extra boost 0, `_IncreaseParams` HP 7875, stamina 2550, attack 1395, defence 1104,
magic attack 558, magic defence 445, blow 260, weight 140 (ReadOnly false); `CulmativeExp` [0,0,0,0,11130,0,...]; ranks
Warrior 6, others 1. `calcMaxHp` gives 1637.5 against 1837 shown (base) on the Status page, `calcMaxStamina` 855 = shown.

**b Real dismiss** (16:11, from the field: a native dismiss runs the same chain anywhere). Auto-capture at
`dismissPawn(CharacterID)` pre refreshed the backup (Lv 27, exp 9610, discipline 1930; source `dismissPawn-pre`).
Chain: `dismissPawn` pre → `returnSubPawnItems` → `removeEquipData` → posts. **No storage hook fired**: the equipment,
including the player-given helmet 4018, does not come back; `getHaveAllNum` is 0 for all five equipped items at +1 s and
+5 s (1 each at capture). As the game warns when equipping a hired pawn, the item goes to its owner: the player loses it.
No errors. Saved, marker `saved`. Save backup `m2-restore-after-dismiss`. Data in `b/`.

**c Re-hire with Restore mode 1** (16:20, run file `restore_20261104_161631.json`). `hirePawn` pre and post both read the
OfflineID (`426f7888…`) from the Character's `PawnOwnerContext`: **the OfflineID is readable in `hirePawn` post.** New
CharacterID 372209474; in post Lv 23, exp 0, record lookups false (`by_charid`, `by_uniqid`), `IsStore` true, `IsRestore`
false. Return matched; restore one frame later. Before: Lv 23, exp 0, discipline 0, `_IncreaseParams` HP 6720, stamina
2280, attack 1095, defence 996, magic attack 480, magic defence 370, blow 220, weight 110; Warrior culmative 9200.
Writes: `set_Level`, `set_Exp`, the eight `_IncreaseParams` fields by `set_field` (ReadOnly was false),
`setExtraStatusBoost` (0), `set_ConsumableExpProp` (1930): **all read back equal and unchanged at +1 s and +10 s**.
**`CulmativeExp` not written**: `set_element` does not exist in this REFramework; `SetValue(create_int32, i)` returns
without changing the array (Warrior stays 9200, rank 6 either way). Status page (screenshots `c/`): Lv 27, base Health
1837, Stamina 855, Strength 239, Defense 170, Magick 55, Magick Defense 44, Knockdown Power 46, Knockdown Res 400:
**identical to the baseline**; totals differ only by the regenerated equipment. Warrior rank 6.
Script fix for the array: SetValue, then index assignment, then the game's `set_NowJobCulmativeExpProp` (current job)
/ `addJobExp(job, delta)`; retested in-session with *Reset scripts* + manual *Restore backup into slot N*.

**c' Array fix, same session** (16:29, *Reset scripts*, manual *Restore backup into slot 3*, run file
`restore_20261104_162915.json`). `SetValue` again no effect; **index assignment `arr[i] = v` (0-based) wrote
`CulmativeExp`** (Warrior 11130, read back equal). The game-method fallback was not reached (untested). Discipline 1930,
ranks unchanged. **0 of 46 fields differ at +10 s**, no errors.

**c'' Persistence.** Saved (marker `saved`): the record became visible at the save (16:40:38, `by_charid` and
`by_uniqid` true) — **the restore was written to the live contexts before any record existed, and the save stored it**.
Back to title, reload (16:42:17, `IsRestore` true); compare `reload` 16:48: **only `item_ids` differ** (regenerated
equipment). Full relaunch (run file `restore_20261104_165127.json`, Restore mode 0, so nothing written this session):
`auto:first-seen` and `relaunch` compares, only `item_ids` differ. Status page unchanged per the user. No errors in any
run file.

**e Uninstall** (after save backup `20261104-165649-m2-restore-c`; `./deploy.sh --remove`: no mod, probe or experiment
linked, the user's other mods still installed). The save loads normally; Folken Lv 27 with the same Status page; saved,
reloaded: unchanged (user report, no screenshots). **The restored state is an ordinary saved hired pawn: the uninstall
guarantee holds.**

**f Lost path for equipment** (17:21–17:24, fixture again, run file `restore_20261104_171811.json`). Same helmet (4018)
given, captured, Nick's Devtools *Kill pawns*: `returnSubPawnItems` + `removeEquipData` for both hired pawns at the kill,
no storage hook; Folken left the party before the Rift. Item counts: 0 for all five items; the helmet is nowhere (user
checked inventory and storage). Step d (manual restore after a save) was not needed.

## Answer

Done 2026-11-04. Findings note: [0008](../../../docs/findings/0008-m2-restore.md) (data in
`docs/findings/data/2026-11-04-m2-restore/`).

- **Yes: the backup can be written into a re-hired pawn and it sticks.** Written to the live `HumanStatusContext` /
  `JobContext` one frame after `hirePawn` post, before the pawn has a record: level, exp, all eight `_IncreaseParams`,
  extra boost, discipline and `CulmativeExp` read back equal, are not overwritten, and survive save, reload and a full
  relaunch. The Status page (HP, stamina and every base stat) matches the levelled pawn exactly.
- **Record writability**: no need to wait. The record appears at the next save and stores the written values;
  `IsRestore` turns true on reload.
- **`_OfflineID` is readable in `hirePawn` post** (and pre).
- **Write methods**: setters for level, exp, extra boost, discipline; `set_field` on the existing `_IncreaseParams`
  object; index assignment `arr[i] = v` for `CulmativeExp` (`set_element` does not exist, `SetValue` is a no-op).
- **Uninstall**: with Retinue removed the save loads and the pawn keeps its restored state.
- **Equipment**: gear the player gives a hired pawn is lost on dismiss and on lost (removed with `removeEquipData`, never
  returned to storage). Recording it in the backup stays display-only.
