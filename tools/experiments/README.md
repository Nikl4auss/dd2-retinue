# Experiments

Throwaway scripts that **hook the game** and can change state and saves. Not part of the mod. Unlike the
read-only probe, every run needs a backup first.

## `Retinue_Exp_Hooks.lua`: does lifting the `ExpDispenser` gate level up hired pawns?

Question: if `app.ExpDispenser` stops treating hired pawns as hired, do they gain level, discipline and
vocation rank from a fight, and what does each hooked call receive?

Variants (menu: **Retinue Exp Hooks (EXPERIMENT)**; it always starts at 0, nothing is saved between sessions):

| Variant | Effect for hired pawns in the party |
|---|---|
| 0 Off | no overrides, hooks only log |
| 1 isSubPawn | `ExpDispenser.isSubPawn` returns false |
| 2 + checkLevelUp ID rewrite | also `checkLevelUp` gets the main pawn's CharacterID (and Boolean false, if ticked) |
| 3 + addJobPoint ID rewrite | also `addJobPoint` gets the same rewrite |
| 4 + notification swap-back | 3's rewrite with the Boolean left as passed; the real hired-pawn ID is put back into `dispLevelUpUI` and `GuiManager.reqJobRankUp` when they run inside a rewritten call |

Debug sliders (variant ≥ 3): **hired jobPoint x** multiplies the hired pawns' jobPoint in `addJobPoint`, **hired exp x**
their exp in `addExpAndJobPoint(id, exp, jobPoint, chara)`, to reach a rank-up or level-up in a fight or two.
Discipline, rank and levels gained this way are saved: restore the backup after the
run if you don't want to keep them. `PawnPartyCombatInfo.setLevelUp` (pawn chatter) is hooked log-only.

Baseline to compare against: in the same fight the main pawn gained +1891 exp and +479 discipline
(see `docs/findings/0001-hired-pawn-baseline.md`); hired pawns gained +1891 exp, no level, no discipline.

### Procedure

1. Quit the game. Back up, one label per run: `tools/saves.sh backup m1-variant1`.
2. `./deploy.sh --remove`, then `./deploy.sh --experiments` (add `--probe` if you also want the probe). This links
   the experiments instead of the mod: the two hook the same methods and are never linked together.
3. Launch, load the save (two hired pawns in the party), open the REFramework menu, expand
   **Retinue Exp Hooks (EXPERIMENT)**. Check the status line says all hooks are installed (if some are
   missing, note which and stop). Note which other mods touching exp or skills are active.
4. Log-only fight: variant 0, "Log calls" on. Type a label and press **Snapshot** with `before-logonly`,
   fight one enemy group, **Snapshot** `after-logonly`. Watch whether level-up or rank-up notifications
   appear, and for whom.
5. Variant 1: select it in the combo (an `auto:variant->1` snapshot is taken), Snapshot `before-v1`, fight
   one enemy group, Snapshot `after-v1`. On screen note: does a hired pawn level-up notification appear,
   under whose name, several levels at once? Watch discipline and rank in the live table.
6. Persistence: save at an inn or rest, Snapshot `pre-save`, go back to the title, reload, Snapshot
   `after-reload`. Set variant 0 and Snapshot `variant0-after-reload`.
7. Only if variant 1 falls short: restore the backup (below) or continue from the current state, then repeat
   step 5 with variant 2, then variant 3, each run with its own backup first (back to step 1).
### Variant 4 run (notification swap-back and rank-up)

Back up (`tools/saves.sh backup m1-variant4`), deploy, load. Select variant 4, set **hired jobPoint x** to 20,
Snapshot `before-v4`, fight until a hired pawn ranks up (watch Rank in the live table), Snapshot `after-v4`.
On screen note: level-up and rank-up notifications, whose name, how many times, and any odd pawn chatter. Then the
persistence step (6) as above.

8. Quit the game. Copy `reframework/data/Retinue/experiments/run_*.json` (in the game folder) into
   `docs/findings/data/<date>-<topic>/`. Then `./deploy.sh --remove`.

A forgotten script is harmless: it starts at variant 0 on the next launch.

### Rolling back

`tools/saves.sh list`, then `tools/saves.sh restore <backup>` (game closed). Restore first takes a
`pre-restore` backup of the current state, so it can be undone.

### What the run file contains

`run_<YYYYmmdd_HHMMSS>.json`, one per script session, flushed every 2 s when changed (also via **Flush log
now**):

- `variant_events`: every variant or checkbox change, with a timestamp.
- `lvup_params`: the exp curve (`Level`, `RequiredEXP`), dumped once.
- `snapshots`: `{label, time, pawns}` as the probe's fields plus `consumable_exp` and `culmative_exp`
  (whole array; JSON position = array index, the index-to-vocation mapping is not assumed).
- `calls`: one entry per hooked call: `seq`, `t` (`os.clock()`), `depth` (nesting), `method`, `id`, `tag`
  (`main`/`hired`/`other`), decoded `args`, `ctx_before`/`ctx_after` (level, exp, discipline, culmative exp,
  rank) for the progression methods, `ret` and `count` for `isSubPawn` (consecutive identical entries are
  collapsed), and `override` when a rewrite fired (original and rewritten values).
- `dropped` (entries lost after the 20000-entry cap), `errors` (caught hook errors; empty is the goal),
  `hooks` (installed and missing hooks).
