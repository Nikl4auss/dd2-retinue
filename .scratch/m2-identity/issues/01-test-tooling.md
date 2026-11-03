# What tools can speed up in-game testing?

Type: research
Status: open

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
