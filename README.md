# Retinue (working title)

A Dragon's Dogma 2 REFramework Lua mod, for local/offline use: adopt up to two hired pawns (the party is the main pawn
plus two) that keep their identity and progress, and that level up like the main pawn. Vocation change, equipment and
renaming are later milestones.

It is a replacement for the author's use of *Arisen's Own*, built on a different principle:
**adopted pawns stay hired pawns as far as the game's save is concerned**, and the mod only lifts
the restrictions placed on hired pawns at runtime. See [ADR 0001](docs/adr/0001-runtime-lift-not-save-injection.md).

## Status

Nothing released yet (0.0.0). M0 (research) and M1 (progression, checklist:
[findings 0005](docs/findings/0005-m1-checklist-run.md)) are done. M2 (identity and persistence) is implemented and its
in-game checklist is being run. 0.1.0 will be M1 + M2. See [docs/roadmap.md](docs/roadmap.md).

## What it does

### Adopt and release

Talk to a hired pawn in your party (in the field or at a Rift stone). The talk menu has an **Adopt** row before
*Never mind*; pick it, then *Confirm adopt* (or *Cancel*). The pawn is now a member of your **retinue**; the row reads
**Release (Retinue · Lv N)** from then on, and *Confirm release* makes it an ordinary hired pawn again, at the level it
has. The Arisen's own main pawn and online pawns cannot be adopted.

The retinue holds two members per save slot. Adopting a third pawn while a member is away offers to release that
member to make room: picking "Release Folken (away, Lv 28)" releases it and adopts the pawn. With nobody away, Adopt is
refused. Each save slot has its own retinue.

The same Adopt / Release actions are in the mod menu (REFramework → *Retinue*), which also shows the slot, each
member's status and level, and any warning.

### Progression

Members gain levels, discipline and vocation rank from any exp source, through the game's own exp curve, like the
main pawn; other hired pawns do not. Level-up and rank-up notifications name the pawn. A pawn that has been in the
party a while has **banked exp**: on its first grant it may jump several levels at once, with one notification. The
menu checkbox *Adopted pawns gain levels and vocation ranks* turns this off (on by default); turning it off reverts
nothing. If a game update renamed a hooked method, the menu says `<feature> unavailable: <method> not found (game
update?)` and that feature does nothing.

### Identity across dismiss, lost and re-hire

- Every member in the party has a **backup** of its progress (level, exp, stat increases, discipline, vocation exp),
  refreshed about every 10 s in the world when something changed.
- Dismissing a member at the Rift, or losing it any other way, marks it **away**. The Rift's Previous Hires lists it as
  "★ <name> · Lv N" with its backup's level. Hiring it again (from Previous Hires, the regular list, or meeting it in
  the world) **restores** its progress, and a notice says "<name> returned — Lv N restored", unless the game already
  has it at a higher level ("<name> returned — kept Lv M, newer than the backup").
- A member's Status page header reads "<name> · Retinue".
- On every load the retinue follows the loaded save: load an older save and the member is as that save has it (the
  save wins; the backup is lowered), except a save from before a Return, which gets the backup back.
- A new game (on its first save) or a restart over a slot archives that slot's retinue to `slots/<n>/archive-<date-time>/` and starts it
  empty. A new game plus keeps it.
- A notice shows once per load when the roster is damaged (the retinue is locked: nothing is written), written by a
  newer Retinue (read-only), or the save slot is unknown (the retinue is off for that session). A damaged backup gives
  a warning in the menu and log instead.

Nothing is written to the game's save by the mod: the gains and restores are made at runtime
([ADR 0001](docs/adr/0001-runtime-lift-not-save-injection.md)).

### Files

Everything the mod keeps is in `reframework/data/Retinue/`:

- `config.json`: the checkbox, created only when you change it. A hand-edited file with mistakes falls back to
  defaults, shows a warning in the menu and log, and is not overwritten until you change a setting.
