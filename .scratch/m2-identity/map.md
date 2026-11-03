# M2 — Identity and persistence (wayfinder map)

Label: wayfinder:map

## Destination

A spec for M2 in `spec.md`, ready for `/to-tickets`, plus the M2 in-game checklist in `docs/testing.md`.
Implementation, the 0.1.0 tag and release are past the destination (they go through `/to-tickets` → `/ship`).

## Notes

Domain: Dragon's Dogma 2 REFramework Lua mod "Retinue". Read `CONTEXT.md`, `docs/adr/0001-runtime-lift-not-save-injection.md`,
`docs/findings/0001-hired-pawn-baseline.md`, `docs/findings/api-map.md` and the M1 spec (`../m1-progression/spec.md`) first.
Skills: `grilling` + `domain-modeling` for grilling tickets; `research` for research tickets; `prototype` for prototype tickets.
Conversation with the user in Spanish; every file in English.
Project vision (beyond this map): building your own party of pawns.

Settled while charting (2026-11-03):

- Scope: the five roadmap bullets for M2: roster file format and validation; adopt and release; behaviour on
  dismiss, lost and re-hire; JSON backup of each adopted pawn's state with restore when the game's copy is gone
  (may shrink if the game keeps everything, decided in a ticket); the uninstall guarantee.
- **The roster narrows M1**: only adopted pawns progress; ordinary hired pawns are vanilla again. The M1
  `progression` toggle stays as a global switch.
- **Offline pawns only** (owner `CAPCOM`, with `_OfflineID`).
- **Roster holds at most 2** (the party is main pawn + two adopted). A constant in one place, so it can grow later.
  An away pawn (dismissed or lost) keeps its place in the roster.
- **Adopt** only a hired pawn currently in the party. Where it is triggered from should feel native; the mod menu is
  the baseline and fallback (see the native-UI tickets).
- **Release** (with confirmation): leaves the roster, stays in the party as an ordinary hired pawn with its level,
  its backup is deleted, it stops progressing.
- **Dismiss and lost do not release**: the pawn stays in the roster as away, meant to come back with its progress
  (restored from backup if the game lost it). Feasibility is what the experiments establish.
- Method as in M1: game questions are answered by **experiment scripts** in `tools/experiments/`; every in-game run
  does `tools/saves.sh backup <label>` first and a findings note after.

## Decisions so far

<!-- one line per resolved ticket: - [<title>](issues/NN-slug.md): <gist> -->

## Not yet specified

- **What the backup holds, and when it is taken and restored**: hangs on what the game discards on dismiss/lost and
  whether a re-hired pawn comes back as the same character. Also whether restoring (writing level/exp/vocation into
  a re-hired pawn's contexts) stays within ADR 0001, or needs a new ADR.
- **How an away pawn comes back**: via the Rift as the game offers it, or a mod-driven re-hire; and for a lost
  pawn, whether the game ever offers it again.
- **Roster vs. save drift**: restoring an older save (or `tools/saves.sh restore`) while the roster says otherwise;
  how the roster is validated against the loaded save.
- **The uninstall guarantee**: how it is verified for adopted and away pawns (checklist shape).
- **Menu / status for the roster**: present and away entries, release confirmation; shape follows the native-UI decision.

## Out of scope

- Online pawns (owner with `_UserId`): perhaps later, only if adopting has no effect on the owner. Not in M2.
- The main pawn: never altered.
- Spending discipline, vocation change, augments: M3.
- A roster larger than the party (rotation of more than two adopted pawns).
