# M1 — Progression (wayfinder map)

Label: wayfinder:map

## Destination

A spec for M1, ready for `/to-tickets`, plus the M1 in-game checklist in `docs/testing.md`.
Implementation is past the destination (it goes through `/to-tickets` → `/ship`).

## Notes

Domain: Dragon's Dogma 2 REFramework Lua mod "Retinue". Read `CONTEXT.md`, `docs/adr/0001-runtime-lift-not-save-injection.md`,
`docs/findings/0001-hired-pawn-baseline.md` and `docs/findings/api-map.md` first.
Skills: `grilling` + `domain-modeling` for grilling tickets; `research` for research tickets.
Conversation with the user in Spanish; every file in English.

Settled while charting (2026-11-03):

- M1 applies to **every hired pawn in the party**, behind a mod-menu toggle. Gating by the roster arrives in M2.
- The toggle is **on by default** and persisted in `reframework/data/Retinue/config.json`, separate from the roster.
  Turning it off reverts nothing (levels already gained stay, per ADR 0001).
- Progression starts **when the hook becomes active**. No retroactive exp or discipline.
- Parity with the main pawn: **the game's own exp curve and per-level stat gains**. No balance options in M1.
- M1 covers **level, discipline and the current vocation's rank**.
- Hook only **`app.ExpDispenser.isSubPawn`**, never `app.PawnUtil.isSubPawn` (used by guild, equipment, Rift),
  and only for CharacterIDs that are currently hired pawns in the party.
- Questions are answered by an **experiment script** in `tools/experiments/` (not part of the mod) with the hook
  variants togglable from the menu: (1) `isSubPawn` alone, (2) + ID rewrite in `checkLevelUp`,
  (3) + ID rewrite in `addJobPoint`. Run in order; go further only if the previous variant falls short.
  Every run: `tools/saves.sh backup <label>` first, a findings note after.

## Decisions so far

<!-- one line per resolved ticket: - [<title>](issues/NN-slug.md): <gist> -->

- [How does the game compute level-up, and what is `HumanStatusContext.Exp`?](issues/01-level-up-internals.md):
  Exp is per-level progress; the ID only gates and labels, so `isSubPawn` alone likely suffices for real hired-pawn
  IDs; rank follows `CulmativeExp`. Inferred from signatures; the experiment confirms.
- [Build the hook-variant experiment script](issues/02-build-hook-experiment.md): `tools/experiments/Retinue_Exp_Hooks.lua`
  + `deploy.sh --experiments`; procedure in `tools/experiments/README.md`. Built and mock-tested, not yet run in game.

## Not yet specified

- Does the level-up notification name the right pawn, and what to do if it doesn't? (Observed in the variant 1 run.)
- Would an ID rewrite in `checkLevelUp` / `addJobPoint` also add exp or discipline to the main pawn?
- Do gained levels survive save/load, and stay when the hook is turned off?
- Interaction with other active mods that touch experience or skills.
- Exact shape of `config.json` and of the mod-menu section.

## Out of scope

- Online pawns (owner with `_UserId`): the mod targets offline play.
- The main pawn: never altered.
- Dismissal, loss and re-hire from the Rift: M2.
- Spending discipline, changing vocation, augments: M3.
