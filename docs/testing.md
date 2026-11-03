# In-game testing

## Before every test that changes game state

1. Quit the game and back up: `tools/saves.sh backup <label>` (e.g. `m1-isSubPawn-hook`).
   It copies the save folder and `reframework/data/Retinue/`, verifies the copy, and refuses to run while
   `DD2.exe` is up.
2. Note which other mods are active if they touch pawns, items, skills or experience.

Read-only probes (`tools/probe/`) need no backup. Experiments (`tools/experiments/`) hook the game and can
change saves: they DO need a backup, one per run.

To roll back: `tools/saves.sh list`, then `tools/saves.sh restore <backup>`. Restore first takes a
`pre-restore` backup of the current state, so it can itself be undone.

## Where things are

- **Saves**: the game runs through crucible-launcher, so the live folder is
  `~/.local/share/crucible-launcher/Prefix/dragon_s_dogma_2prefix/drive_c/users/Public/Documents/Steam/RUNE/2054970/remote/win64_save/`.
  `tools/saves.sh where` prints the folder it would use: the most recently written `2054970/remote/win64_save`
  across the known prefixes. An older, stale copy exists under Steam's `compatdata/2434481856/`; ignore it.
  Override with `DD2_SAVE_DIR`.
- **Backups**: `<game>/Retinue-backups/<timestamp>-<label>/` (override with `DD2_BACKUP_DIR`).
  `20261103-092435-m0-baseline` is the state before any Retinue code ran.

## Recording results

- Use the probe's *Save snapshot* at each step; snapshots land in `reframework/data/Retinue/probe/`.
- Copy them into `docs/findings/data/<date>-<topic>/` and write a findings note
  (procedure, results table, conclusions, open questions).
- Experiment runs write JSON logs to `reframework/data/Retinue/experiments/`; the procedure is in
  `tools/experiments/README.md`.

## Checklists

One section per milestone, written before its implementation starts.

## M1 — Progression

Spec: [.scratch/m1-progression/spec.md](../.scratch/m1-progression/spec.md). Record results in a findings note with
the probe's snapshots. Items marked *(opportunistic)* pass when the situation comes up during play; record each one as
passed or not reached.

### Setup

1. Quit the game and back up: `tools/saves.sh backup m1-checklist`.
2. `./deploy.sh --remove`, then `./deploy.sh --probe`. The experiment script must **not** be linked.
3. Delete `reframework/data/Retinue/config.json` if present (fresh-install state).
4. Use a save with two hired pawns in the party, at least one of them hired long enough to have banked exp.
   Note the other active mods that touch exp or skills (SimpleDifficultyTweaks multipliers, Bestiary, UDD2P,
   SkillCreator).

### Checks

1. **Menu, fresh install**: the *Retinue* section shows the checkbox ticked, no `Progression unavailable` notice,
   and `Applies to:` listing both hired pawns with level, vocation, rank and discipline. No `config.json` was created.
2. **Banked exp**: on the first fight, the long-hired pawn gains its banked levels (possibly several at once). One
   level-up notification, with its own name.
3. **Normal fight**: hired pawns gain exp and discipline (probe snapshot before and after), and level up when exp
   allows. Each notification names the right pawn, once. The main pawn's numbers move only by its own gains, and its
   own level-up notification names the main pawn.
4. **Rank-up**: a hired pawn's vocation rank goes up, and the rank-up notification shows its own name.
   *(opportunistic: needs a pawn close to its next rank)*
5. **Save → title → load right after a hired-pawn level-up**: no freeze, and level, discipline and rank are kept.
   Repeat once.
6. **Full relaunch**: quit, relaunch and load. Gains are kept and the menu state matches.
7. **Toggle off**: untick mid-session. `config.json` now exists with `"progression": false`. In the next fight hired
   pawns gain exp but no level and no discipline, and nothing gained earlier is lost. *Reset scripts*: still off.
8. **Toggle on again**: the next grant applies the exp banked while off, as in check 2.
9. **Party change**: swap a hired pawn at the Rift. The status line follows without *Reset scripts*, and the new
   pawn progresses on its next fight.
10. **Malformed config**: quit, write `not json` into `config.json`, and launch. Progression is on (default), the
    menu and the REFramework log show a `config.json` warning, and the file is unchanged until you toggle. Then put
    `{ "version": 1, "progression": "yes", "extra": 1 }`: progression is on, there is a warning for `progression` (menu and log),
    and after a toggle the file keeps `"extra": 1`.
11. **Main pawn untouched**: across all of the above, nothing about the main pawn differs from vanilla.
12. **Mod-originated grant**: UDD2P's Sphinx reward (or any mod that grants exp) levels hired pawns. This verifies
    that `sdk.hook` fires for Lua `method:call`. *(opportunistic)*
13. **Player rank-up from SkillCreator's refund**: the notification still names the player. *(opportunistic)*
14. **SimpleDifficultyTweaks multiplier ≠ 1**: the main pawn is scaled and hired pawns are not (known difference).
    *(opportunistic: only if the user changes the preset)*
15. **Uninstall**: `./deploy.sh --remove`, then launch and load. The save loads, and hired pawns keep their levels as
    ordinary hired pawns.

Afterwards: restore `m1-checklist` only if you do not want to keep the gains.
