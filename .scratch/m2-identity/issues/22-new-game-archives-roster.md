# 22: A new game archives the slot's roster; NG+ keeps it

Parent: [M2 spec](../spec.md) (§ Save slot (new playthrough, NG+))

**What to build:** starting a new game (or a restart) over a slot moves its roster and backups to a timestamped archive in that slot
and starts empty; NG+ keeps the roster, and members not in the party become away by reconciliation.

**Blocked by:** [21: The roster reconciles with the loaded save](21-reconcile-on-load.md)

**Status:** ready-for-agent

- [x] Archive written from the update loop after the hook, never inside it; never deleted.
- [x] Archive name `archive-<yyyymmdd-hhmmss>` (tested in the `slot` module).
- [x] NG+ (`RedoNewGameSkip`): roster kept.
- [ ] Verified in game on a test slot (checklist 21, 22, opportunistic).

## Comments

- REFramework has no working `os.remove` here (verified in ticket 18: release ran the emptying fallback; the LeovvayGore
  mod says `os.rename` is missing too). So the archive is a copy of each file into `archive-<yyyymmdd-hhmmss>/` plus emptying the original
  (an empty file reads as missing).
- Facts observed in the game on the title screen, 2026-11-06 (throwaway script, no save loaded; also in
  `docs/findings/api-map.md` § REFramework `fs`): `fs.write` creates missing folders and writes the text (exact as seen through `fs.read`; on disk LF becomes CRLF, see below)
  (multi-line, UTF-8), and `fs.write(path, "")` works. `fs.glob(filter)` is recursive and returns paths relative to
  `reframework/data` with backslashes; the filter must match the whole relative path and forward slashes in it do not
  match (`Retinue[\\/]slots[\\/]2[\\/].*` works, `Retinue/spike/.*` and `spike` return nothing); no match is an empty
  table. `os.date("*t")` works. In run `saveslot_20261105_192726` `requestLoadGameData` runs nested inside
  `requestStartType` (start pre, load pre, load post, start post) for `RedoNewGame` and `RedoNewGameSkip`.
- Implemented (plan `plan.md`, slice 1): the session's `archive_pending` / `take_archive`, the pure `archive.lua`, and
  `game/archive_store.lua` called from `re.on_frame`. Unit tests only; the in-game box stays open.
- In-game test 1, NewGame path only, passed 2026-11-07 (checklist 21; RedoNewGame is test 2, still undecided, so the box stays
  open). Slot 3 empty, with a fake one-member roster and backup, both CRLF like the mod's own files. Log:
  `Slot 3: archived 2 files to Retinue/slots/3/archive-20261107-002713; the slot starts empty`, then `roster ok (0/2)`.
  The archive is byte-identical to the originals (sha256), the originals are 0 bytes, and `slots/2` and the 7 save files are
  unchanged. NewGame fires on the last Yes, after the difficulty choice, and the archive line follows within 1 s. The game was
  terminated right after, then the backup was restored.
