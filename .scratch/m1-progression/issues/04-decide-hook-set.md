# Decide the M1 hook set

Type: grilling
Status: open
Blocked by: 01, 03

## Question

Given the research on level-up internals and the variant 1 findings: is `ExpDispenser.isSubPawn` alone enough
for M1, or do `checkLevelUp` / `addJobPoint` (or `dispLevelUpUI`) need hooks too? If variant 1 falls short, which
further variant runs are needed before deciding?