- `slots/<n>/roster.json`: the members of save slot `<n>`.
- `slots/<n>/backups/<offline id>.json`: one backup per member.
- `slots/<n>/archive-<date-time>/`: archived retinues; never read or deleted by the mod.

### Uninstall and reinstall

- **Uninstall**: with the game closed, remove the scripts (`Retinue.lua` and the `Retinue/` folder in
  `reframework/autorun/`). Every save still loads and every pawn becomes an ordinary hired pawn: a member in the party
  keeps its level and progress; an away member comes back at the level it was first hired at, because its progress
  lives only in its backup.
- The mod never deletes `reframework/data/Retinue/`. Leaving it there is what makes a reinstall work. Deleting it by
  hand is the **clean uninstall**, and discards away members' backups for good.
- **Reinstall**: on the next load the retinue follows the save as above. A member that was re-hired while the mod was
  removed is recognised and restored.
- There is no "prepare for uninstall" step.

### Known limits

- Up to ~10 s of progress can be lost when a member is lost (its backup is the last refresh).
- Gear given to any hired pawn, adopted or not, is lost on dismiss and lost; equipment and skills are never restored
  (equipment is M4).
- Without the mod, an away member returns at its first-hire level; reinstalling restores it.
- A restored member comes back with its restored maximum health but the current health of its first-hire state until
  healed.
- A new game started while the mod is not installed is not seen: the old members become away and must be released.
  The same goes for *Reset scripts* between a new game and its first save.
- Texts are English only.

## Compatibility

- **Exp from other mods' multipliers**: exp may arrive already scaled by *Bestiary* (every recipient) or
  *SimpleDifficultyTweaks* (the player and the main pawn only). With an SDT EXP/DCP multiplier other than 1, adopted
  pawns progress at the vanilla rate while the main pawn is scaled. Known difference, not mirrored.
- **Grants made by other mods** through the game's exp path (for example UDD2P's Sphinx reward) level adopted pawns too.
- **Do not combine** Retinue with another mod that lifts the hired-pawn exp gate (such as *Arisen's Own*), or that
  hooks `ExpDispenser.checkLevelUp` / `ExpDispenser.addJobPoint`.
- **Logging**: some mods (NickCore) raise REFramework's global log level to `error`; Retinue logs its warnings as
  errors for that reason, and also shows them in its menu.

Details: [findings 0004](docs/findings/0004-other-mods-on-exp-path.md).

## Layout

| Path | Contents |
|---|---|
| `src/autorun/` | The mod itself: what gets installed into `reframework/autorun/` |
| `tools/probe/` | Read-only in-game inspectors used for research; not part of the mod |
| `tools/dump/` | Scripts to query the game's `il2cpp_dump.json` |
| `tools/saves.sh` | Back up and restore the save folder around in-game tests |
| `tests/` | Pure-Lua tests for logic that does not touch the game |
| `docs/` | Roadmap, decisions (ADRs), research findings, in-game test checklists |
| `CONTEXT.md` | Glossary of the domain terms used across code and docs |

## Development

```sh
./deploy.sh --probe       # symlink mod + probe into the game's reframework/autorun
./deploy.sh --probe-only  # the probe without the mod (uninstall checks)
./deploy.sh --remove      # remove those links; never touches reframework/data/Retinue
tests/run.sh              # pure-Lua tests (lua5.4), exits non-zero on failure
```

Game path defaults to `~/Documentos/Games/Dragon Dogma 2`; override with `DD2_DIR`.
After editing a linked script, use *ScriptRunner → Reset scripts* in the REFramework menu.
`./deploy.sh --experiments` links the hook experiments **instead of** the mod: the two hook the same methods and are
never linked together.

Before any in-game test of code that changes game state, back up the save with `tools/saves.sh backup <label>`;
see [docs/testing.md](docs/testing.md).

## Requirements

- Dragon's Dogma 2 with REFramework (tested build: revision `d4611aef`)
- Game version: the one the current `il2cpp_dump.json` was taken from (2026-11-03)
