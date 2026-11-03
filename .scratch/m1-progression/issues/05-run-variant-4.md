# Run variant 4: notification swap-back and rank-up

Type: task
Status: resolved
Blocked by: 04

## Question

Extend `tools/experiments/Retinue_Exp_Hooks.lua` with variant 4 (the core rewrite from
[Decide the M1 hook set](04-decide-hook-set.md), the Boolean left as passed, and the real hired-pawn ID swapped back
in `dispLevelUpUI` and `GuiManager.reqJobRankUp`) plus a debug-only jobPoint multiplier for hired pawns, so a
vocation rank-up is reached in one or two fights. With the user playing (`tools/saves.sh backup <label>` first), record:

- Does a hired pawn's vocation rank go up, and does discipline still grow as in 0002?
- Level-up and rank-up notifications: shown? With which name? Once per pawn? Does the GUI accept a hired pawn's ID?
- Anything else keyed on the ID that goes wrong (e.g. pawn chatter `PawnPartyCombatInfo.setLevelUp`).
- Main pawn unaffected; gains persist through save → title → load.

Write `docs/findings/0003-<slug>.md` with data under `docs/findings/data/<date>-<topic>/`. If swap-back fails, the
answer records that M1 falls back to the silent notification.

## Answer

Run 2026-11-03 with the user (three sessions). Full write-up: `docs/findings/0003-notification-swap-back.md`, data in
`docs/findings/data/2026-11-03-exp-hooks-v4/`. Script extended with variant 4 plus debug jobPoint and exp multipliers.

- **Swap-back works**: rank-up and level-up notifications show each hired pawn's own name, once. The GUI accepts a
  hired pawn's ID. The silent fallback is not needed.
- **Vocation rank-up works** under the `addJobPoint` rewrite (rank 4 → 5) and persists.
- Downstream of `dispLevelUpUI`, `reqLevelUp` and pawn chatter's `setLevelUp` get the hired pawn's ID; no visible
  chatter reaction. A multi-level jump (20 → 24) shows one notification for the whole range.
- Main pawn unaffected; gains persist through save → title → load, also at variant 0.
- One unexplained freeze on a load after a level-up; not reproduced on an identical repeat, and the exception burst
  in the log comes from other mods at every title transition. Not attributed; the M1 checklist should cover a
  save → title → load right after a hired-pawn level-up.
