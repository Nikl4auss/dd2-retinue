# Build the hook-variant experiment script

Type: task
Status: resolved

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

## Answer

Done 2026-11-03. Not yet run in game (that is "Run variant 1 (`isSubPawn` alone) in game").

- `tools/experiments/Retinue_Exp_Hooks.lua`: mod-menu node "Retinue Exp Hooks (EXPERIMENT)". Variant combo
  0 Off / 1 `isSubPawn` / 2 + `checkLevelUp` ID rewrite / 3 + `addJobPoint` ID rewrite (cumulative), a
  "Rewrite Boolean to false (as Arisen's Own)" checkbox (default on, variants 2–3 only) and "Log calls"
  (default on). Log-only run = variant 0 + log on. Settings are not persisted: every launch starts at variant 0.
- Targets: party members with `PawnUtil.isSubPawn` true, main pawn (`ch100000_00` = 2283028347) excluded,
  refreshed once a second outside the hooks.
- 11 hooks installed once at load: `ExpDispenser.isSubPawn`, the four `addExpAndJobPoint` overloads,
  `addJobPoint`, `addJobPointInternal`, `checkLevelUp`, `dispLevelUpUI`, `GuiManager.reqLevelUp` /
  `reqJobRankUp`. Missing methods show in the status line; the rest still install.
- Output: `reframework/data/Retinue/experiments/run_<ts>.json` with variant events, `LVupParams`, snapshots
  (probe's pawn read + `consumable_exp`, `culmative_exp`), calls (args, nesting depth, context numbers before and
  after, overrides; consecutive identical `isSubPawn` calls collapsed), errors. Flushed every 2 s.
- `deploy.sh --experiments` (combinable with `--probe`; `--remove` removes all). Procedure:
  `tools/experiments/README.md`. `docs/testing.md` notes experiments need a backup per run.

Checked: `luac5.4 -p`, a mocked-API run under `lua5.4` (install, overrides per variant, rewrite, collapse,
nesting), `deploy.sh` against a throwaway game dir. Unverified REFramework details the first run should watch:
`sdk.to_ptr(0)` as a false Boolean retval/arg; `args` index of `this` for the two `GuiManager` hooks (log-only);
`get_method` signature format (a name + param-type fallback exists); reading `LVupParam` items and `Int32[]`;
possible stutter from flushing a large log.
