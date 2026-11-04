# What does a pawn's backup hold, and when is it written?

Type: grilling
Status: open
Blocked by: 07

## Question

Per "Run the dismiss / lost / re-hire experiment in game", the game keeps no progress past dismiss or lost, a re-hired
pawn returns at its first-hire level with regenerated equipment, and lost has no reliable last-read hook. Decide:
which fields the backup holds (level, exp, discipline, per-vocation ranks and culmative exp, current vocation,
equipment, skills, anything for display), when it is written (on save, on level-up, on a timer, at `dismissPawn` pre),
where it lives relative to the roster file, and what is restored versus only shown. Whether writing these into a
re-hired pawn's contexts stays within ADR 0001 or needs a new ADR is part of the question.
