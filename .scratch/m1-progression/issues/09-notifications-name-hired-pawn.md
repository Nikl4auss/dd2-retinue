# 09: Notifications name the hired pawn

Parent: [M1 spec](../spec.md) (§ Notification swap-back, § Failure handling)

**What to build:** level-up and rank-up notifications for a hired pawn show its own name, once, instead of the main
pawn's. The mod puts the real ID back in `ExpDispenser.dispLevelUpUI` and `GuiManager.reqJobRankUp`, but only while a
rewritten `checkLevelUp` / `addJobPoint` call is open. The player's and the main pawn's own notifications are never
touched.

**Blocked by:** [08: Hired pawns level up](08-hired-pawns-level-up.md)

**Status:** ready-for-agent

- [ ] The core pre-hook pushes one frame per call, carrying the real ID only when it rewrote; the matching post-hook
      pops it. Stale frames are dropped when an outer post-hook pops, and the stack is cleared at the start of every
      game frame. (Amended from "push only when it rewrites"; see plan.md, Ticket 09.)
- [ ] The swap happens only when the incoming ID is the main pawn's fixed ID and the innermost open call was
      rewritten. It uses that call's real ID. Every other call passes through.
- [ ] On an error in a hook, the call's frame never carries a real ID (no renaming entry).
- [ ] Install is all or nothing over all four methods. Any missing method makes progression unavailable, with the
      menu notice.
- [ ] Pure tests of the swap decision: rewritten call open versus not, nested calls, a stale entry after a missing
      post-hook, frame reset, non-main IDs passing through.
- [ ] Verified in game by the user: a hired-pawn level-up shows its own name once, and a main-pawn level-up shows the
      main pawn's name.
