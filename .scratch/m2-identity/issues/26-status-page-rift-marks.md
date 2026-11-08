# 26: Retinue marks on the Status page and in Previous Hires

Parent: [M2 spec](../spec.md) (§ Status (native))

**What to build:** the Status page header reads "<name> · Retinue" for a present member, and the Rift's Previous Hires list shows
"★ <name> · Lv N" (backup's level) for every member.

**Blocked by:** [19: Dismiss and Return restore an adopted pawn's progress](19-dismiss-return-restore.md)

**Status:** done

- [x] Status page: only members, never the Arisen or the main pawn.
- [x] Previous Hires matched by `ResInfo.OfflineId`; ordinary entries untouched.
- [x] Fails closed when a widget field is missing (no mark, logged once).
- [x] Verified in game (checklist 4, 11).

## Comments

- 2026-11-08, slice 1 (the pure marks, the glue in `game/marks.lua`, wiring and tests; `34f604e`): in-game checks (4, 11) wait for slice 2.
- 2026-11-08, `34f604e`, run 1 (headless, by the peer session; Slot 2, Diamonds present in the party, Anne reconciled to away):
  Status page passes visually ("Diamonds · Retinue"; Klauss and Shaira plain; no stacking over tab switches), but setupPawn's post
  reported "PawnInfo.TxtName / CharaTab.TxtName unreadable" (the refs are nil there, as in findings 0009's run; the header is written
  by the PawnInfo2Ref.setup and updateName posts). Previous Hires: no marks, one report "rift marks: TxtPawnName unreadable":
  `get_elements()` fails on that `via.gui.Text[]`. Fixed in `1abfddc` (get_Length / GetValue fallback; nil refs skipped silently).
- 2026-11-08, `1abfddc`, run 2 (headless, same setup): check 4 passes (headers "Klauss", "Shaira", "Diamonds · Retinue" over two
  cycles, no stacking) and check 11 passes ("★ Diamonds · Lv 24", the backup's level, beside the list's own "Lv. 22" column;
  Folken (released) and the other five entries plain; no stacking over two scroll round-trips). No report lines. Favorites is empty
  in this save. Backups `20261108-122004-m2-t26-pre` (restored after each run), `20261108-123258-m2-t26-run2-pre`.
  Left for the user's manual pass: a non-member hired pawn on the Status page, Release then Previous Hires (stale mark stripped),
  an away member's entry after a real dismiss, and how the marks look.
- 2026-11-08, `1abfddc`, manual pass by the user: all pass, the optional step included. Status page: Diamonds marked, Klauss and
  Shaira plain, Folken (hired, not a member) plain. Previous Hires: "★ Diamonds · Lv 24"; after Release, Diamonds plain on both
  pages (stale mark stripped); Folken adopted then dismissed at the Rift shows "★ Folken · Lv N". Saves restored to
  `20261108-122004-m2-t26-pre`. Ticket closed.
