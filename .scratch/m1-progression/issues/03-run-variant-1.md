# Run variant 1 (`isSubPawn` alone) in game

Type: task
Status: resolved
Blocked by: 02

## Question

With the user playing, run the experiment script at variant 1 and record:

- First a short log-only fight, to see the call order before anything is overridden.
- Do the hired pawns level up? Several levels at once from banked exp? Does discipline grow? Does the current vocation's rank grow?
- Does the main pawn's exp/discipline change compared with the baseline (+1891 per the same fight)?
- Does the level-up notification appear, and for which pawn?
- After save → title → load: are the gains kept? With the variant set back to off: still kept?

Write `docs/findings/0002-<slug>.md` with data under `docs/findings/data/<date>-<topic>/`.

## Answer

Run 2026-11-03 with the user; went on to variant 3 and two split runs (Boolean only, ID only) in the same
session. Full write-up: `docs/findings/0002-exp-hook-variants.md`, data in `docs/findings/data/2026-11-03-exp-hooks/`.

- Variant 1 does nothing: the game never calls `ExpDispenser.isSubPawn` during exp distribution.
- Rewriting the CharacterID to the main pawn's in `checkLevelUp` and `addJobPoint` is necessary and sufficient:
  level (17 → 18 → 19), discipline and CulmativeExp grow. Forcing the Boolean false alone does nothing.
- The Boolean is the notification flag: true + rewritten ID shows "<main pawn> levelled up" once per hired pawn;
  false is silent.
- Main pawn unaffected. Gains survive save/load and a full relaunch with no hook.
- Not reached: a hired pawn's vocation rank-up (should follow CulmativeExp; unverified).
