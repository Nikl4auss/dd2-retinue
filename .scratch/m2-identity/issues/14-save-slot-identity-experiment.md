# Which save slot is loaded, and can a new game be told apart?

Type: task
Status: claimed
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
