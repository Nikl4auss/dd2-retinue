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
  (required: the game keeps no progress past dismiss); the uninstall guarantee.
- **The roster narrows M1**: only adopted pawns progress; ordinary hired pawns are vanilla again. The M1
  `progression` toggle stays as a global switch.
- **Offline pawns only** (owner `CAPCOM`, with `_OfflineID`).
- **Roster holds at most 2** (the party is main pawn + two adopted). A constant in one place, so it can grow later.
  An away pawn (dismissed or lost) keeps its place in the roster.
- **Adopt** only a hired pawn currently in the party. Where and how: see "How should adopt and release look and feel?".
- **Native first** (2026-11-04): everything the player needs must be doable fluidly in the game itself. The REFramework
  mod menu is a development convenience and a fallback, never a required surface.
- **Release** (with confirmation): leaves the roster, stays in the party as an ordinary hired pawn with its level,
  its backup is deleted, it stops progressing.
- **Dismiss and lost do not release**: the pawn stays in the roster as away, meant to come back with its progress
  (restored from backup if the game lost it). Feasibility is what the experiments establish.
- Method as in M1: game questions are answered by **experiment scripts** in `tools/experiments/`; every in-game run
  does `tools/saves.sh backup <label>` first and a findings note after.

## Decisions so far

<!-- one line per resolved ticket: - [<title>](issues/NN-slug.md): <gist> -->

- [What tools can speed up in-game testing?](issues/01-test-tooling.md): use the installed Nick's Devtools /
  Content Editor (teleport, time skip, spawn, kill pawns) + our own test-actions script (exp, dismiss, lost) + fixture
  saves; save editors read-only at most. Branch `research/m2-test-tooling`.
- [Which native UI entry points could host adopt and release?](issues/05-native-ui-entry-points.md): the mod menu
  stays the complete surface (away pawns are unreachable in world); best native spot is the hired pawn's talk menu
  (reuse a slot), fallback a Status-page button; release confirms via the game's own dialog. Branch `research/m2-native-ui`.
- [What does the game do to a hired pawn on dismiss, lost and re-hire?](issues/02-dismiss-lost-rehire-internals.md):
  CharacterIDs are reused (observed), dismiss likely deletes the whole record, the Rift keeps only generation data
  (offline ID, look, skills, job, `Level`): progress is not kept, so the mod's backup is required. Lost path inferred.
  Branch `research/m2-dismiss-lost-rehire`.
- [Build the dismiss / lost / re-hire experiment script](issues/03-build-lifecycle-experiment.md): built
  `tools/experiments/Retinue_Exp_Lifecycle.lua` (log-only hooks, snapshots, test actions), linked with the mod via
  `./deploy.sh --lifecycle`; procedure with fixture saves in `tools/experiments/README.md`.
- [Run the dismiss / lost / re-hire experiment in game](issues/04-run-lifecycle-experiment.md): re-hire keeps the
  OfflineID but gets a new CharacterID; dismiss deletes the record at once, lost later; the pawn returns via the Rift's
  "previously hired" list (lost too) at first-hire level, exp 0, regenerated equipment. Findings 0006.
- [How should adopt and release look and feel?](issues/06-adopt-release-ux.md): a fifth entry ("Adopt"/"Release") in
  the party pawn's root talk menu, confirmed by the game's own dialog opened before the talk ends (fallback: confirm in
  the talk menu); a full retinue offers to release an away member natively; native first, mod menu only for dev and
  fallback. Findings 0007.

## Not yet specified

- **Mod-side detection and restore flow**: how the mod notices adopt-relevant events (dismiss pre, `hirePawn` post by
  OfflineID, lost with no single hook) and drives restore and away/present status; shape depends on the backup and
  restore tickets.
- **Roster vs. save drift**: restoring an older save (or `tools/saves.sh restore`) while the roster says otherwise;
  how the roster is validated against the loaded save.
- **The uninstall guarantee**: how it is verified for adopted and away pawns (checklist shape).
- **Native roster status**: where the player sees, in game, who is adopted and who is away (and why an away
  pawn can't be adopted twice), and how an away pawn's return is presented (the Rift's "previously hired" list). The mod
  menu shows the same for development and as a fallback.

## Out of scope

- Online pawns (owner with `_UserId`): perhaps later, only if adopting has no effect on the owner. Not in M2.
- The main pawn: never altered.
- Spending discipline, vocation change, augments: M3.
- A roster larger than the party (rotation of more than two adopted pawns).
