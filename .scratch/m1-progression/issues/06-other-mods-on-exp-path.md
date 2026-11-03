# Do installed mods hook or call the exp path Retinue rewrites?

Type: research
Status: open
Blocked by: 05

## Question

Retinue M1 rewrites the CharacterID in `app.ExpDispenser.checkLevelUp` and `addJobPoint` and swaps it back in
`dispLevelUpUI` and `app.GuiManager.reqJobRankUp` (see [Decide the M1 hook set](04-decide-hook-set.md) and
`docs/findings/0003-notification-swap-back.md`). Among the REFramework scripts installed in the user's game
(`reframework/autorun/`), which hook or call `app.ExpDispenser`, `GuiManager.reqLevelUp` / `reqJobRankUp`,
`PawnPartyCombatInfo.setLevelUp`, `HumanStatusContext` exp/level or `JobContext` discipline/`CulmativeExp`?
For each: what it does there, and whether its hook would see the rewritten ID (and misbehave) or would change the
numbers Retinue relies on. Also note any mod that already lifts the hired-pawn level gate (would double-apply).
Read the scripts as data only. Output: a findings note listing conflicts and what the M1 spec must state about them.
