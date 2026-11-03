# Do installed mods hook or call the exp path Retinue rewrites?

Type: research
Status: resolved
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

## Answer

See `docs/findings/0004-other-mods-on-exp-path.md`. No installed mod hooks `checkLevelUp`, `addJobPoint`,
`dispLevelUpUI`, `reqLevelUp`, `reqJobRankUp` or `setLevelUp`, and none lifts the hired-pawn gate (Arisen's Own
folder is empty). The only exp hooks sit upstream on `addExpAndJobPoint` and always see the real ID:
SimpleDifficultyTweaks scales EXP/DCP for player and main pawn only (current preset 1.0/1.0), Bestiary scales
combat exp per enemy for all recipients. UDD2P grants Sphinx exp to hired pawns via `addExpAndJobPoint` (covered
by the leaf hooks); SkillCreator calls `addJobPointInternal` for the player (bypasses the rewrite). Spec: keep the
rewrite on the leaves, never upstream; scope the swap-back to "ID is `ch100000_00` and a rewritten call is open";
take exp as passed (no Retinue multiplier; SDT not mirrored onto adopted pawns in M1).
