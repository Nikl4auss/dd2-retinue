# M2 plan: ticket 17 (Adopt and release from the mod menu; only adopted pawns progress)

Source: [issues/17-adopt-release-mod-menu.md](issues/17-adopt-release-mod-menu.md), [spec.md](spec.md) § Identity,
§ Roster file, § Progression (M1 narrowed), § Mod menu. Base commit: `afc3075`. (Ticket 16's plan is in git history.)

Two slices, sequential (slice 2 uses slice 1's modules).

- [x] Slice 1: Pure `roster` module and the narrowed `targets` predicate, with tests. Tier: **Sonnet** (`implementer`).
- [x] Slice 2: Game glue: party views, per-slot roster store, menu with Adopt/Release, wiring. Tier: **Sonnet** (`implementer`).

Cross-review: skipped (Sol and Astra unavailable on this account); Opus `reviewer` only.

Facts the design rests on:

- `PawnOwnerContext` is read from `chara:call("get_Context")` → `Contexts` dictionary keyed by
  `sdk.typeof("app.PawnOwnerContext")` → `get_CurrentContext()` (`tools/experiments/Retinue_Exp_Restore.lua`
  `holder_context` / `owner_of`). `_Name` is a string (`"CAPCOM"` for Rift pawns, the creator's name otherwise);
  `_OfflineID` is a `System.Guid`, read as text with `:call("ToString")` (lowercase `8-4-4-4-12`); the main pawn's
  is the zero GUID (probe data 2026-11-03).
- `_PartyPawnList` index = party slot (0 main pawn, 1–2 hired pawns).
- `json.dump_file` creates missing directories (the restore experiment wrote `Retinue/experiments/restore_backups/`)
  and returns true even when the file cannot be opened, so writes are read back (as `config_store` does).
- REFramework's json writes an empty `{}`/`[]` as `null`, and a `null` decodes to nil: an empty roster is written as
  `"members": null` and must read back as an empty roster, so **missing `members` = empty**, not a structural error.
- `fs.read` returns `""` for a missing and an empty file alike (empty file = missing). Without `fs.read`,
  `json.load_file` cannot tell a missing roster from a damaged one: then the roster is **locked** (fail closed: never
  overwrite a file we could not read). With `fs.read` (the normal case) this never happens.

---

## Slice 1: Pure roster module and the narrowed target predicate

**Goal**: the decisions behind the roster exist as a pure, tested module: reading a `roster.json` (validation, locked,
read-only, soft corrections, unknown keys kept), the data to write back, adopt / release / cache refresh with their
errors, the adoptable rule, ambiguity, and menu texts. `targets.build` now returns only present, non-ambiguous
roster members found in the party. No game code changes in this slice (the glue still calls the old `targets.build`
signature until slice 2, so slice 2 must land with it; that is fine: slices are committed in order, and this slice
is verified by tests only).

**Context** (read first):
- `.scratch/m2-identity/spec.md` § Identity, § Roster file, § Progression (M1 narrowed), § Mod menu.
- `src/autorun/Retinue/config.lua` + `tests/config_test.lua`: the resolve/merge pattern and test style (plain
  `assert`s, `do ... end` blocks, run by `tests/run.sh` under Lua 5.4, `LUA_PATH` = `src/autorun/?.lua`).
- `src/autorun/Retinue/slot.lua` (`dir(unit)`, `to_int`), `src/autorun/Retinue/targets.lua`, `tests/targets_test.lua`,
  `src/autorun/Retinue/ids.lua`, `src/autorun/Retinue/status.lua` + `tests/status_test.lua`.
- Terms (CONTEXT.md): **member** = entry of the active roster; adopted pawn present / away / returning; release.

**Design**:

1. New `src/autorun/Retinue/roster.lua` (pure: no REFramework globals). Requires `Retinue.slot` and `Retinue.ids`.
   ```lua
   local M = {}
   M.CAP = 2                -- the only place the cap appears
   M.VERSION = 1
   M.PRESENT, M.AWAY, M.RETURNING = "present", "away", "returning"
   M.OK, M.LOCKED, M.READ_ONLY = "ok", "locked", "read_only"   -- roster.mode
   M.UNKNOWN_NAME = "(unknown)"
   M.OWNER = "CAPCOM"

   function M.path(unit) return slot.dir(unit) .. "/roster.json" end

   -- Canonical Offline ID: v is a string of the form 8-4-4-4-12 hex digits (either case), not all zeros ->
   -- lowercase copy; anything else (nil, non-string, wrong shape, zero GUID) -> nil.
   function M.canonical_id(v) end

   -- CharacterID cache value: an integer view (slot.to_int) in 0..0xFFFFFFFF -> that integer; else nil.
   function M.valid_character_id(v) end

   -- Party view (built by the glue, one per party pawn; also the shape the tests use):
   --   { slot = 0|1|2, character_id = integer|nil, owner = string|nil, offline_id = string|nil (raw or canonical),
   --     name = string|nil }
   -- adoptable(view) -> canonical offline id when view.slot is 1 or 2, view.owner == M.OWNER and
   -- canonical_id(view.offline_id) is non-nil; else nil.
   function M.adoptable(view) end
   ```

   **Roster** (the value every function takes; members are plain tables so unknown keys survive):
   ```lua
   -- roster = {
   --   mode = M.OK | M.LOCKED | M.READ_ONLY,
   --   reason = string|nil,     -- LOCKED: why (e.g. "not valid JSON"); READ_ONLY: "version 2"; OK: nil
   --   members = { member, ... },  -- adoption order; always {} when LOCKED
   --   base = table|nil,        -- decoded top level (unknown keys kept on rewrite); nil when missing or LOCKED
   --   warnings = { string, ... },
   -- }
   -- member = { offline_id = <canonical>, name = string, status = PRESENT|AWAY|RETURNING,
   --            character_id = integer|nil, <unknown keys as read> }
   ```

   ```lua
   -- status: "missing" | "unparseable" | "unreadable" | "ok"; data: the decoded value when "ok".
   -- ("unreadable": the glue could not tell missing from damaged; see Facts.)
   function M.resolve(status, data) end
   ```
   Rules, in this order:
   - `"missing"` → `{ mode = OK, members = {}, warnings = {} }` (no base).
   - `"unparseable"` → LOCKED, reason `"not valid JSON"`. `"unreadable"` → LOCKED, reason
     `"cannot be read safely (fs.read unavailable)"`. Any other status string → LOCKED, reason `"cannot be read"`.
   - `"ok"`: `data` not a table, or a table with any array part (`#data > 0`) → LOCKED `"top level is not an object"`.
   - `version`: integer view (`slot.to_int`). Nil/non-integer/`< 1` → warning
     `"version is missing or invalid; read as 1"`, treated as 1. `> M.VERSION` → **read-only path** (below).
   - `members`: nil → empty (the `null` caveat). A non-table, or a table that is not a sequence (any key other than
     the integers 1..n) → LOCKED `"members is not an array"`.
   - Each entry `i` (1-based in messages):
     - not a table → LOCKED `"member <i> is not an object"`;
     - `canonical_id(entry.offline_id)` nil → LOCKED `"member <i> has no valid offline_id"`;
     - its canonical id already seen → LOCKED `"duplicate offline_id <id>"`;
     - after all entries, count > `M.CAP` → LOCKED `"more than <CAP> members"`.
     The first structural error found wins (entries checked in order, the cap last).
   - Soft corrections per member (each with one warning, `"member <i>: ..."`): `name` not a non-empty string →
     `M.UNKNOWN_NAME` (`"name is missing or invalid; using (unknown)"`); `character_id` present (non-nil) but
     `valid_character_id` nil → removed (`"character_id is invalid; ignored"`); absent `character_id` → no warning;
     `status` not one of the three → `AWAY` (`"status is missing or invalid; using away"`). `offline_id` is stored
     canonical.
   - The member table is a **shallow copy** of the entry with the corrected known fields; the roster keeps
     `base = data`.
   - **Read-only path** (`version > M.VERSION`): mode READ_ONLY, reason `"version <n>"`, one warning
     `"written by a newer Retinue (version <n>); read-only"`. `members` not a sequence → no members (no lock).
     Members are taken as v1 leniently: an entry that would be a structural error (not a table, bad or duplicate
     `offline_id`) is **skipped** with a warning `"member <i> skipped: <why>"`; soft corrections apply; only the first
     `M.CAP` valid members are kept (warning `"members past <CAP> ignored"` if more). Never LOCKED for member errors.
   - Warnings are plain strings without a prefix (the glue adds `[Retinue] Slot N roster.json: `).

   ```lua
   function M.writable(r) return r ~= nil and r.mode == M.OK end

   -- A NEW table to write (only meaningful when writable): shallow copy of r.base (unknown top-level keys kept;
   -- nil base -> {}), version = M.VERSION, members = array of shallow copies of r.members (a nil character_id is
   -- simply absent). Same json null/{} caveat as config.merge (comment it).
   function M.serialize(r) end

   -- Read-back check for the glue: back is a table whose members (nil = empty) list the same canonical
   -- offline_ids in the same order as r.members.
   function M.matches(r, back) end
   ```

   **Party matching and ambiguity**:
   ```lua
   -- match(r, views) -> found, ambiguous
   --   found:     { [offline_id] = view }  members of r whose id appears in exactly one view
   --   ambiguous: { [offline_id] = true }  members of r whose id appears in two or more views
   -- Views are compared by canonical_id(view.offline_id); views without one are ignored. Any slot counts (a
   -- duplicate anywhere in the party is ambiguous). LOCKED or nil r -> {}, {}.
   function M.match(r, views) end

   function M.find(r, offline_id) end   -- member with this canonical id (input canonicalised) or nil
   ```

   **Operations** (mutate `r` in place; return a value or `nil, err`; never touch files):
   ```lua
   -- adopt(r, view) -> member | nil, err.  Checks in this order:
   --   r.mode LOCKED -> "locked"; READ_ONLY -> "read_only"; adoptable(view) nil -> "no_offline_id";
   --   already a member (any status) -> "already_adopted"; #r.members >= M.CAP -> "full".
   -- Appends { offline_id, name = view.name if a non-empty string else UNKNOWN_NAME, status = PRESENT,
   --           character_id = valid_character_id(view.character_id) }.
   function M.adopt(r, view) end

   -- release(r, offline_id) -> removed member | nil, err.  LOCKED -> "locked"; READ_ONLY -> "read_only";
   -- not a member -> "not_adopted". Removes the whole member table (its unknown keys go with it).
   function M.release(r, offline_id) end

   -- refresh_cache(r, views) -> changed (boolean). For each PRESENT member in match(r, views).found (so never an
   -- ambiguous one): set character_id = valid_character_id(view.character_id) when non-nil and different, and
   -- name = view.name when a non-empty string and different. Away and returning members are left alone (an away
   -- member keeps its last CharacterID). LOCKED -> false, no change. Works in memory for READ_ONLY too (the glue
   -- never writes it).
   function M.refresh_cache(r, views) end
   ```

   **Texts** (menu and errors; plain English):
   ```lua
   M.ERRORS = {
     full = "the retinue is full (" .. M.CAP .. " members)",
     already_adopted = "already in the retinue",
     locked = "the roster is locked (see the menu)",
     read_only = "the roster is read-only (written by a newer Retinue)",
     no_offline_id = "not a Rift pawn with an Offline ID",
     not_adopted = "not in the retinue",
     no_slot = "the save slot is unknown",          -- produced by the glue
     not_in_party = "no longer in the party",       -- produced by the glue
     write_failed = "could not save roster.json (see log)", -- not an operation error; used by the menu
   }
   function M.error_text(err) end -- M.ERRORS[err] or tostring(err)

   -- state_text(r) -> nil r: "no roster (slot unknown)"; OK: "roster ok (<n>/<CAP>)";
   -- LOCKED: "roster locked: <reason> (fix roster.json by hand, then Reset scripts)";
   -- READ_ONLY: "roster read-only: written by a newer Retinue (<reason>)".
   function M.state_text(r) end

   -- member_text(m, info) -> "<name>: <status>[, Lv <level>][, <note>]"
   --   info = { level = number|nil, in_party = boolean, ambiguous = boolean }
   --   note: ambiguous -> "ambiguous: two party pawns share its Offline ID, excluded";
   --         status PRESENT and not in_party and not ambiguous -> "not in party".
   --   level printed as an integer when integral (like status.lua's num).
   function M.member_text(m, info) end
   ```

2. `src/autorun/Retinue/targets.lua` — replace the predicate:
   ```lua
   -- build(views, r, is_hired) -> { [character_id] = true }
   -- A target is a party view whose canonical offline id is a PRESENT member in roster.match(r, views).found
   -- (so not ambiguous), whose character_id is an integer and not ids.MAIN_PAWN, and for which is_hired(character_id)
   -- == true (is_hired only called for those). r nil (slot unknown) or LOCKED -> {}. READ_ONLY -> its present
   -- members. Away and returning members are never targets.
   function M.build(views, r, is_hired) end
   ```
   Remove `M.is_target` and the old M1 comments about it; update the header comment.

3. `src/autorun/Retinue/status.lua`: `format({})` returns `"No adopted pawns in party"` (was "No hired pawns in
   party"); update `tests/status_test.lua` to match. Nothing else in status changes.

4. Tests:
   - New `tests/roster_test.lua` covering at least: `canonical_id` (lowercase/uppercase accepted → lowercase; zero
     GUID, wrong length, non-hex, nil, number → nil); `valid_character_id` (0, 0xFFFFFFFF, 1601809365.0 ok; -1,
     2^32, 1.5, "1" → nil); `adoptable` (slot 0 / 3 / nil → nil; owner not CAPCOM → nil; zero GUID → nil; slot 1 and
     2 ok); `resolve`: missing → empty OK; unparseable → LOCKED; unreadable → LOCKED; non-table / array top level →
     LOCKED; members nil → empty OK; members a string / a map → LOCKED; member not a table, no / bad offline_id,
     duplicate (including case-only difference), 3 members → LOCKED with the exact reasons; soft corrections (bad
     name, bad character_id, bad status, each with a warning; absent character_id no warning); version missing →
     warning, OK; version 2 → READ_ONLY with valid members kept, bad members skipped, members past the cap ignored,
     non-array members → no members; unknown keys kept top level and per member through `serialize`; `serialize`
     sets version 1, omits a nil character_id, does not alias `r.base` or member tables; `matches` true/false
     (order, count, nil members vs empty roster); `match` (found, ambiguous, LOCKED → empty, views without ids
     ignored); `adopt` each error in the listed order of precedence (e.g. LOCKED wins over no_offline_id; already
     adopted wins over full), success appends a PRESENT member with canonical id, name fallback; `release` errors and
     success (unknown keys gone, order of remaining members kept); `refresh_cache` (present member's id/name updated
     → true; same values → false; away member untouched; ambiguous untouched; LOCKED → false); `M.CAP == 2` used by
     the "full" and "more than" cases (tests build their counts from `roster.CAP`); `error_text`, `state_text`,
     `member_text` outputs.
   - Rewrite `tests/targets_test.lua` for the new signature: nil roster → {}; LOCKED → {}; present member in party →
     its character_id; away / returning member in party → not a target; non-member hired pawn → not a target;
     ambiguous → not a target; main pawn excluded even if (artificially) matched, and `is_hired` not called for it;
     `is_hired` false / 1 / nil excludes; READ_ONLY → present members are targets.

**Acceptance criteria**:
- [ ] `tests/run.sh` passes, including the new `tests/roster_test.lua` and the rewritten `tests/targets_test.lua`;
  no other test removed or weakened (status_test only changes the one string).
- [ ] `roster.lua` and `targets.lua` use no REFramework globals (`sdk`, `json`, `fs`, `log`, `re`, `imgui`).
- [ ] The cap `2` appears only as `M.CAP` in `src/` (grep `roster.lua` for other literal 2s used as the cap).
- [ ] Syntax check passes on every changed Lua file.

**Verify**: `tests/run.sh`; `for f in src/autorun/Retinue/*.lua tests/*.lua; do luac5.4 -p "$f" || lua5.4 -e "assert(loadfile('$f'))"; done`.

**Out of scope**: any `game/` file or `Retinue.lua` (slice 2), `mark_away` / `mark_returning` / `mark_present`
(later tickets), backups, reconciliation, labels.lua, docs.

---

## Slice 2: Game glue: roster per slot, menu Adopt/Release, narrowed targets wired in

**Goal**: in game, the *Retinue* menu shows the slot and the roster state, one line per member, an **Adopt** button
per adoptable party pawn and a **Release** button per member, each with an inline Yes/No confirm; errors show with
their reason. The roster is read from `reframework/data/Retinue/slots/<n>/roster.json` when a unit becomes active,
written on every change (never while locked or read-only, nothing when the slot is unknown). Only present,
non-ambiguous members progress; ordinary hired pawns are vanilla again.

**Context** (read first):
- Slice 1's `src/autorun/Retinue/roster.lua` and `targets.lua` (the decisions; do not re-implement them in glue).
- `src/autorun/Retinue.lua`, `src/autorun/Retinue/game/{party,config_store,slot_hooks,progression_hooks}.lua`,
  `src/autorun/Retinue/{slot,status,errlog,hooks}.lua`.
- This plan's "Facts the design rests on".
- `tools/experiments/Retinue_Exp_Restore.lua` `holder_context`, `owner_of`, `str`: how the owner context and the
  Offline ID are read.
- Conventions: every game read under pcall; log with `log.error` and the `[Retinue] ` prefix (another mod may raise
  the log level); `report(key, err)` (errlog) for unexpected errors; REFramework callbacks wired only in `Retinue.lua`.

**Design**:

1. New `src/autorun/Retinue/game/jsonfile.lua` — the file I/O pattern from `config_store`, made reusable:
   ```lua
   local M = {}
   -- read(path) -> status, data with status "missing" | "unparseable" | "ok" (as config_store's read_config today),
   -- plus a second mode: read(path, { strict = true }) returns "unreadable" instead of guessing when fs.read is
   -- unavailable (json.load_file cannot tell missing from damaged).
   function M.read(path, opts) end
   -- write(path, data, check) -> true | false, err. pcall(json.dump_file); res == false -> "dump_file returned
   -- false"; then, when fs.read exists, read back, decode, and require check(back) (else "file unchanged after
   -- write (read-only or locked?)"). Without fs.read: true after a successful dump.
   function M.write(path, data, check) end
   return M
   ```
   `config_store` uses it: `read_config()` → `jsonfile.read(config.PATH)` (non-strict: same results as today), and
   `store:save` → `jsonfile.write(config.PATH, out, function(back) return back.progression == value end)`, keeping
   the existing error strings and `report("config write", err)`. Config behaviour must be identical.

2. `game/party.lua` — party **views** instead of building targets:
   - Each frame `refresh()` reads `_PartyPawnList` as today (party_loaded, main pawn flag, per index `i` the
     `app.Character` and CharacterID).
   - It builds `views` = array (party order) of `{ slot = i, character_id, owner, offline_id, name, chara }`
     (`owner` = `_Name` as a Lua string or nil, `offline_id` = `roster.canonical_id(<Guid>:call("ToString"))` or nil,
     `name` = `GUIBase.getName(chara)` as string or nil; each read under its own pcall).
   - **Cache**: owner, offline_id and name are re-read only when the party's CharacterID list (in order) differs from
     the last frame's, or when the last read was incomplete (the owner context or name could not be read for some
     pawn). A CharacterID can be reused by another pawn only across a dismiss, which changes the list, so the cache
     key is safe. `character_id` and `chara` are fresh every frame.
   - `party.views()` → the array (empty when no party); `party.changed()` → true on the frame the cached part was
     re-read (consumed by the roster store for the cache refresh); `party.has_main_pawn()` as today;
     `party.rows(target_set)` → nil when no party, else `read_row` for each view whose `character_id` is in
     `target_set` (status.format input, unchanged semantics: the status line lists the current targets);
     `party.level(view)` → the level read live (pcall, nil on failure) for the menu; `party.failed` as today.
   - `party.new(report)` — it no longer takes `state` or `is_hired` and no longer writes `state.targets`.

3. New `src/autorun/Retinue/game/roster_store.lua`:
   ```lua
   local M = {}
   -- Returns a store:
   --   unit          integer|nil   the unit whose roster is active (nil = unknown slot: no roster)
   --   roster        roster|nil    roster.resolve result for unit; nil when unit is nil
   --   ambiguous     { [offline_id] = true }  from the last update
   --   found         { [offline_id] = view }  from the last update
   --   save_failed   boolean       last write failed (cleared by the next successful one)
   --   update(unit, party)          -- every frame, after party.refresh and the slot tracker
   --   adopt(view) -> true | nil, err      -- err: roster's errors, plus "no_slot"
   --   release(offline_id) -> true | nil, err
   function M.new(report) end
   return M
   ```
   - `update(unit, party)`: if `unit ~= store.unit`: switch (log `[Retinue] <slot label>: roster <state_text>` and
     each warning as `[Retinue] <slot label> roster.json: <warning>`; for unit nil log nothing new — the slot line
     already says unknown), `store.roster = unit and roster.resolve(jsonfile.read(roster.path(unit),
     { strict = true })) or nil`, reset `ambiguous`, `found`, the ambiguity-warned set and `save_failed`, and force a
     cache refresh this frame. Then if a roster is active: `found, ambiguous = roster.match(r, party.views())`; log
     one warning per member when it **becomes** ambiguous (`[Retinue] <name>: two party pawns share its Offline ID;
     excluded`), forgotten when it stops being ambiguous; if `party.changed()` or the forced refresh, call
     `roster.refresh_cache(r, views)` and, when it returns true, `save()`.
   - `save()` (local): only when `roster.writable(r)`; `jsonfile.write(roster.path(unit), roster.serialize(r),
     function(back) return roster.matches(r, back) end)`; on failure `save_failed = true` and
     `report("roster write", err)`; on success `save_failed = false`.
   - `adopt(view)`: unit nil → `nil, "no_slot"`; else `roster.adopt(r, view)`; on success `save()` and log
     `[Retinue] <slot label>: adopted <name> (<offline_id>)`; return `true` (the write result shows via
     `save_failed`). `release(offline_id)`: same shape with `roster.release`, log `released <name>`. A **missing
     file is created by the first adopt** through `save()` (dump_file creates the directory).
   - Never writes when the roster is locked, read-only, or there is no unit (the operations refuse first, and
     `save()` checks `writable` again).

4. New `src/autorun/Retinue/game/roster_menu.lua` — the imgui part:
   ```lua
   local M = {}
   -- draw(store, party, unit_label) -- called inside Retinue.lua's draw, under its pcall
   function M.new() end  -- returns { draw = function(self, store, party, unit_label) end }
   return M
   ```
   Lines, in order:
   - `<slot label> · <roster.state_text(store.roster)>` (e.g. `Slot 2 · roster ok (1/2)`, `Slot unknown · no roster
     (slot unknown)`).
   - `Could not save roster.json (see log)` when `store.save_failed`.
   - Each roster warning as a line.
   - One line per member: `roster.member_text(m, { level = <party.level(found view)> or nil, in_party = found[id]
     ~= nil, ambiguous = ambiguous[id] == true })`, then `imgui.same_line()` + button `Release##<offline_id>`.
     (Release on every member, present or away; locked/read-only show the button too and answer with the reason.)
   - For each party view with slot 1 or 2 that is **not** a member: `<name or "?">` and, if `roster.adoptable(view)`,
     same-line button `Adopt##<slot>`; otherwise ` — cannot adopt: <roster.error_text("no_offline_id")>`.
     With no roster (slot unknown) the Adopt buttons still show; pressing one answers `no_slot`.
   - **Inline confirm**: pressing a button sets `pending = { action = "adopt"|"release", offline_id, name }` (for
     adopt, `offline_id = roster.adoptable(view)`, or nil if not adoptable — then the error shows directly, no
     confirm). While pending, the buttons above are not drawn; instead the text `Adopt <name> into your retinue? Gear
     you give them is lost if they're dismissed or lost.` or `Release <name>? Their progress will be lost.` and
     buttons `Yes##retinue_confirm` / `No##retinue_confirm` on one line. Yes: for adopt, find the party view whose
     canonical offline id equals `pending.offline_id` (none → error `not_in_party`) and call `store:adopt(view)`;
     for release `store:release(pending.offline_id)`. No clears pending. Pending is also cleared when the active
     unit changes.
   - **Result line**: after Yes, a failure sets `last_error = "<Adopt|Release> <name>: <roster.error_text(err)>"`,
     shown until the next button press; success clears it.

5. `src/autorun/Retinue.lua` wiring:
   - `local party = party_reader.new(report)`; `local retinue = roster_store.new(report)`; `local menu =
     roster_menu.new()`.
   - `on_frame`: `party.refresh()`; then (each under its own pcall, report key in brackets) `tracker.update(
     party.has_main_pawn())` ["slot"]; `retinue.update(tracker.unit(), party)` ["roster"]; then `state.targets =
     targets.build(party.views(), retinue.roster, prog_hooks.is_hired)` when `prog_hooks.is_hired` is non-nil
     (else `{}`), under pcall ["targets"]; any failure in the roster or targets step sets `state.targets = {}`
     (fail closed: nobody progresses).
   - `draw`: checkbox label becomes `Adopted pawns gain levels and vocation ranks` (same config key), config lines
     as today, the status line from `status.format(party.rows(state.targets))`, then **replace** the
     `slot.label(...)` line with `menu:draw(retinue, party, slot.label(tracker.unit()))`, then the slot-tracking and
     progression-unavailable lines as today.
   - Header comment: describe the narrowed rule (only present adopted pawns progress), the roster file path per
     slot, the new modules (`roster`, `game/jsonfile`, `game/roster_store`, `game/roster_menu`).

**Acceptance criteria**:
- [ ] `tests/run.sh` passes; syntax check passes on every changed/new Lua file.
- [ ] Config read/write behaviour unchanged (same statuses, warnings, error strings) after moving to `jsonfile`.
- [ ] Roster read only when the active unit changes; written only through `save()`, only when `roster.writable`;
  nothing read or written when the unit is nil; a missing file becomes a file on the first adopt.
- [ ] A `not json` roster: locked with the reason in the menu and log, Adopt/Release answer `locked`, file untouched.
- [ ] Targets = `targets.build(party.views(), retinue.roster, is_hired)`; any error → no targets.
- [ ] Owner/OfflineID/name read only on a party change or after an incomplete read, not every frame.
- [ ] One log line per adopt, release, roster activation (+ its warnings) and per member becoming ambiguous; none
  per frame.
- [ ] No game value is written (read-only glue besides the existing M1 hooks).
- [ ] `Retinue.lua` holds no `sdk.` calls.

**Verify**: `tests/run.sh`; `for f in src/autorun/Retinue.lua src/autorun/Retinue/*.lua src/autorun/Retinue/game/*.lua; do luac5.4 -p "$f" || lua5.4 -e "assert(loadfile('$f'))"; done`.

**Out of scope**: backups, transitions (away/returning), reconciliation, native talk menu, notices, docs/README/
CHANGELOG (ticket 27). The in-game check is done with the user after commit.
