# How does the game compute level-up, and what is `HumanStatusContext.Exp`?

Type: research
Status: claimed

## Question

From primary sources (the type dump via `tools/dump/`, Arisen's Own scripts as API reference only, open-source DD2
mods that touch pawn progression), find out:

1. What `HumanStatusContext.Exp` holds: progress within the current level, or a running total? Where is the exp
   curve (exp needed per level) and how is it read?
2. What `app.ExpDispenser.checkLevelUp`, `addJobPoint` and `dispLevelUpUI` take and touch, and what part the
   CharacterID plays in each (why Arisen's Own rewrites it to the main pawn's).
3. How vocation rank grows from job points (`JobContext`), and whether it needs anything beyond `addJobPoint`.

Baseline data: main pawn Exp 5874 at level 16; hired pawns Exp 0 → 1891 at level 17 (findings/0001).
