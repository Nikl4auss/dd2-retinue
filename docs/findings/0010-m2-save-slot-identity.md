# 0010 — M2: which save slot is loaded, and how a new game and NG+ show

Date: 2026-11-05 · Ticket: [Which save slot is loaded, and can a new game be told apart?](../../.scratch/m2-identity/issues/14-save-slot-identity-experiment.md)
(the decision is there) · Script: `tools/experiments/Retinue_Exp_SaveSlot.lua` at `1e69af4` (log-only) and
`tools/experiments/watch_saves.sh` · Run files (xz-compressed JSON) and the file-watcher log:
[data/2026-11-05-saveslot/](data/2026-11-05-saveslot/)

Offline play, mod active, deployed `--saveslot`. Saves backed up as `20261105-185454-m2-saveslot` and, before the new
game over slot 2, `20261105-192629-m2-saveslot-pre-newgame`, which was restored at the end. The pre-restore backup
`20261105-193920-pre-restore` holds the state after NG+ (the last run file came from it, because the restore also
replaces `reframework/data/Retinue`). No hook errors in any run; 53/53 hooks installed.

| Run file | Steps |
|---|---|
| `saveslot_20261105_185618` | title; load slot 1 and slot 2; load each save type of slot 1; manual, inn and autosave; death → "load last save" |
| `saveslot_20261105_191854` | relaunch → Continue (slot 1); new game in empty slot 3 |
| `saveslot_20261105_192726` | new game over slot 2; NG+ over slot 1 |

Playthroughs: slot 1 = Niklauss / main pawn Mishu, 74 h, cleared (`IsGameClearedList[0] = true`); slot 2 = Klauss /
Shaira, 7 h; slot 3 empty.

## Layout (verified-game)

- Statics of `app.GameSystem`: `UNIT_MAX_COUNT = 3`, `SLOT_PER_UNIT = 5`, `SLOT_MAX_COUNT = 15`; save types
  `SAVE_SLOT_AUTO = 0`, `MANUAL = 1`, `BACK = 2`, `CLEAR = 3`, `ADDAUTO = 4`, `SYSTEM = -1`.
- The game's code calls the player's save slot a **unit** (0–2 = slots 1–3 in the menu). A save is a **global slot**
  `unit × 5 + type`. File `dataNNNslot.bin` is global slot NNN (`data000.bin` is global slot 0, no `slot` suffix);
  `data00-1.bin` is the system save (slot −1), rewritten after every game save.
- Constant names do not match the menu names (from `ui030901.MainListInfo.SlotInfo.SaveDataType` on decide):

| Type | Constant | Menu (`SaveDataType`) | Written by |
|---|---|---|---|
| 0 | `AUTO` | Latest | autosave; also right after entering the world from a Latest load |
| 1 | `MANUAL` | Base | inn rest |
| 2 | `BACK` | (BackStart) | not seen |
| 3 | `CLEAR` | (ClearData) | temporary copy during a restart (below); deleted after the first save |
| 4 | `ADDAUTO` | Manual | manual save |

- **An inn rest writes three saves in a row: type 1, then 4, then 0** (watcher: `data001slot`, `data004slot`,
  `data000` at 19:14:58). It overwrites the manual save too.

## Which unit is loaded (verified-game)

- Every load of an existing save (Latest, Base, Manual from the title; "load last save" after death; Continue after a
  relaunch) calls **`MainFlowManager.requestLoadGameData(Int32 globalSlot)`**, then
  `SaveDataManager.requestLoadSlot` / `requestLoad` with the same number, 20–40 s before the world is entered.
  Death → "load last save" goes `restart()` → `requestLoadGameData(0)` without passing the title.
- `MainFlowManager.LastLoadedSlot` takes that number at the load, **but is 0 by default at boot** (a valid slot), and
  it follows every save afterwards (`setLatestSaveSlotNum`). It stays stale at the title. Unit = `LastLoadedSlot ÷ 5`
  is therefore right in the world, but cannot tell "unit 0" from "nothing loaded yet" on its own.
- `GameSystem.UnitNumber` is set to the chosen unit when the player picks a slot (`setUnitNumber`), but the title
  menu also iterates it over 0, 1, 2 while drawing the unit list, it is 0 by default, and it returns to 0 or stays
  stale at the title.
- `GameSystem.LatestSaveSlot` / `getLatestSaveSlot()` is the most recent save **across all units**, not the loaded
  one.
- `GameSystem.UnitPlayCountList` (`2,1,0` at boot) did not change on a new game over slot 2 nor on NG+; it went
  0 → 1 for slot 3 on its first save. Not a new-game signal.

## New game and NG+ (verified-game)

`MainFlowManager.requestStartType(StartType)` names every start: `SystemMenuSave` (9) for a Manual save, `Latest` (2),
`Base` (3), `NewGame` (0), `RedoNewGame` (7), `RedoNewGameSkip` (8), `ExitGame` (10). Death reload calls none.

- **New game in an empty unit** (slot 3): `setUnitNumber(2)` on pick, `requestStartType(NewGame)`, **no
  `requestLoadGameData`**. The first save (after the prologue) writes types 1, 4, 0 (global 11, 14, 10).
- **New game over an occupied unit that is not cleared** (slot 2): `SaveUnitSelect.onExecuteGameRestart(UnitNo 1,
  IsClearData false)`; on the final confirm the game loads the unit's latest save (9), copies it to type 3 (global 8)
  and **deletes the unit's saves 5, 6, 9 at once** (`updateUnitDataList(n, true)`, watcher). Then
  `requestStartType(RedoNewGame)` + `requestLoadGameData(8)`. The player plays the prologue; the character presets load
  the old Arisen's look. The first save writes 6, 9, 5 and deletes 8. A different playthrough.
- **NG+ over a cleared unit** (slot 1): the same restart path (`onExecuteGameRestart(UnitNo 0, IsClearData true)`,
  copy to type 3 = global 3, delete 0, 1, 4), then `requestStartType(RedoNewGameSkip)` + `requestLoadGameData(3)`.
  The menu does not say "New Game+" and offers no choice: with a cleared cycle it skips the prologue and starts in the
  capital. Arisen Niklauss and main pawn Mishu keep their level (329); **the party holds only the main pawn** (hired
  pawns gone). The first save writes 1, 4, 0 and deletes 3.
- In both restart cases `requestLoadGameData` names the unit (8 ÷ 5 = 1, 3 ÷ 5 = 0); `UnitNumber` already holds it
  from the pick.

## Not established

- What the Rift's "previously hired" list holds after NG+ (whether away members can return in the new cycle).
- A cleared unit always took `RedoNewGameSkip` here; whether a cleared unit can ever take `RedoNewGame` was not seen.
- Type 2 (`BACK`, menu BackStart) was never written.
