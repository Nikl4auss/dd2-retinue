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
  `docs/findings/api-map.md` § REFramework `fs`): `fs.write` creates missing folders and writes bytes exactly
  (multi-line, UTF-8), and `fs.write(path, "")` works. `fs.glob(filter)` is recursive and returns paths relative to
  `reframework/data` with backslashes; the filter must match the whole relative path and forward slashes in it do not
  match (`Retinue[\\/]slots[\\/]2[\\/].*` works, `Retinue/spike/.*` and `spike` return nothing); no match is an empty
  table. `os.date("*t")` works. In run `saveslot_20261105_192726` `requestLoadGameData` runs nested inside
  `requestStartType` (start pre, load pre, load post, start post) for `RedoNewGame` and `RedoNewGameSkip`.
- Implemented (plan `plan.md`, slice 1): the session's `archive_pending` / `take_archive`, the pure `archive.lua`, and
  `game/archive_store.lua` called from `re.on_frame`. Unit tests only; the in-game box stays open.
