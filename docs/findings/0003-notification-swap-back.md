# 0003 — Notification swap-back and vocation rank-up for hired pawns

Date: 2026-11-03 · Tool: `tools/experiments/Retinue_Exp_Hooks.lua` variant 4 (commits `4258f23`, `341bd9c`) ·
Raw data: [data/2026-11-03-exp-hooks-v4/](data/2026-11-03-exp-hooks-v4/)

Offline play, same save and party as [0002](0002-exp-hook-variants.md): main pawn Shaira (2283028347), hired
Alder (1601809365, Fighter) and Clothilde (1306736823, Archer). Backup taken before any run:
`20261103-122746-m1-variant4`.

Variant 4 = variant 3's rewrite (ID → `ch100000_00` in `checkLevelUp` and `addJobPoint`) with the Boolean left as the
game passes it, and the real hired-pawn ID put back into `dispLevelUpUI` and `GuiManager.reqJobRankUp` when they run
nested inside a rewritten call. Debug multipliers (hired pawns only) were used to reach the events quickly.

## Runs

| Run file | What | Hired pawns |
|---|---|---|
| `run_20261103_131653.json` | jobPoint ×20, one fight; save → title → load; variant 0 | rank 4 → **5**, discipline 379 → 4359; kept after reload and at variant 0 |
| `run_20261103_143047.json` | exp ×10, one fight; save → title → load | level 19 → **20**; the load **froze** (see below); level 20 was in the save |
| `run_20261103_144510.json` | after a relaunch: save → title → load with no grant; then exp ×10, one fight; wait ~30 s; save → title → load | level 20 → **24** from a single grant; both loads fine; kept |

## Results

### Rank-up

`addJobPoint` (rewritten) → `addJobPointInternal` → `GuiManager.reqJobRankUp`, synchronously, with the main pawn's ID.
The swap-back replaced it with the hired pawn's. **On screen: one rank-up notification per hired pawn, with its own
name.** `GuiManager` accepts a hired pawn's ID. Rank follows `CulmativeExp` as predicted (research ticket 01).

### Level-up

`checkLevelUp` (rewritten) → `dispLevelUpUI` (main pawn's ID, swapped back) → `GuiManager.reqLevelUp` and
`PawnPartyCombatInfo.setLevelUp`, both called with the **hired pawn's** ID. **On screen: one level-up notification per
hired pawn, with its own name** (0002 showed "Shaira" twice). No visible pawn-chatter reaction either way.

Several levels from one grant (20 → 24 from one 46 000-exp grant) produce **one** `dispLevelUpUI` / notification
spanning the jump, not one per level.

### Main pawn

Its level, exp, discipline and rank moved only by its own grants in every run.

### The freeze

On the save → title → load after the first level-up (14:37), the game hung during the load and had to be killed.
The REFramework log shows ~80 caught exceptions (`app.Character.get_IsDrawedWeapon`, `via.GameObject.set_DrawSelf`,
`via.Component.get_GameObject`) at the title transition, raised by Lua calls from **other installed mods** (our script
calls none of these methods), and nothing after 14:38:18 but a periodic Streamline message.

Not attributed to Retinue:

- The same exception burst appears at **every** title transition in these sessions (13:32, 14:47, 14:49, 14:57), none
  of which hung.
- No Retinue hook ran during the transition (last call 20 s before the save).
- Repeating the exact sequence (variant 4 level-up, pending chatter, save → title → load) did **not** hang.

Unexplained one-off; logged in `re2_framework_log_freeze_1430.txt`. The M1 in-game checklist should include a
save → title → load right after a hired-pawn level-up.

## Conclusions

1. **Swap-back works for both notifications**: correct name, once per pawn. The silent fallback is not needed.
2. **Hired-pawn vocation rank-up works** under the `addJobPoint` rewrite and persists.
3. Downstream of `dispLevelUpUI`, the game's own calls (`reqLevelUp`, chatter's `setLevelUp`) get the hired pawn's
   ID, so nothing else seen is left keyed on the main pawn's.
4. Multi-level jumps notify once, with the full range.
5. Gains persist through save/load, also with no override active.

## Notes on the tool

- `dispLevelUpUI`'s parameter labels were reversed in these run files (it receives `(newLv, oldLv)`, noted in 0002):
  read their `prevLv`/`nextLv` swapped. Fixed in the script afterwards.
- The debug multipliers' gains stay in the save (here: discipline, rank 5, level 24). Restore
  `20261103-122746-m1-variant4` to undo them.
