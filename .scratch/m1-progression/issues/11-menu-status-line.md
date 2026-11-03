# 11: Menu status line

Parent: [M1 spec](../spec.md) (§ Menu)

**What to build:** the *Retinue* menu shows which party pawns progression applies to right now. The user can see at a
glance that the mod is acting, and for whom.

**Blocked by:** [08: Hired pawns level up](08-hired-pawns-level-up.md)

**Status:** ready-for-agent

- [ ] `Applies to: <name> (Lv <level>, <vocation> R<rank>), ...` for current targets. `No hired pawns in party` when
      there are none, and `Load a save` when the pawn manager is not available.
- [ ] Vocation names follow the glossary. Names come from the game's GUI name lookup, as in the experiment script.
- [ ] The line follows party changes (a pawn swapped at the Rift) without *Reset scripts*.
- [ ] Line formatting is pure and tested, including the empty and no-save cases.
- [ ] Shown whatever the checkbox state. Coexists with the `Progression unavailable` notice.
