# Build the dismiss / lost / re-hire experiment script

Type: task
Status: open
Blocked by: 01, 02

## Question

Build an experiment script in `tools/experiments/` (not part of the mod) that snapshots a pawn's full state
(CharacterID, offline ID, level, exp, discipline, vocation and ranks, equipment, name) before and after dismiss,
lost, re-hire and save/load, and writes it to JSON, using the test tooling chosen in "What tools can speed up
in-game testing?" and the hook points from "What does the game do to a hired pawn on dismiss, lost and re-hire?".
Document the procedure in `tools/experiments/README.md`. Mock-test what can be tested outside the game.
