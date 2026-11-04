# How does the mod notice a member leaving and returning, and when does it act?

Type: grilling
Status: open
Blocked by: 10

## Question

Per "Can a backup be written into a re-hired pawn?" the restore itself is settled: one frame after `hirePawn` post,
into the live contexts, no save needed. Per "Run the dismiss / lost / re-hire experiment in game", dismiss has a reliable
`dismissPawn` pre, while lost has no single hook (with *Kill pawns*, `returnSubPawnItems` + `removeEquipData` fire at the
kill and the pawn leaves the party; the record lingers for minutes). Decide the mod's member status transitions and their
triggers: how a present member becomes away (dismiss hook; lost by a party diff in the 10 s poll, by
`returnSubPawnItems`/`removeEquipData`, or both), what the last backup read is in the lost case, how a Return is detected
and applied (the `hirePawn` post path, retries if the actor or contexts are not ready, the level guard), and what the mod
logs or shows at each step. The load-time case already decided in "What does a pawn's backup hold, and when is it
written?" (present in the save while the roster says away → present, no restore) stays as is.
