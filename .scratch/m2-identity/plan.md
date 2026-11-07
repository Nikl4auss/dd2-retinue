# M2 plan: ticket 22 (A new game archives the slot's roster; NG+ keeps it)

Source: [issues/22-new-game-archives-roster.md](issues/22-new-game-archives-roster.md), [spec.md](spec.md) § Save slot. Base commit: `0bbd677`.
(Plans of earlier tickets are in git history.)

One slice.

- [x] Slice 1: pending flag in the session, pure `archive.lua`, glue, wiring, tests, docs. Tier: **Sonnet** (`implementer`).

Cross-review: skipped (Sol and Astra unavailable on this account); Opus `reviewer` only.

## Verified before planning

Title-only run in the game, 2026-11-06 (throwaway autorun script, removed; no save loaded):

- `fs.write` creates missing folders and writes bytes exactly (multi-line, UTF-8). `fs.write(path, "")` works.
- `fs.glob(filter)` is recursive and returns paths relative to `reframework/data`, **with backslashes**. The filter must
  match the **whole** relative path, and forward slashes do not match: `Retinue[\\/]slots[\\/]2[\\/].*` works,
  `Retinue/spike/.*` and `spike` return nothing. No match returns an empty table, not nil.
- `os.date("*t")` works.
- Run file `saveslot_20261105_192726`: `requestLoadGameData` runs nested inside `requestStartType` (start pre, load pre,
  load post, start post), for `RedoNewGame` and `RedoNewGameSkip`.

## Slice 1: Archive on a new playthrough

**Goal**: starting a new game or a restart over a slot moves its roster and backups to `slots/<n>/archive-<yyyymmdd-hhmmss>/`
and the slot starts empty. NG+ keeps the roster.

**Context**: read `slot.lua`, `game/slot_hooks.lua`, `game/jsonfile.lua`, `game/roster_store.lua`, `Retinue.lua`,
`tests/slot_test.lua`. Findings 0010 § New game and NG+.

**Design**

`slot.lua`, Session:

- New fields: `archive_pending = false`, `archives = 0`.
- `on_start_request`: after `self.unit` and `self.source` are assigned, as the **last** statement:
  `self.archive_pending = kind == M.NEW_PLAYTHROUGH and (name ~= "NewGame" or unit ~= nil)`.
  The order matters: `re.on_frame` may run on the render thread, and seeing the flag with the previous unit would archive
  the wrong slot. Comment it. A `NewGame` without a unit stays false because no load request follows it. Every other start
  clears the flag, so a restart whose load never came cannot archive a slot loaded later.
- `Session:take_archive() -> unit | nil`: when pending and `unit ~= nil`: clears pending, `archives += 1`, returns the
  unit. Otherwise nil, and the flag stays (the load request sets the unit).

New pure `Retinue/archive.lua`:

```lua
-- archive.run(unit, t, files) -> result
--   files.list(filter) -> array of paths (relative to reframework/data, either separator)
--   files.read(path)   -> text ("" = missing or empty), or nil when it cannot be read
--   files.write(path, text) -> anything; success is judged only by reading back
-- result: { status = "none" | "done" | "failed", dir = string|nil, copied = n, left = n, why = string|nil }
```

`archive.filter(unit)` -> the `fs.glob` regex for everything under `slot.dir(unit)`: built from `slot.ROOT` with each `/`
replaced by `[\\/]`, ending in `[\\/].*`, with the Lua string holding the characters `[\\/]`.

Steps of `run`:

1. `read(roster.path(unit))`: nil -> failed ("roster unreadable"); `""` -> `none`, nothing else touched. Any other text,
   including a locked or newer-version file, is archived: the copy keeps it as it was.
