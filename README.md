# Retinue (working title)

A Dragon's Dogma 2 REFramework Lua mod, for local/offline use: adopt up to three pawns that
level up, change vocation, take equipment and can be renamed, like the main pawn.

It is a replacement for the author's use of *Arisen's Own*, built on a different principle:
**adopted pawns stay hired pawns as far as the game's save is concerned**, and the mod only lifts
the restrictions placed on hired pawns at runtime. See [ADR 0001](docs/adr/0001-runtime-lift-not-save-injection.md).

## Status

Nothing released yet (0.0.0). Milestone M0 (research) is done; M1 (progression) is next. See [docs/roadmap.md](docs/roadmap.md).

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
```

Game path defaults to `~/Documentos/Games/Dragon Dogma 2`; override with `DD2_DIR`.
After editing a linked script, use *ScriptRunner → Reset scripts* in the REFramework menu.

Before any in-game test of code that changes game state, back up the save with `tools/saves.sh backup <label>`;
see [docs/testing.md](docs/testing.md).

## Requirements

- Dragon's Dogma 2 with REFramework (tested build: revision `d4611aef`)
- Game version: the one the current `il2cpp_dump.json` was taken from (2026-11-03)
