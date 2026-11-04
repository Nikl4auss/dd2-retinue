# How does the mod reconcile the roster with a save that disagrees with it?

Type: grilling
Status: resolved
Blocked by: 11

## Question

The roster is global, not per save ("What is the shape of the roster file and its validation?"), and the load-time
rules from "How does the mod notice a member leaving and returning, and when does it act?" cover the simple cases
(away but in the party → present, no restore; present but not in the party → away; returning → retry). Decide what
happens when the save contradicts the roster in ways those rules don't settle: loading an older save (or
`tools/saves.sh restore`) where an away member is present at a lower level than its backup, or where the member was
never hired; a second save slot or a new game; a party pawn whose CharacterID cache points at a different pawn; two
saves leap-frogging one backup. Which side wins per field, when the backup is overwritten or kept, what is logged, and
whether anything must be stored (e.g. a save marker or timestamps) to tell these apart.

## Answer

Resolved 2026-11-04 (grilling); every recommendation accepted. Correction from the user that reshaped the ticket: DD2
now has **three save slots**, each with its own history of autosaves, inn saves and manual saves (on disk:
`data000.bin`, `data00-1.bin`, `data001slot.bin`…`data009slot.bin`). The il2cpp dump has `app.GameSystem`
`LatestSaveSlot` / `getLatestSaveSlot` / `getSaveSlotType`, enum `SaveSlotType` (`Manual`, `Auto`, `AddAuto`, `Back`,
`Clear`), and `GameSaveSlotDetailContents` (`SaveCount`, `ActualPlayingTime`). Which value names the player's slot is
established by "Which save slot is loaded, and can a new game be told apart?".

- **One roster per save slot** (supersedes "global" in "What is the shape of the roster file and its validation?"):
  `reframework/data/Retinue/slots/<slot>/roster.json` and `slots/<slot>/backups/<offline_id>.json`; the cap of 2 is
  per slot. Format stays `version: 1` (nothing was ever shipped with a global roster: no migration). `config.json`
  stays global (settings, not playthrough state). A global roster would split the cap across playthroughs and let one
  slot's present pawn overwrite another slot's away backup.
- **Slot unknown at load** (not identifiable or the read fails): no roster is active that session. Adopted pawns behave
  as ordinary hired pawns, nothing is written, Adopt disabled with the reason, a warning. Never guess a slot.
- **Within a slot, the save wins**: loading an older autosave, inn or manual save is a rollback of that playthrough.
  A member in the loaded party keeps the save's state even when below its backup (level or exp); the poll lowers the
  backup; a warning logs both levels. No `.prev` copy of the overwritten backup. No save marker or timestamps are
  needed: on load a present pawn is never regenerated (that only happens at `hirePawn`), so lower than the backup means
  an older save.
- **Member absent from the loaded save** (save from before the adopt): away with its backup, by the existing rule.
- **New game over a slot with a roster**: if detectable, the slot's roster and backups move to
  `slots/<slot>/archive-<date>/` (never deleted) and the slot starts with an empty roster. NG+ (`Clear`) is the same
  playthrough and keeps its roster, if it can be told apart. If a new game cannot be detected, its members become away
  by the general rule and the player releases them.
- **CharacterID cache**: identity is always resolved by OfflineID on load and on every party change; a mismatching
  `character_id` is corrected (log line only when it changed) and never used to read or write.
- **`returning` on load**: in the party → restore retried with the level guard; not in the party (save from before the
  re-hire) → away, backup untouched.
- **Read-only roster**: reconciliation in memory only. **Locked**: none.
- **When**: one reconciliation pass per load, on entering the world (main pawn present, not loading, not at the
  title), before the party diff and the backup poll act. Switching slots in one session: each load activates that
  slot's roster and cancels the previous slot's pending work (returning retries, diff counts) without writing to it.
- **Orphan slot directories** (slot deleted in game) are ignored and never deleted automatically.
- **Logging**: one line per correction, e.g. `Rook: roster away, save has it Lv20 (backup Lv27) → present, save wins`.
- Glossary: `CONTEXT.md` gains **Save slot**; **Roster** is per save slot.
