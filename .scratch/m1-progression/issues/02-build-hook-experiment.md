# Build the hook-variant experiment script

Type: task
Status: open

## Question

Write `tools/experiments/Retinue_Exp_Hooks.lua` (deployed like the probe; not part of the mod) and its run
procedure, so the variant runs can answer the M1 questions:

- Mod-menu section with the variant selector: off / (1) `ExpDispenser.isSubPawn` → false for hired pawns in the
  party / (2) + CharacterID rewrite in `checkLevelUp` / (3) + rewrite in `addJobPoint`.
- A **log-only** setting (no override) that hooks `addExpAndJobPoint`, `checkLevelUp`, `addJobPoint`,
  `addJobPointInternal`, `dispLevelUpUI`, `GuiManager.reqLevelUp` / `reqJobRankUp` and `ExpDispenser.isSubPawn`,
  to see call order and the `Boolean` arguments for main and hired pawns (research ticket 01, open questions 2 and 5).
- Dump `LVupParams` (Level, RequiredEXP) once, and record `JobContext.CulmativeExp` and `ConsumableExp` per pawn.
- Logging of every hooked call (method, CharacterID, args, return) to a file under `reframework/data/Retinue/`,
  so a run can be read afterwards.
- Reuse the probe's snapshot so level, exp, discipline and vocation rank are recorded per pawn before and after.
- `deploy.sh` support for `tools/experiments/` (e.g. `--experiments`).
- The step-by-step procedure for the user, including `tools/saves.sh backup` and what to look at on screen.
