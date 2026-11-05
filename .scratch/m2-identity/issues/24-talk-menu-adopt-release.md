# 24: Adopt and Release from the pawn's talk menu

Parent: [M2 spec](../spec.md) (§ Adopt and Release (native))

**What to build:** talking to a hired party pawn shows a fifth row, "Adopt" or "Release (Retinue · Lv N)"; picking it opens the
game's Yes/No dialog inside the talk (with the gear warning on Adopt), acts on Yes and ends the talk like Never mind.
Refusals (full, locked, read-only, no slot) show a notice.

**Blocked by:** [23: Native notices](23-native-notices.md)

**Status:** ready-for-agent

- [ ] Row only on the root party-pawn talk node (by node id or Dismiss choice); never in sub-menus or for a pawn outside the party; not added for non-adoptable pawns; unrecognised node → menu vanilla.
- [ ] Pick redirected to Never mind before the game maps it.
- [ ] `requestDialog` Yes/No opened before the talk ends; answer read from the widget.
- [ ] If the confirming press leaks to the character, switch to the talk-menu confirm fallback ("Confirm adopt" / "Confirm release" + Never mind) and record it.
- [ ] Same roster rules and errors as the mod menu; texts from `labels`.
- [ ] Verified in game (checklist 2–4, 7): adopt and release natively, no jump or pawn command on confirm.
