# How does the game compute level-up, and what is `HumanStatusContext.Exp`?

Type: research
Status: resolved

## Question

From primary sources (the type dump via `tools/dump/`, Arisen's Own scripts as API reference only, open-source DD2
mods that touch pawn progression), find out:

1. What `HumanStatusContext.Exp` holds: progress within the current level, or a running total? Where is the exp
   curve (exp needed per level) and how is it read?
2. What `app.ExpDispenser.checkLevelUp`, `addJobPoint` and `dispLevelUpUI` take and touch, and what part the
   CharacterID plays in each (why Arisen's Own rewrites it to the main pawn's).
3. How vocation rank grows from job points (`JobContext`), and whether it needs anything beyond `addJobPoint`.

Baseline data: main pawn Exp 5874 at level 16; hired pawns Exp 0 → 1891 at level 17 (findings/0001).

## Answer

Resolved 2026-11-03 from the type dump and Arisen's Own call sites (no method bodies in the dump, so behaviour is
inferred). Full notes: `docs/findings/research-m1-level-up-internals.md` on branch `research/m1-level-up-internals`
(commit `e6a6bdd`, not merged).

1. **Exp** is progress within the current level (high confidence): `LVupParameterUserData.getLVFromEXPandLevel`
   takes exp and level; the curve is `LVupParameterUserData.LVupParams` (`Level`, `RequiredEXP`), reachable via
   `CharacterManager.get_HumanParam().get_LVupInfo()`. Hired pawns bank exp while blocked, so lifting the gate may
   give several levels at once.
2. **`checkLevelUp` / `addJobPoint` / `dispLevelUpUI`** are static and act on the context passed in; the CharacterID
   drives the `isSubPawn` gate and the display (name on the notification), not whose numbers change (medium).
3. **Why Arisen's Own rewrites the ID**: its extra pawns had IDs (`ch100000_01/02`) the game cannot resolve, so it
   points them at the main pawn's `ch100000_00`. Our hired pawns have real IDs (`ch110006`, `ch110003`), so
   `isSubPawn` alone may suffice and the notification would name the right pawn (medium, untested).
4. **Vocation rank** is computed by `JobContext.calcJobRank` from `CulmativeExp[job]` and
   `JobRankParameter.JobParam.RequiredNextPoints`; `addJobPoint` → `addJobPointInternal` likely feeds both it and
   discipline (`ConsumableExp`), so nothing beyond the `addJobPoint` path should be needed (medium-high).
