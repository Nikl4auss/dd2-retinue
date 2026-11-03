# What tools can speed up in-game testing?

Type: research
Status: resolved

## Question

M1 testing was slow: every check needed real play (fights for exp, travel to the Rift). M2 needs many more
hire / dismiss / lost / re-hire / save-load cycles. Find tools that shorten these loops, from primary sources
(Nexus Mods pages, tool repos and docs, REFramework docs):

1. DD2 save editors: can they read/edit hired-pawn state (level, exp, vocation, offline ID) in the save? Do they
   work on the current game version? Useful at least as a read-only inspector of what the save holds.
2. REFramework Lua mods or Cheat Engine tables that give exp, teleport (to a Rift stone), hire/dismiss pawns,
   kill/revive a pawn, or skip time (for the "lost" condition).
3. Whether extending our own `tools/probe/Retinue_Probe.lua` with test actions (grant exp, call
   `PawnManager.dismissPawn`, force lost) is simpler and safer than any of the above.

Output: a recommendation (what to adopt, what to build), with risks (save corruption, version mismatch, conflicts
with the mod's hooks). Adopting or building a tool may become a task ticket.

## Answer

Findings: `docs/findings/research-m2-test-tooling.md` on branch `research/m2-test-tooling` (commit `70dd0cf`, never merged).

- Use what is installed: Nick's Devtools and the Content Editor devtools give teleport (`TimeSkipManager.requestPlayerWarp`),
  time skip, enemy spawn/kill for exp, and "Kill pawns" (lost setup). To verify in the first experiment: does "Kill
  pawns" fire `PawnManager.lost`/`onLost`; does a spawned Big Riftstone open the hire screen.
- Build a small test-actions script in `tools/experiments/` (not the probe, which stays read-only): grant exp via
  `ExpDispenser.addExpAndJobPoint`, dismiss via `PawnManager.dismissPawn`, force lost via `PawnManager.lost(id, bool, bool)`
  (bool meaning unknown). Hooks nothing, so it can be linked alongside the mod. Folded into the experiment-build ticket.
- Fixture saves via `tools/saves.sh backup fixture-<state>`, restored before each cycle.
- Save editors: not for editing (DD2 Save Manager is Windows/main-pawn only); ree-save-editor optional as a read-only
  inspector of a copied backup. Never write a save. Cheat Engine tables and WeMod rejected.
- Risks: direct dismiss/lost calls may skip the game's own flow, so every checklist run still does one real Rift
  dismiss and one real death; granted exp is not scaled by Bestiary; LeovvayGore hooks `setPawnLostTimer`/`pawnLost`.
