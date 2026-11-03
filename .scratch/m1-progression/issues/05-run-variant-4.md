# Run variant 4: notification swap-back and rank-up

Type: task
Status: open
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
