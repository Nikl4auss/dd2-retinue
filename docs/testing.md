# In-game testing

## Before every test that changes game state

1. Quit the game and back up: `tools/saves.sh backup <label>` (e.g. `m1-isSubPawn-hook`).
   It copies the save folder and `reframework/data/Retinue/`, verifies the copy, and refuses to run while
   `DD2.exe` is up.
2. Note which other mods are active if they touch pawns, items, skills or experience.

Read-only probes (`tools/probe/`) need no backup.

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

## Checklists

One section per milestone, written before its implementation starts.
