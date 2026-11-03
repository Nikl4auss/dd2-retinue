# Build the dismiss / lost / re-hire experiment script

Type: task
Status: resolved
Blocked by: 01, 02

## Question

Build an experiment script in `tools/experiments/` (not part of the mod) that snapshots a pawn's full state
(CharacterID, offline ID, level, exp, discipline, vocation and ranks, equipment, name) before and after dismiss,
lost, re-hire and save/load, and writes it to JSON, using the test tooling chosen in "What tools can speed up
in-game testing?" and the hook points from "What does the game do to a hired pawn on dismiss, lost and re-hire?".
Include a test-actions panel (grant exp via `ExpDispenser.addExpAndJobPoint`, dismiss via
`PawnManager.dismissPawn`, force lost via `PawnManager.lost`), hooking nothing, so it can run alongside the mod.
Document the procedure, including fixture saves (`tools/saves.sh backup fixture-<state>`), in `tools/experiments/README.md`. Mock-test what can be tested outside the game.

## Answer

Done 2026-11-03. Not yet run in game (that is "Run the dismiss / lost / re-hire experiment in game").

- `tools/experiments/Retinue_Exp_Lifecycle.lua`: menu node "Retinue Lifecycle (EXPERIMENT)". 37 log-only hooks
  (every section-4 hook point of the internals research, plus `registPawn`/`unregistPawn`), pcall-guarded, never
  altering args or return; full pawn state read in the `pre` of `dismissPawn`/`lost`/`pawnLost`. Chatty hooks collapse
  and are capped per hook (2000).
- Snapshots (manual, and deferred automatic ones after dismiss, lost, hire, Rift start/end and each test action) of
  the party and every pawn seen this session (record existence via `hasRecord` / `CharacterID2Keys`), plus the Rift's
  dismissed list, `_SavedPartyPawnList`, `_PawnLostTimers`, `StrayPawnPastInformationMax`, `RelationPawnDismissNum`.
- Test actions (grant exp, dismiss, force lost with both bools), two-click confirm bound to the armed CharacterID,
  main pawn and player refused; run in `re.on_pre_application_entry("UpdateBehavior")`, not the render thread.
- Output `reframework/data/Retinue/experiments/lifecycle_<ts>.json`. `./deploy.sh --lifecycle` links it alongside
  the mod and the probe (`--experiments` stays exclusive with the mod).
- Procedure (a)–(g) with fixture saves in `tools/experiments/README.md`; restore uses the `<timestamp>-<label>`
  name and run files are copied out before each restore (restore wipes `reframework/data/Retinue`).

Checked outside the game: `luac5.4 -p`, a mocked-API run (128 checks), `deploy.sh` against a throwaway game dir,
`tests/run.sh`. Reviewed (one round of fixes). In-game-only: `sdk.to_valuetype` for Guid args, `CharacterID2Keys`
lookup and dictionary iteration, boxed `StorageData._ItemId`, CAPCOM detection via zero `_UserId`, the
`NetworkManager` → `RelationPawnDismissNum` chain, calling `dismissPawn`/`lost` directly, flush cost.
