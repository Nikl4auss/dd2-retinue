# 08: Hired pawns level up

Parent: [M1 spec](../spec.md) (§ Targets, § Progression hooks, § Failure handling, § Code layout and tests)

**What to build:** the first mod code. With the mod deployed, every hired pawn in the party gains levels, discipline
and vocation rank from any exp source, through the game's own curve. The mod does this by putting the main pawn's
fixed CharacterID in place of the target's ID in the two `ExpDispenser` leaves (`checkLevelUp`, `addJobPoint`).
Notifications still name the main pawn at this stage; [09](09-notifications-name-hired-pawn.md) fixes that.

The *Retinue* menu section has the progression checkbox (held in memory only, on at load) and the
`Progression unavailable: <method> not found (game update?)` notice. Install is all or nothing over these two
hooks. Set up the pure-Lua test runner the spec describes, and the entry script and module layout every later
ticket builds on.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [x] Targets: a party pawn whose ID is not the main pawn's and for which `PawnUtil.isSubPawn` (called, never hooked)
      is true. Membership is refreshed at least once per frame. The predicate is a single replaceable function (M2).
- [x] Only `checkLevelUp` and `addJobPoint` are hooked. Never `addExpAndJobPoint` and never any `isSubPawn`. Only the ID
      argument changes: the Boolean, exp and job points are untouched, and there is no multiplier.
- [x] With the checkbox off, the hooks do nothing. The change takes effect on the next call.
- [x] Hook bodies run under `pcall` and always call the original. On an error the args are left as passed, and the
      error is logged once per method and message.
- [x] If either method is missing, progression is unavailable for the session and the menu notice lists the method.
- [x] Deploy links the mod's module folder as well as the entry script.
- [x] The test runner runs every test script with `lua5.4` and exits non-zero on failure. The target logic is covered
      wherever it is pure.
- [ ] Verified in game by the user (experiment script not deployed): after one fight, a hired pawn gains discipline
      and levels when its exp allows, and the main pawn is unchanged.

## Comments

- 2026-11-03: implemented in `d81211c` (plan: [../plan.md](../plan.md)). In game, the user confirmed that a hired
  pawn levels up after a fight and gets the level-up notification, which still names the main pawn (expected
  until 09). Still to confirm: discipline gained, and the main pawn unchanged. Deferred by the user until the menu status
  line ([11](11-menu-status-line.md)) shows those numbers; not checked with the probe.
- 2026-11-03: with the status line from 11, the user confirmed in game that hired pawns gain discipline after a
  fight. Remaining: the main pawn unchanged.
