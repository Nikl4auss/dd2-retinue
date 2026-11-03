# Decide the M1 hook set

Type: grilling
Status: resolved
Blocked by: 01, 03

## Question

Given the research on level-up internals and `docs/findings/0002-exp-hook-variants.md` (the ID rewrite in
`checkLevelUp` + `addJobPoint` works; `isSubPawn` alone does not; the Boolean is the notification flag and with
the rewrite the notification names the main pawn): what is the M1 hook set? In particular, how to handle the
notification (silent, re-raise `reqLevelUp` / `reqJobRankUp` with the hired pawn's ID, swap the ID back in
`dispLevelUpUI` / `reqLevelUp`, or accept the wrong name), and which further experiment runs, if any, are needed
before deciding (notification fix, rank-up).

## Answer

Grilled with the user 2026-11-03.

1. **Core**: hook `ExpDispenser.checkLevelUp` and `ExpDispenser.addJobPoint`; when the CharacterID is a hired pawn
   currently in the party, rewrite it to the constant `ch100000_00` (2283028347, the main pawn's fixed ID, so it does
   not depend on the main pawn being present). No `isSubPawn` hook anywhere.
2. **Leaves, not the entry**: hooking those two leaves covers every exp source (combat, quests, items) and every
   `addExpAndJobPoint` overload, including the 7-argument one never seen in combat.
3. **Notification**: target is swap-back (c): leave the Boolean as the game passes it, remember the real ID in the
   pre-hook, and put it back in `dispLevelUpUI` and `GuiManager.reqJobRankUp`. Fallback if the GUI rejects a hired
   pawn's ID: silent (Boolean forced false). Re-raising ourselves and accepting the wrong name were rejected.
   Conditional on [Run variant 4: notification swap-back and rank-up](05-run-variant-4.md).
4. **Banked exp**: exp the game banked while the pawn was blocked is the game's own state, not retroactive exp from
   the mod; it is applied as-is, even if a long-hired pawn gains several levels at once. Never zeroed.
