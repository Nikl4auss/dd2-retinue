# Decide the M1 hook set

Type: grilling
Status: open
Blocked by: 01, 03

## Question

Given the research on level-up internals and `docs/findings/0002-exp-hook-variants.md` (the ID rewrite in
`checkLevelUp` + `addJobPoint` works; `isSubPawn` alone does not; the Boolean is the notification flag and with
the rewrite the notification names the main pawn): what is the M1 hook set? In particular, how to handle the
notification (silent, re-raise `reqLevelUp` / `reqJobRankUp` with the hired pawn's ID, swap the ID back in
`dispLevelUpUI` / `reqLevelUp`, or accept the wrong name), and which further experiment runs, if any, are needed
before deciding (notification fix, rank-up).
