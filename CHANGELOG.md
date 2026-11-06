# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/);
0.x while the mod is incomplete. 0.1.0 is the first playable release (milestones M1 + M2).

## [Unreleased]

### Added
- Project scaffold: docs, deploy script, dump query tools, read-only party probe (research tool, not part of the mod).
- `tools/saves.sh`: verified backup and restore of the save folder and mod data for in-game tests.
- Progression (M1): hired pawns in the party gain levels, discipline and vocation rank from any exp source through
  the game's own curve, by pre-hooking `ExpDispenser.checkLevelUp` and `addJobPoint`. The main pawn is never altered.
- Level-up and rank-up notifications name the hired pawn (`dispLevelUpUI`, `GuiManager.reqJobRankUp`).
- *Retinue* menu: progression checkbox, status line (name, level, vocation, rank, discipline per hired pawn), and a
  `Progression unavailable` notice when a hooked method is missing (all-or-nothing install).
- `reframework/data/Retinue/config.json` holding the checkbox: written only on change, per-key validation with
  warnings in the menu and log, unknown keys kept.
- `tests/run.sh`: pure-Lua test runner for the mod's logic.
- Backups (M2): every present adopted pawn in the party has `slots/<n>/backups/<offline_id>.json` (level, exp, stat
  increases, discipline, vocation exp; item IDs and skills recorded), written on adopt and refreshed about every 10 s
  in the world, only when a value changed. A member below its backup lowers it (the save wins). Release empties or
  deletes the file. The menu shows an away member's level from its backup and a note when the backup is missing or
  damaged.

### Changed
- `deploy.sh --experiments` links the experiments instead of the mod, and refuses to link one while the other is
  linked.
