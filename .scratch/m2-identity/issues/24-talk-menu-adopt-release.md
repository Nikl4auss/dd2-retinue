# 24: Adopt and Release from the pawn's talk menu

Parent: [M2 spec](../spec.md) (§ Adopt and Release (native))

**What to build:** talking to a hired party pawn shows a fifth row, "Adopt" or "Release (Retinue · Lv N)"; picking it opens the
game's Yes/No dialog inside the talk (with the gear warning on Adopt), acts on Yes and ends the talk like Never mind.
Refusals (full, locked, read-only, no slot) show a notice.

**Blocked by:** [23: Native notices](23-native-notices.md)

**Status:** ready-for-agent

- [x] Row only on the root party-pawn talk node (by node id or Dismiss choice); never in sub-menus or for a pawn outside the party; not added for non-adoptable pawns; unrecognised node → menu vanilla.
- [x] Pick redirected to Never mind before the game maps it.
- [x] `requestDialog` Yes/No opened before the talk ends; answer read from the widget.
- [ ] If the confirming press leaks to the character, switch to the talk-menu confirm fallback ("Confirm adopt" / "Confirm release" + Never mind) and record it.
- [x] Same roster rules and errors as the mod menu; texts from `labels`.
- [ ] Verified in game (checklist 2–4, 7): adopt and release natively, no jump or pawn command on confirm.

## Comments

- 2026-11-08, `ac9fd94`, run 1 (headless, by the peer session): no row on either hired pawn, no log line. Trace build `e30a0c0`, run 2:
  the root node and the pawn read fine, `_Choices` unreadable through `get_elements()`. Fixed in `04f7aff`.
- 2026-11-08, `04f7aff`, run 3 (headless, F taps, Diamonds path): row "Adopt" after Never mind on the root node; Adopt No (nothing changes),
  Adopt Yes (member present with `character_id`, backup written), "Release (Retinue · Lv 24)" on the next talk, Release Yes (member gone, backup
  emptied), "Adopt" again; read-only roster: no dialog, the talk ends, notice "Cannot adopt Diamonds: the roster is read-only (written by a
  newer Retinue)" 1.5 s after the pick, 3 s. No leak on 4 confirms; the dialog shows after the talk has ended (the checklist expected it inside
  the talk). Leak box and the in-game box stay open for the manual pass: pad A, F held on Yes (Hail prompt live under the dialog), Release No,
  a Rift stone talk, Talk's sub-menu on this build, a non-party pawn, and the feel.
- 2026-11-08, `583ac7b`: trace replaced by one report when the root node id is seen but its choices do not qualify.
