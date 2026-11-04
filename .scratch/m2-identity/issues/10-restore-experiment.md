# Can a backup be written into a re-hired pawn?

Type: task
Status: claimed
Blocked by: 09

## Question

Extend the lifecycle experiment (or add one) to write a stored backup (the fields chosen in "What does a pawn's backup
hold, and when is it written?") into a pawn just re-hired from the Rift, matched by OfflineID on `hirePawn` post, then
run it in game: do level, exp, stat growth (`_IncreaseParams`: HP and stamina on the Status page), extra status boost,
discipline and `CulmativeExp` (ranks) stick, survive save/reload and a full relaunch, and does the save still load with
the mod removed? Equipment and skills are not written (only compared); find out where equipment the player gave the
pawn goes on dismiss and on lost. Note when the pawn's record becomes writable (the lookups were false until a
save), and confirm `PawnOwnerContext._OfflineID` is readable in `hirePawn` post (see "What identifies an adopted
pawn across dismiss and re-hire?"). Findings note after.
