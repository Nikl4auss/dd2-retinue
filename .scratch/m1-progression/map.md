# M1 — Progression (wayfinder map)

Label: wayfinder:map

## Destination

**Reached 2026-11-03**: [spec.md](spec.md) and the M1 checklist in `docs/testing.md`. Next: `/to-tickets`.

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
- Progression starts **when the hook becomes active**. No retroactive exp or discipline from the mod; exp the game
  itself banked while the pawn was blocked is applied as-is (see Decide the M1 hook set).
- Parity with the main pawn: **the game's own exp curve and per-level stat gains**. No balance options in M1.
- M1 covers **level, discipline and the current vocation's rank**.
- Never hook `app.PawnUtil.isSubPawn` (used by guild, equipment, Rift). Overrides apply only to CharacterIDs
  that are currently hired pawns in the party. (`ExpDispenser.isSubPawn` turned out to be ineffective: see
  Decisions so far.)
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
- [Run variant 1 (`isSubPawn` alone) in game](issues/03-run-variant-1.md): `isSubPawn` alone does nothing; the ID
  rewrite in `checkLevelUp` + `addJobPoint` is what works; the Boolean only toggles the (wrongly named)
  notification; main pawn unaffected; gains persist. Findings 0002.
- [Decide the M1 hook set](issues/04-decide-hook-set.md): rewrite the ID to `ch100000_00` in `checkLevelUp` +
  `addJobPoint` for hired party pawns; notification by swapping the real ID back in `dispLevelUpUI` /
  `reqJobRankUp`, silent as fallback; banked exp applies as-is.
- [Run variant 4: notification swap-back and rank-up](issues/05-run-variant-4.md): swap-back gives the right name
  on both notifications (no fallback needed); hired rank-up works and persists; one unexplained, unreproduced
  freeze on load. Findings 0003.
- [Do installed mods hook or call the exp path Retinue rewrites?](issues/06-other-mods-on-exp-path.md): no conflict;
  nothing hooks the rewritten/swapped members or lifts the gate; SDT and Bestiary scale exp upstream on the real ID.
  Keep the rewrite on the leaves and scope the swap-back strictly. Findings 0004.
- [Decide the shape of `config.json` and the M1 mod-menu section](issues/07-config-and-menu-shape.md): flat
  `{ version: 1, progression: true }`, per-key fallback, written only on change; toggle acts immediately; menu shows
  checkbox, status line of hired pawns in party, and a hook-failure notice.

## Not yet specified

(none: every decision is made; the next step is writing the M1 spec and checklist, i.e. the destination)

## Out of scope

- Online pawns (owner with `_UserId`): the mod targets offline play.
- The main pawn: never altered.
- Dismissal, loss and re-hire from the Rift: M2.
- Spending discipline, changing vocation, augments: M3.
