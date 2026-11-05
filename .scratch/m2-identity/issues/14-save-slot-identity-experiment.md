# Which save slot is loaded, and can a new game be told apart?

Type: task
Status: resolved
Blocked by: 12

## Question

"How does the mod reconcile the roster with a save that disagrees with it?" made the roster per save slot; the mod
must know which of the three slots is loaded, or it activates no roster. Build an experiment script (log-only) and run
it in game: on every load (each slot; its autosave, inn save and manual save; "load last save" after death) and on
every save of each type, log `app.GameSystem` `LatestSaveSlot`, `getLatestSaveSlot()`, `getLatestSaveSlotNum()`,
`getSaveSlotType(...)`, `SaveData_02.LatestSaveSlotId`/`SlotTimeStampList`, and the slot's
`GameSaveSlotDetailContents` (`SaveCount`, `ActualPlayingTime`). Establish: which value maps to the player's slot 1–3
(and how the `dataNNNslot.bin` files group per slot), whether it is stable across save types, reload and relaunch,
when during a load it is first correct (before the world is entered?), and how a **new game** over an existing slot
and an **NG+** (`Clear`) can each be detected (a hook, a counter or play time that drops, the slot type). Every run
backs up with `tools/saves.sh backup <label>` first (the user's three slots are real playthroughs); findings note after.

## Answer

Resolved 2026-11-05 (task: built `tools/experiments/Retinue_Exp_SaveSlot.lua` + `watch_saves.sh` at `1e69af4`, run in
game). Facts in [findings 0010](../../../docs/findings/0010-m2-save-slot-identity.md); what the mod does with them:

- **Slot = the game's unit** (0–2, menu slots 1–3). A save is a global slot `unit × SLOT_PER_UNIT + type`
  (`SLOT_PER_UNIT` = 5, read from `app.GameSystem`'s static at runtime, never hard-coded). The roster directory is
  `slots/<unit + 1>/` so it matches what the player sees (1–3).
- **How the mod learns the unit**, kept as session state ("loaded unit"), set before the world is entered:
  - hook `MainFlowManager.requestLoadGameData(Int32)` pre: unit = arg ÷ `SLOT_PER_UNIT` (every load: title, Continue,
    death reload, restarts);
  - hook `MainFlowManager.requestStartType(StartType)` pre with `NewGame`: unit = `GameSystem.UnitNumber` at that
    moment (a new game in an empty unit loads nothing).
  - **Fallback** when no such call was seen this session (the mod loaded after the game started, e.g. "Reset scripts"
    in the world): in the world, use `LastLoadedSlot ÷ SLOT_PER_UNIT` **only if it equals `UnitNumber`**; otherwise
    the slot is unknown (the existing rule: no roster active, nothing written, warning). Neither value alone is
    trusted: both default to 0 at boot, `UnitNumber` is iterated by the title menu, `LastLoadedSlot` stays 0 through a
    new game's prologue.
  - `LatestSaveSlot` (newest save of any unit) and `UnitPlayCountList` are not used.
- **New game and NG+**, from `requestStartType` (the unit already known from the same flow):
  - `NewGame` (empty unit) and `RedoNewGame` (restart over an occupied, not cleared unit: the game deletes that unit's
    saves on the final confirm): **a new playthrough** → if the unit has a roster, it moves to
    `slots/<n>/archive-<date>/` (as decided in the save-drift ticket) and the unit starts empty. The archive is written
    from the update loop right after the hook, never inside it.
  - `RedoNewGameSkip` (restart over a cleared unit, the game's NG+: prologue skipped, Arisen and main pawn kept,
    hired pawns gone): **the same playthrough** → roster kept; members not in the party become away by the general
    rule and keep their backups.
  - Any other `StartType` (Latest, Base, SystemMenuSave, and none on death reload): a load within the playthrough,
    the save-drift rules apply.
- **When**: the unit is known at `requestLoadGameData` / `requestStartType`, 20–40 s before the world; the
  reconciliation pass still runs on entering the world, as decided. Switching units in one session is
  `restart()` → title → the next start, which sets the unit again.
- No new ticket: what the Rift keeps after NG+ is left to the general away/Return rules (a member who can't come back
  stays away until released).
