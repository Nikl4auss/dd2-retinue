# 11: Menu status line

Parent: [M1 spec](../spec.md) (§ Menu)

**What to build:** the *Retinue* menu shows which party pawns progression applies to right now. The user can see at a
glance that the mod is acting, and for whom.

**Blocked by:** [08: Hired pawns level up](08-hired-pawns-level-up.md)

**Status:** resolved

- [x] `Applies to: <name> (Lv <level>, <vocation> R<rank>, Disc <discipline>), ...` for current targets. `No hired pawns in party` when
      there are none, and `Load a save` when the pawn manager is not available.
- [x] Vocation names follow the glossary. Names come from the game's GUI name lookup, as in the experiment script.
- [x] The line follows party changes (a pawn swapped at the Rift) without *Reset scripts*.
- [x] Line formatting is pure and tested, including the empty and no-save cases.
- [x] Shown whatever the checkbox state. Coexists with the `Progression unavailable` notice.

## Comments

- 2026-11-03: implemented in `2649520`; discipline added to the line in `e8f1948` at the user's request (spec
  § Menu updated). In game the user saw the `Applies to:` line, with discipline rising after a fight. Not yet
  checked: the line following a Rift swap without *Reset scripts*.
- 2026-11-03: Rift-swap check still pending (only one hired pawn in the party during the test). Stays open for it.
- 2026-11-03: the user confirmed the line updates when a new pawn is brought from the Rift. All criteria met; closed.