- `fs.write` turns LF into CRLF. An earlier run with LF fixtures gave an archive that differed only in that; `fs.read` gives LF
  back (the copy's read-back check passed), so the mod's CRLF files archive unchanged.
- In-game test 2, `RedoNewGame` on slot 2, passed 2026-11-07 (checklist 21). Log: `slot: Slot 2 (load request, global slot 8)`,
  `Slot 2: archived 2 files to Retinue/slots/2/archive-20261107-005752; the slot starts empty`, `roster ok (0/2)`. No line names
  `RedoNewGame`: `note` logs only a change, and the unit is nil before and after that start, but the load of global 8 and the
  archive show it. The archive has the sha256 of the pre-test originals, the originals are 0 bytes, and `roster.json` was still
  0 bytes 2 min 20 s later, in the prologue. Saves 5, 6, 9 went to `data008slot.bin` on Convert Saved Data, as in findings 0010.
  The backup was restored and all 7 saves and `slots/2` matched by hash.
- The restart is not reached from New Game (corrects findings 0010): title, Change Save Slot, hold Shift on the slot (prompt
  "Restart game with data carried over"), Yes, I Understand, Convert Saved Data, OK, back to the title, START GAME, "Restart game
  with current level and equipment", Yes, difficulty, Yes. It works on the current slot and on a slot that is not current.
- New Game over the occupied current slot is a different path, seen in the first attempt at test 2: the log has
  `slot: Slot 2 (new game)`, so a plain `NewGame`, and the saves stay on disk (5, 6, 9 unchanged after 3 min 40 s in the prologue;
  presumably the first save replaces them, not observed). The mod archives at once.
- Open bug, not fixed: a New Game given up before its first save leaves the old save but an empty roster. Slot 2 in that state,
  closed in the prologue and loaded with Load from Last Saved Data: `Slot 2: roster ok (0/2)`, Folken Lv 28 in the party, the
  mod has no member for him, the roster stays empty in `archive-*`, and nothing brings it back. The saves did not change.
  Deciding the fix is a design question: archive at the first save of the new game instead, or restore the archive when
  the old save is loaded. That state is in backup `20261107-005116-pre-restore`.
- In-game test 3, NG+ on slot 1, passed 2026-11-07 (checklist 22). Log: `slot: Slot 1 (load request, global slot 3)`, no archive
  line and no `archive-*` folder, then after `in the world: yes`: `FakeT33: roster present, not in the save's party (no backup) →
  away, backup kept`. `roster.json` keeps the member, now `away`; the backup file is unchanged; the party held only Mishu.
  `(no backup)` is the fixture's fault: it had no `version`, so it read as damaged. A member with a valid backup was not
  exercised on this path. Saves 0, 1, 4 went to `data003slot.bin`. The restore gave back all 7 saves and `slots/2` by hash.
- After the difficulty choice a cleared slot now asks "Start from Vernworth" or "Start from Beginning" (findings 0010: no
  choice). Vernworth is `RedoNewGameSkip`, then "Use existing character data" and the creator for the Arisen and the pawn: the
  world comes after those, nearly 9 min after the load request here. "Start from Beginning" was not tried; it may be a
  `RedoNewGame` over a cleared slot, which would archive.
- `tools/saves.sh` found the save folder by `data000.bin`, which the conversion of slot 1 deletes. It then chose an old Steam
  prefix and `restore` refused, correctly. It now looks for `data00-1.bin`, the system save.
- Fix of the open bug, decided by the user 2026-11-07: a `NewGame` archives on its first save. `RedoNewGame` stays at once (its old
  saves are already converted, so the bug does not apply). Signal: `SaveDataManager.requestSaveSlot(global, ...)`, seen for every
  save in the runs of 2026-11-05, with `requestSaveSlot(11)` as the first call after `NewGame` on slot 3. Until that save no
  roster is active; a later start or load, or closing the game, gives the new game up and changes nothing. Needs the in-game
  check again: give up (slot 2, close in the prologue, load: roster as before), and a real first save. In the 2026-11-05 runs that save came about 80 s after `NewGame`, not after the prologue, so this may be short; on slot 2 it had not come after 3 min 40 s. A conversion's copy (type 3) does not count as the first save.
- Still untried: "Start from Beginning" on a cleared slot, and NG+ with a valid backup.
- Retest A, giving up a `NewGame`, passed 2026-11-07 on `4636245` (slot 2, Folken). New Game on the current slot, "Erase saved data and start a new game", Normal, Yes. Log at 11:42:42: `slot: Slot 2 (new game)`, `slot: start NewGame`, `slot: the roster waits for the new game's first save`; no `archived` line. 23 s after it, on the server notice that opens the new game, there was no `archive-*` and `slots/2` and all 7 saves matched by hash. Closed with SIGTERM 33 s after `NewGame`; no first save came in that time, so `first save of the new game` did not appear. Relaunched and used Load from Last Saved Data: `slot: Slot 2 (load request, global slot 9)`, `Slot 2: roster ok (1/2)`, `in the world: yes` at 11:47:11. Folken Lv 28 in the party, status `present`, no away or returning correction. Stayed 21 s. After closing: `roster.json` identical, all 7 saves identical, still no `archive-*`. The backup changed only by a new `hire_time`, written by the normal poll at 11:47:24 (the file had none). The `given up` line did not appear, as expected: the game was closed before the load. The test used the slot's old saves and the restore gave back `slots/2` by hash.
- Retest A2 (give up without closing, to see the `given up` line) was not run: the path back to the title from the new game is one I have not proven by keys.
- Retest B, a real first save, passed 2026-11-07 on `4636245` (slot 3, empty, played by the user; CRLF fixture `FakeT23`, status `away`, with a valid backup that has `version`). `slot: start NewGame` and `the roster waits for the new game's first save` at 12:00:14. Until the save the fixture stayed unchanged with no `archive-*`. `first save of the new game, global slot 11` at 12:01:31, 76 s later and about 5 s after the character creator's last Yes; it depended on how fast the cutscenes were skipped, since the save follows the creator. Then `Slot 3: archived 2 files to Retinue/slots/3/archive-20261107-120131; the slot starts empty` and `Slot 3: roster ok (0/2)`. Archive hashes equal the originals, originals 0 bytes, `slots/2` unchanged. That first save wrote `data010slot.bin`, `data011slot.bin` and `data014slot.bin`; saves of the other slots did not change, only the system save. This also explains the slot 2 run with no save by 3 min 40 s: it stayed before the creator. The restore gave back all 7 saves and `slots/2` by hash.
- Not run: the repeat over slot 2 (plain `NewGame`, saves on disk), so it is still unknown whether that first save replaces 5, 6, 9.
