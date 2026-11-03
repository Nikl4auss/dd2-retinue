# 0002 — Lifting the hired-pawn exp gate: which hooks work

Date: 2026-11-03 · Tool: `tools/experiments/Retinue_Exp_Hooks.lua` · Raw data: [data/2026-11-03-exp-hooks/](data/2026-11-03-exp-hooks/)
(`run_20261103_100706.json`: log-only, variant 1, variant 3; `run_20261103_104942.json`: after a full relaunch,
Boolean-only and ID-only runs).

Offline play, same save and party as [0001](0001-hired-pawn-baseline.md): main pawn Shaira (2283028347), hired
Alder (1601809365) and Clothilde (1306736823), player Klauss (2891076981). Backups taken:
`20261103-100411-m1-variant1` (before any run) and `m1-variant3` (after the variant 3 run).

## Procedure

1. Log-only fight (variant 0).
2. Variant 1 (`ExpDispenser.isSubPawn` → false for hired pawns), one fight.
3. Variant 3 (ID rewritten to the main pawn's in `checkLevelUp` and `addJobPoint`, Boolean forced false), one fight.
4. Save, title, load. Quit the game, relaunch with no override (variant 0), load.
5. Variant 3 with only the Boolean forced false (real ID kept), one fight.
6. Variant 3 with only the ID rewritten (Boolean untouched), one fight.

## Results

### Call order (identical for main pawn, player and hired pawns)

```
addExpAndJobPoint(id, exp, chara, damageInfo)
 └ addExpAndJobPoint(id, exp, jobPoint, chara)      exp already added to HumanStatusContext before checkLevelUp
    ├ checkLevelUp(id, hs, job, flag=true, dh)
    │  └ dispLevelUpUI(id, newLv, oldLv)            only on a level-up, only when flag is true
    │     └ GuiManager.reqLevelUp(id, oldLv, newLv)
    └ addJobPoint(id, jc, jobPoint, flag=true)
       └ addJobPointInternal(id, job, jc, jobPoint, flag)   discipline + CulmativeExp[job]
          (rank-up: GuiManager.reqJobRankUp(id, job, oldRank, newRank))
```

The 7-argument `addExpAndJobPoint` overload was never called in combat. `dispLevelUpUI`'s two ints are
`(newLv, oldLv)`, the reverse of `reqLevelUp`.

### Per run (hired pawns; both behaved identically)

| Run | Level | Discipline / CulmativeExp | Notification | Evidence |
|---|---|---|---|---|
| Log-only | 17, no change | 0 | none | `addJobPoint` called, never reaches `addJobPointInternal` |
| Variant 1 (`isSubPawn`) | 17 with 9429 exp (9400 needed) | 0 | none | `ExpDispenser.isSubPawn` **never called by the game** (0 calls); the override works when called from Lua |
| Variant 3, ID + Boolean false | 17 → **18** | 0 → 344 | **none** | `checkLevelUp` did not call `dispLevelUpUI` |
| Save/title/load, then full relaunch at variant 0 | **18 kept** | 344 kept | — | `auto:start` snapshot of the relaunched session |
| Boolean false only (real ID) | 18 with 17035 exp (10400 needed) | 344, no change | none | 208 hired calls, none changed anything |
| ID only (Boolean untouched) | 18 → **19** | 344 → 379 | **"Shaira" levelled up**, shown twice | `dispLevelUpUI` / `reqLevelUp` called with the main pawn's ID |

Main pawn: in every run its level, exp, discipline and CulmativeExp moved only by its own grants, never by the
hired pawns' (e.g. variant 3: +344 discipline, the same as each hired pawn, from its own calls). The rewritten
calls change the contexts passed in, not the main pawn's.

Exp curve: `LVupParams` has 998 entries; the entry with `Level = N` is the exp needed within level N−1 to reach
N (Shaira: 10626 exp at level 16 → level 17 with 2176 left = 10626 − 8450, entry `Level 17`).

## Conclusions

1. **`ExpDispenser.isSubPawn` is not the gate in practice.** The game never calls it during exp distribution
   (probably inlined into `checkLevelUp` / `addJobPoint`), so hooking it does nothing. Map variant 1 is dead.
2. **Rewriting the CharacterID to the main pawn's in `checkLevelUp` and `addJobPoint` is necessary and
   sufficient** for level and for discipline + CulmativeExp. The Boolean plays no part in the gate.
3. **The Boolean is the "show notification" flag.** With it true, the notification uses the passed ID, so with
   the rewrite it names the main pawn (once per hired pawn); with it false, the level-up is silent.
4. **Gains persist** through save/load and a full relaunch with no hook active (consistent with ADR 0001).
5. **The main pawn is not affected** by the rewrite.
6. `Exp` is progress within the current level (confirmed; was inferred in the research).

## Open questions

- Vocation rank-up for a hired pawn was not reached (CulmativeExp 2800 → 3144 at rank 4). Rank is derived from
  CulmativeExp, so it should follow; its notification (`reqJobRankUp`) would likely also carry the main pawn's ID.
- How to show a correct notification: e.g. rewrite with the Boolean false and raise `GuiManager.reqLevelUp` /
  `reqJobRankUp` ourselves with the hired pawn's ID, or swap the ID back in `dispLevelUpUI` / `reqLevelUp`.
  Untested: whether those accept a hired pawn's ID (name lookup).
- Whether other code reached from `checkLevelUp` keys anything else on the (rewritten) ID, e.g. pawn chatter
  `PawnPartyCombatInfo.setLevelUp(id)`. Nothing visible went wrong in these runs.
