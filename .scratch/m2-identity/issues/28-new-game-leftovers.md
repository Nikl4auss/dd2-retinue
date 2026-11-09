# 28: New game leftovers: Start from Beginning, NG+ with a backup

Parent: [M2 spec](../spec.md) (§ Save slot (new playthrough, NG+))

**What to build:** settle what the two new-game paths left open by [ticket 22](22-new-game-archives-roster.md) do, and fix what
they show. All three are checks in game; only the first may need code.

**Blocked by:** [22: A new game archives the slot's roster; NG+ keeps it](22-new-game-archives-roster.md)

**Status:** resolved

- [x] "Start from Beginning" on a cleared slot (new since findings 0010, offered after the difficulty choice): which `StartType`
  it sends. If `RedoNewGame`, the roster is archived at once: decide whether that is a new playthrough or the same one.
- [x] NG+ with a member that has a valid backup: away, backup unchanged. Ticket 22's fixture read as damaged.
- [x] A new game given up inside the session (back to the title, then a load): the line
  `slot: new game given up before its first save; the roster stays`. Closing the game was tested; this path was not, because
  going back to the title by keys is unproven. Covered by `tests/slot_test.lua`.

## Comments

- Each is a test on a backup: the first two convert slot 1, the only cleared slot recorded. Fixtures CRLF, with `version`.
- Run on `bba9fee`, 2026-11-08/09, headless, by the peer session. Fixture for checks 1 and 2: `FakeT23` copied byte for byte from
  retest B's archive (CRLF, roster and backup both `version` 1, valid Lv 28 backup), status set to `present`, in `slots/1`. Each check
  was restored from its own backup (`20261108-233420-t28-1`, `20261108-234654-t28-2`, `20261108-235614-t28-3`), and all 7 saves
  and `slots/1`, `slots/2` matched by sha256.
- Check 1: "Start from Beginning" on cleared slot 1 sends `RedoNewGame` and archives at once. Log: `slot: start RedoNewGame`,
  `slot: Slot 1 (load request, global slot 3)`, `Slot 1: archived 2 files to Retinue/slots/1/archive-20261108-234336; the slot
  starts empty`, `Slot 1: roster ok (0/2)`, all within 0.12 s. The archive has the originals' sha256; the originals are 0 bytes.
  Unlike Vernworth, there is no "Use existing character data" and no creator: it goes straight to the prologue's opening
  cinematic. No new save came before the close (only the conversion's `data003slot.bin`). Open: decide whether this is a new
  playthrough (current behaviour, matches the uncleared-slot restart) or the same one (`CONTEXT.md` says NG+ over a cleared slot
  continues the playthrough).
- Check 2 passed: NG+ (Start from Vernworth) on slot 1. `slot: start RedoNewGameSkip`, `Slot 1: roster ok (1/2)`, `in the world: yes`
  4 min later, then `FakeT23: roster present, not in the save's party (backup Lv28) → away, backup kept`. `roster.json` is `away`
  (CRLF kept), the backup is byte-identical, no `archive-*`, `slots/2` unchanged. The party held only Mishu.
- Check 3 cannot be reached in the game. After `NewGame` (slot 2, `the roster waits for the new game's first save`), the pause in
  the prologue offers only Unpause and Photo Mode (also via Esc during the cinematics); in the creator, Esc, right click and P do
  nothing. System > Return to Title only exists after the first save, which follows the creator's last Yes within about 5 s
  (retest B). So the only way to give a new game up before its first save is closing the game (retest A), and the
  `given up` line's path is covered by `tests/slot_test.lua` alone. Nothing was archived and all hashes matched after the close.
- Decided by the user 2026-11-09: "Start from Beginning" on a cleared slot is the same playthrough, so the roster is kept as on
  Vernworth NG+. This needs a signal at `requestStartType(RedoNewGame)` that tells a cleared slot from an uncleared one.
  Candidates from the dump: `app.GuiManager._IsGameClearData`, `_IsRestartData`, `IsGameClearData()`,
  `isGameClearOrRestartData()`, `makeLoopSaveData`. A log-only spike was sent to the peer session (runs: slot 1 Beginning,
  slot 2 restart, slot 1 Vernworth). Fail closed: if the signal cannot be read, keep archiving (the archive is never deleted).
- Fixed in `1b8cdb4` (plan `plan-28.md`): a `RedoNewGame` waits in the session until `GuiManager._IsRestartData` is true, then
  `_IsGameClearData` decides: cleared keeps the roster, otherwise archive; unreadable or no flag within 10 s archives.
- In-game check of the fix passed 2026-11-09 (peer, headless, mod only). Slot 1, Start from Beginning, `FakeT23` fixture:
  `slot: start RedoNewGame`, `Slot 1 (load request, global slot 3)`, 0.81 s later `slot: Slot 1 restart over a cleared slot; the
  roster stays (NG+)`, `Slot 1: roster ok (1/2)`; no archive, roster and backup unchanged by hash at close, 3 min later at Fiska's
  lines before the creator (the world needs the creator and its first save, not reached). Slot 2 restart, Folken's roster:
  0.87 s to `slot: Slot 2 restart over a slot not cleared; the roster is archived`, then `archived 2 files to
  Retinue/slots/2/archive-20261109-004943`, `roster ok (0/2)`; archive hashes equal the originals, originals 0 bytes. No
  `no clear flag` or `unreadable` line. Backups `20261109-003730-t28-fix1`, `20261109-004535-t28-fix2`; both restored and verified.
- Left for the user's manual pass: Start from Beginning played through the creator into the world, to see the kept roster
  reconcile (members not in the party go away) and how it feels.
- Closed 2026-11-09.
