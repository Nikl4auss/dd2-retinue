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
