# Retinue (working title)

A Dragon's Dogma 2 REFramework Lua mod, for local/offline use: adopt up to three pawns that
level up, change vocation, take equipment and can be renamed, like the main pawn.

It is a replacement for the author's use of *Arisen's Own*, built on a different principle:
**adopted pawns stay hired pawns as far as the game's save is concerned**, and the mod only lifts
the restrictions placed on hired pawns at runtime. See [ADR 0001](docs/adr/0001-runtime-lift-not-save-injection.md).

## Status

Nothing released yet (0.0.0). M0 (research) is done. M1 (progression) is implemented and its in-game checklist is
being run; 0.1.0 will be M1 + M2. See [docs/roadmap.md](docs/roadmap.md).

## What it does (M1)

Every hired pawn in your party gains levels, discipline and vocation rank from any exp source, through the game's own
exp curve, like the main pawn. Level-up and rank-up notifications show the hired pawn's name. Nothing is written to
the save by the mod: the gains are the game's own, made at runtime ([ADR 0001](docs/adr/0001-runtime-lift-not-save-injection.md)).

- A hired pawn that has been in the party a while has **banked exp**: on its first grant it may jump several levels at
  once, with one notification for the range.
- **Menu**: REFramework → *Retinue*. The checkbox *Hired pawns gain levels and vocation ranks* turns progression on or
  off (on by default; takes effect on the next exp grant). Turning it off reverts nothing. A status line lists the
  hired pawns it applies to, with level, vocation, rank and discipline. If a game update renamed a hooked method,
  the menu says `Progression unavailable: <method> not found (game update?)` and the mod does nothing.
- **Settings file**: `reframework/data/Retinue/config.json`, created only when you change the checkbox. A hand-edited
  file with mistakes falls back to defaults, shows a warning in the menu and the REFramework log, and is not
  overwritten until you change a setting.
- **Uninstall**: remove the scripts. The save still loads, and the pawns keep their levels as ordinary hired pawns.

## Compatibility

- **Exp from other mods' multipliers**: exp may arrive already scaled by *Bestiary* (every recipient) or
  *SimpleDifficultyTweaks* (the player and the main pawn only). With an SDT EXP/DCP multiplier other than 1, hired
  pawns progress at the vanilla rate while the main pawn is scaled. Known difference, not mirrored.
- **Grants made by other mods** through the game's exp path (for example UDD2P's Sphinx reward) level hired pawns too.
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
./deploy.sh --probe     # symlink mod + probe into the game's reframework/autorun
./deploy.sh --remove    # remove those links
tests/run.sh            # pure-Lua tests (lua5.4), exits non-zero on failure
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