2. `list(filter)`, each path with `\` turned to `/`. Keep paths under `slot.dir(unit) .. "/"`, drop those whose first
   component after that starts with `archive-`. Always include the roster path, deduplicated. `list` throwing or
   returning a non-table counts as an empty list, so the roster alone is still archived.
3. Read each file. `""` is skipped (an emptied backup); nil -> failed.
4. Copy each to `slot.archive_dir(unit, t) .. "/" .. <path relative to slot.dir(unit)>`; `backups/` stays a subfolder.
   Read it back; a difference -> failed, nothing emptied (`copied` tells how far it went).
5. Empty the roster first with `write(path, "")`; if it does not read back `""` -> failed, stop: the old roster and all
   its backups are still whole. Then empty the others; one that stays non-empty counts in `left` and does not fail the
   run, because an orphan backup is ignored and a re-adopt overwrites it.

`dir` is set whenever a copy was attempted. Files are processed in sorted order, for stable tests.

`archive.text(result, unit)` -> log line, or nil for `none`:

- done: `Slot 2: archived 2 files to Retinue/slots/2/archive-20261106-120000; the slot starts empty`, plus
  `(1 not emptied)` when `left > 0`.
- failed: `Slot 2: could not archive the roster (<why>); it stays in place`.

New `game/archive_store.lua`, `M.run(session, report)`:

- `local unit = session:take_archive()`; nil -> return.
- Runs `archive.run(unit, os.date("*t"), files)`, with `files` wrapping `fs.glob`, `fs.read`, `fs.write` under pcall
  (`read` -> nil on a throw or a non-string or without `fs`; `write` swallows errors; `list` -> `{}` without `fs.glob`).
- `log.error("[Retinue] " .. text)` when there is a text, and `report("archive", why)` on failed.

`jsonfile.lua` is not changed: the copy is raw text, never decoded.

`Retinue.lua` `re.on_frame`, between `tracker.update` and `retinue.update`:

```lua
local ok_a, err_a = pcall(archive_store.run, tracker.session, report)
if not ok_a then report("archive", err_a) end
```

and the `retinue.update` requests argument becomes `tracker.session.starts + tracker.session.loads + tracker.session.archives`.
That sum matters: a hook can land between `take_archive` and `retinue.update` on another thread, so a roster read just
before the archive would otherwise stay active and be written back over the emptied file. Comment it. Update the file's
header (behaviour paragraph and the layout list).

A failed archive leaves the old roster active; its members become away by reconciliation and can be released, as in the
new game without the mod. No retry: the flag is taken once. No native notice (ticket 23).

**Acceptance criteria**

- [ ] `slot_test.lua`: `NewGame` with a unit, `RedoNewGame` then load: `take_archive` returns the unit once, then nil.
- [ ] `RedoNewGame` before its load: nil, flag kept. `NewGame` without a unit: flag false, and a later load gives nil.
- [ ] `RedoNewGameSkip`, `Latest`, `Base`, a nil name: no archive. `RedoNewGame` followed by `Latest` + load: no archive.
- [ ] `archives` counts takes.
- [ ] New `archive_test.lua` with a fake in-memory `files`: done (roster + backup, backups subfolder, originals `""`,
  contents byte-exact); `none` on an empty roster leaves every file and writes nothing; backslash listing; `archive-*`
  folders untouched; empty files skipped; other slots untouched; unparseable roster archived; list failure archives the
  roster alone; copy failure empties nothing; roster that cannot be emptied stops with the backups whole; a backup that
  cannot be emptied gives done with `left = 1`; read failure; `text` for each result; `filter(1)` is exactly
  `Retinue[\\/]slots[\\/]2[\\/].*` (one literal backslash pair in the regex, written so the test is unambiguous).
- [ ] `tests/run.sh` passes.
- [ ] `CHANGELOG.md` entry under Added. `docs/findings/api-map.md` gets a short "REFramework `fs`" section with the facts
  above, status verified-game. Ticket 22 gets a comment with the same facts; its in-game box stays open.

**Verify**: `bash tests/run.sh`.

**Out of scope**: native notices, new menu text, the NG+ reconciliation itself (general rule, already covered by
`reconcile_test.lua`), reading or listing archives, deleting archives, `tools/`.
