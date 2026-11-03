# M1 plan: ticket 08 (Hired pawns level up)

Source: [issues/08-hired-pawns-level-up.md](issues/08-hired-pawns-level-up.md), [spec.md](spec.md). Base commit: `11d96d7`.

One slice (the ticket). Tier: **Sonnet** (`implementer`). Tickets 09–11 build on the layout fixed here.

- [x] Slice 1: Hired pawns level up (entry script, modules, two core hooks, menu checkbox + notice, test runner)

## Slice 1: Hired pawns level up

**Goal**: with the mod deployed, every hired pawn in the party gains levels, discipline and vocation rank from any exp
source, because Retinue's pre-hooks on `app.ExpDispenser.checkLevelUp` and `app.ExpDispenser.addJobPoint` replace a
target's CharacterID with the main pawn's fixed ID `2283028347` (`ch100000_00`). The *Retinue* menu section has the
progression checkbox (in memory only, on at load) and, if a method is missing, the
`Progression unavailable: <method> not found (game update?)` notice. Notifications still name the main pawn (ticket 09).

**Context** (read first):
- `.scratch/m1-progression/spec.md` § Targets, § Progression hooks, § Toggle, § Failure handling, § Code layout and tests.
- `tools/experiments/Retinue_Exp_Hooks.lua`: copy `find_method` (inside `install_hooks`, ~line 436) verbatim; the
  arg decoding (`arg_u32`: `sdk.to_int64(a) & 0xFFFFFFFF`), `to_u32`, the CharacterID position `args[2]` (spec
  `base = 2` for ExpDispenser), the write `args[2] = sdk.to_ptr(MAIN_ID)`, the party read in `refresh_party`
  (~line 631: `PawnManager._PartyPawnList`, `get_CachedCharacter`, `get_CharaID`, `PawnUtil.isSubPawn` accepting
  `true` or `1`), and the `sdk.hook` wrapper shape with `pcall` + `CALL_ORIGINAL`.
- `deploy.sh`: the loop over `src/autorun/*` already picks up a directory, and `ln -sfn` links it. Only the
  `.gitkeep` files go; leave the script as is unless a check fails.
- `CONTEXT.md` for naming (hired pawn, not sub pawn, in our identifiers and prose).
- Decisions made: no config file yet (ticket 10), no status line yet (ticket 11), no notification swap-back yet
  (ticket 09), but the hook table and all-or-nothing install must let 09 add two methods by appending entries.

**Design**:

Files (Lua 5.4, REFramework resolves `require("Retinue.x")` to `reframework/autorun/Retinue/x.lua`):

1. `src/autorun/Retinue/ids.lua` (pure)
   ```lua
   return { MAIN_PAWN = 2283028347 } -- app.CharacterID ch100000_00
   ```
2. `src/autorun/Retinue/targets.lua` (pure, no REFramework globals)
   ```lua
   local M = {}
   -- The single target predicate. M2 replaces this function to narrow targets to the roster.
   -- id: u32 CharacterID; is_hired: function(id) -> boolean (wraps PawnUtil.isSubPawn in the glue).
   function M.is_target(id, is_hired) return id ~= ids.MAIN_PAWN and is_hired(id) == true end
   -- party_ids: array of u32 CharacterIDs currently in PawnManager._PartyPawnList.
   -- Returns a set { [id] = true } of targets, calling M.is_target (looked up at call time, so a replaced
   -- predicate takes effect).
   function M.build(party_ids, is_hired) ... end
   return M
   ```
   `is_hired` is only called for IDs that are not the main pawn's (short-circuit).
3. `src/autorun/Retinue/progression.lua` (pure)
   ```lua
   local M = {}
   -- Returns the ID to write into argument 1, or nil to leave the args as passed.
   -- state = { enabled = bool, available = bool, targets = { [id] = true } }
   function M.rewrite_id(id, state) end -- ids.MAIN_PAWN iff state.enabled and state.available and state.targets[id]
   return M
   ```
4. `src/autorun/Retinue/errlog.lua` (pure)
   ```lua
   local M = {}
   -- Returns report(where, err): calls sink(string.format("[Retinue] %s: %s", where, tostring(err)))
   -- only the first time a given (where, tostring(err)) pair is seen.
   function M.new(sink) end
   return M
   ```
5. `src/autorun/Retinue/hooks.lua` (REFramework glue, kept thin)
   - `local SPECS = { { key = "checkLevelUp", type = "app.ExpDispenser", sig = "checkLevelUp(app.CharacterID, app.HumanStatusContext, app.Character.JobEnum, System.Boolean, app.DragonHermitContext)", id_arg = 2 }, { key = "addJobPoint", type = "app.ExpDispenser", sig = "addJobPoint(app.CharacterID, app.JobContext, System.Int32, System.Boolean)", id_arg = 2 } }`
     — ticket 09 appends entries (with their own pre/post behaviour), so keep the per-spec body pluggable:
     `M.install(specs_with_bodies, report)`, where each entry carries `pre = function(args)` and optional
     `post = function(retval) -> retval|nil`.
   - `find_method(td, sig)` copied from the experiment.
   - `M.install(entries, report)`: **resolve every method first**; if any type or method is missing, install
     **nothing** and return `false, missing_sigs` (array of the `sig` strings, in order). Otherwise `sdk.hook` each
     and return `true, {}`. Each pre wrapper: `local ok, e = pcall(entry.pre, args); if not ok then report("pre " .. entry.key, e) end; return sdk.PreHookResult.CALL_ORIGINAL`.
     Each post wrapper: if `entry.post` then pcall it, report on error and return `retval`; a non-nil result replaces
     `retval`; with no `entry.post`, return `retval`.
   - Also `M.arg_u32(a)` and `M.to_u32(v)` helpers (from the experiment).
6. `src/autorun/Retinue.lua` (entry, wires everything)
   - State: `local state = { enabled = true, available = false, targets = {} }`, `local missing = {}`.
   - `report = errlog.new(function(msg) log.error(msg) end)`.
   - Core pre body for both methods: `local id = hooks.arg_u32(args[entry.id_arg]); local new = progression.rewrite_id(id, state); if new then args[entry.id_arg] = sdk.to_ptr(new) end`
     (the write is the last statement, so an error leaves the args as passed). Booleans, exp and job points are
     never read or written.
   - Install once at load; `state.available, missing = hooks.install(...)`.
   - `re.on_frame`: under `pcall` (report `"refresh"` on error), rebuild `state.targets` **every frame** from the
     party: `PawnManager` singleton (if nil: `state.targets = {}`), `_PartyPawnList`, `get_CachedCharacter`,
     `to_u32(get_CharaID)`, then `targets.build(ids, is_hired)` with `is_hired = function(id) local r = m_is_sub:call(nil, id); return r == true or r == 1 end`
     (`m_is_sub = app.PawnUtil:get_method("isSubPawn(app.CharacterID)")`, called, never hooked). If `m_is_sub` is
     nil, targets stay empty (no hook-side failure).
   - `re.on_draw_ui`: `if imgui.tree_node("Retinue") then pcall(draw) ... imgui.tree_pop() end`. Draw: checkbox
     `Hired pawns gain levels and vocation ranks` bound to `state.enabled` (always usable); for each missing sig,
     `imgui.text("Progression unavailable: " .. method_name .. " not found (game update?)")`, where
     `method_name` is `"app.ExpDispenser." .. sig` (type + full signature, so the user can report it). UI error →
     `imgui.text("UI error: ...")`.
   - Header comment: what the mod does at this stage, that the experiment script must not be deployed alongside.
7. Tests: `tests/run.sh` (bash, `set -uo pipefail`, executable): runs every `tests/*_test.lua` with
   `LUA_PATH="$ROOT/src/autorun/?.lua;;" lua5.4 <file>` from the repo root, prints `PASS`/`FAIL <file>`, exits 1 if
   any failed or if no test file exists. Test files: `tests/targets_test.lua`, `tests/progression_test.lua`,
   `tests/errlog_test.lua`, plain `assert`.
   - targets: main ID excluded (and `is_hired` not called for it); hired ID included; non-hired ID excluded;
     `is_hired` returning `1`/non-true → excluded; empty party → empty set; replacing `targets.is_target` changes
     `build`'s result.
   - progression: target + enabled + available → MAIN_PAWN; disabled → nil; unavailable → nil; non-target → nil;
     main ID → nil.
   - errlog: same pair logged once; different message or different `where` logged again; non-string err ok.
8. Remove `src/autorun/.gitkeep` and `tests/.gitkeep`. In `deploy.sh`, the `.gitkeep` skip may stay (harmless).

**Acceptance criteria**:
- [ ] Only `checkLevelUp` and `addJobPoint` are hooked; no `addExpAndJobPoint`, no `isSubPawn` hook anywhere.
- [ ] Only argument at `args[2]` is ever written, and only to `2283028347`; no multiplier.
- [ ] Checkbox off → pre body writes nothing; read on every call.
- [ ] Every hook body is under `pcall`, pre returns `CALL_ORIGINAL`, errors are logged once per (method, message).
- [ ] Missing method → no hooks installed, `state.available = false`, notice per missing method.
- [ ] Targets rebuilt every frame; predicate is the single `targets.is_target`.
- [ ] Pure modules use no REFramework globals (`sdk`, `re`, `imgui`, `log`, `json`).
- [ ] `tests/run.sh` passes, and exits non-zero when a test fails (check by breaking one temporarily, then revert).
- [ ] `./deploy.sh` would link both `Retinue.lua` and the `Retinue/` folder (dry-check with a temp `DD2_DIR`
      containing `reframework/autorun/`).

**Verify**:
- `tests/run.sh`
- `luac5.4 -p src/autorun/Retinue.lua src/autorun/Retinue/*.lua` (or `lua5.4 -e 'loadfile(...)'` if `luac5.4` is absent)
- `d=$(mktemp -d); mkdir -p "$d/reframework/autorun"; DD2_DIR="$d" ./deploy.sh; ls -l "$d/reframework/autorun"; DD2_DIR="$d" ./deploy.sh --remove`

**Out of scope**: config.json (10), status line (11), notification swap-back and the open-call stack (09), README /
CHANGELOG / roadmap (12), anything in `tools/`.

## Cross-review

Plan stage: Sol attempted, failed (`gpt-6-sol` not supported with a ChatGPT account, HTTP 400). Proceeding with the Opus reviewer alone.

# Ticket 11 (Menu status line)

Source: [issues/11-menu-status-line.md](issues/11-menu-status-line.md), spec § Menu. Base commit: `6d33bd0`.
Tier: **Sonnet** (`implementer`). Cross-review: skipped (Sol unavailable; no Astra trigger).

- [x] Slice 2: Menu status line

## Slice 2: Menu status line

**Goal**: the *Retinue* menu shows, under the checkbox and whatever its state, which party pawns progression applies
to right now: `Applies to: <name> (Lv <level>, <vocation> R<rank>), ...`, or `No hired pawns in party`, or
`Load a save`. It follows party changes without *Reset scripts*. It also lets the user finish ticket 08's in-game
check (level and rank visible per hired pawn).

**Context**: `src/autorun/Retinue.lua` (refresh_targets, draw), `src/autorun/Retinue/targets.lua`, the test style in
`tests/*_test.lua` and `tests/run.sh`. Reads to copy from `tools/experiments/Retinue_Exp_Hooks.lua`: `read_progress`
(~line 569: `chara:call("get_Human")`, `human:call("get_StatusContext")` → `get_Level`, `human:call("get_JobContext")`
→ `get_Job`, `calcJobRank(job)`) and `m_gui_name` (~line 75: `app.GUIBase` `getName(app.Character)`, called as
`m_gui_name:call(nil, chara)`). Vocation names from `CONTEXT.md` § Progression.

**Design**:
1. New pure module `src/autorun/Retinue/status.lua` (no REFramework globals):
   ```lua
   local M = {}
   M.VOCATIONS = { [1]="Fighter", [2]="Archer", [3]="Mage", [4]="Thief", [5]="Warrior", [6]="Sorcerer",
                   [7]="Mystic Spearhand", [8]="Magick Archer", [9]="Trickster", [10]="Warfarer" }
   -- job: number or nil. Known → its name; other number → "Vocation <n>"; nil → "?".
   function M.vocation_name(job) end
   -- rows: nil when no save is loaded; otherwise an array (party order) of
   --   { name = string|nil, level = number|nil, job = number|nil, rank = number|nil }.
   -- nil → "Load a save"; {} → "No hired pawns in party";
   -- else "Applies to: " .. rows joined with ", ", each "%s (Lv %s, %s R%s)".
   -- A nil or empty name, and a nil level or rank, print as "?". Integral floats print without ".0".
   function M.format(rows) end
   return M
   ```
2. `Retinue.lua`:
   - `refresh_targets` additionally keeps, in a file-local, `party_loaded` (true once PawnManager and
     `_PartyPawnList` are both non-nil this frame, else false) and `target_charas`: an array, in party order, of the
     `app.Character` of each party pawn whose ID is in the new `state.targets` set. Reset both on every early return
     and on refresh error (`party_loaded = false`, `target_charas = {}`). Do not put these in `state`
     (`progression.rewrite_id` only needs `state.targets`).
   - `m_gui_name` resolved once at load like `m_is_sub` (may be nil → name nil).
   - New `local function read_row(chara)`: returns `{ name, level, job, rank }`, each field read under its own
     `pcall` (nil on failure or when the context is nil). Name = `tostring` of the `getName` result when non-nil.
   - Rows are read in `draw` only (so the reads cost nothing while the menu is closed):
     `rows = party_loaded and map(target_charas, read_row) or nil`, then `imgui.text(status.format(rows))`.
   - Draw order: checkbox, status line, then the `Progression unavailable` lines. The status line is shown whether
     the checkbox is on or off and whether hooks are available.
   - Update the header comment to mention the status line and `Retinue/status.lua` among the pure modules.
3. `tests/status_test.lua`: nil → `Load a save`; `{}` → `No hired pawns in party`; one row
   `{name="Ana", level=12, job=1, rank=3}` → `Applies to: Ana (Lv 12, Fighter R3)`; two rows joined with `", "` in
   order; job 11 → `Vocation 11`; nil job → `?`; nil/empty name, nil level, nil rank → `?`; `level = 12.0` → `Lv 12`;
   all ten `VOCATIONS` entries match CONTEXT.md.

**Acceptance criteria**:
- [ ] The three line variants appear exactly as specified, with glossary vocation names.
- [ ] The line follows party changes (built from per-frame state, nothing cached across frames beyond one refresh).
- [ ] A read failure for one field shows `?` and never hides the line or the checkbox.
- [ ] Shown regardless of the checkbox and of the unavailable notice.
- [ ] `status.lua` has no REFramework globals. `tests/run.sh` passes.
- [ ] No change to hooks, progression or targets behaviour.

**Verify**: `tests/run.sh`; `luac5.4 -p src/autorun/Retinue.lua src/autorun/Retinue/*.lua tests/*.lua`;
`grep -nE '\b(sdk|re|imgui|log|json)\.' src/autorun/Retinue/{ids,targets,progression,errlog,status}.lua` (no hits).

**Out of scope**: config.json (10), notifications (09), discipline in the line (not in the spec), any change in `tools/`.

# Ticket 09 (Notifications name the hired pawn)

Source: [issues/09-notifications-name-hired-pawn.md](issues/09-notifications-name-hired-pawn.md), spec § Notification
swap-back, § Failure handling; findings [0003](../../docs/findings/0003-notification-swap-back.md). Base commit: `d94740b`.
Tier: **Sonnet** (`implementer`). Cross-review: skipped (Sol unavailable; no Astra trigger).

- [x] Slice 3: Notifications name the hired pawn

**Design decision (deviation from the spec's wording, recorded in the spec by this slice):** the core pre-hook pushes
a frame for **every** `checkLevelUp` / `addJobPoint` call, with `real = nil` unless it rewrote; the swap looks only at
the **top** frame. Why: post-hooks can't tell whether their own pre pushed, so "push only when rewriting" lets a
non-rewritten call's post pop an outer rewritten entry, and a stale rewritten entry left in the same frame would
rename the main pawn's next level-up. With one frame per call, a main-pawn or toggle-off call always sits on top
with `real = nil`, so a stale entry below it can never rename its notification. `real` is set only after the arg write
succeeds, so an error never leaves a renaming entry (this replaces "remove the entry on error", which would break the
pre/post pairing). Observable behaviour is the spec's.

## Slice 3: Notifications name the hired pawn

**Goal**: level-up and rank-up notifications for a hired pawn show its own name, once. The player's and the main
pawn's notifications are never touched.

**Context**: `src/autorun/Retinue.lua` (make_entry, on_frame, header), `src/autorun/Retinue/hooks.lua` (SPECS,
install; note its `id_arg` comment: instance methods have the ID at `args[3]`), `tests/hooks_test.lua` (stub `sdk`),
`tools/experiments/Retinue_Exp_Hooks.lua` (`pre_body` swap block ~line 375, `post_body` pop ~line 394, SPECS entries
for `dispLevelUpUI` (base 2) and `GuiManager.reqJobRankUp` (base 3)). Call structure (findings 0003):
`checkLevelUp` → `dispLevelUpUI` directly; `addJobPoint` → `addJobPointInternal` (not hooked) → `GuiManager.reqJobRankUp`.

**Design**:
1. New pure module `src/autorun/Retinue/opencalls.lua` (no REFramework globals):
   ```lua
   local M = {}
   M.MAX_DEPTH = 64
   -- Returns a stack object with methods:
   --   s:push(key) -> frame   frame = { key = key, real = nil }. If depth is already MAX_DEPTH, clears first
   --                          (defensive; returns true as a second value when it had to clear).
   --   s:pop(key)             removes the innermost frame whose key == key and every frame above it
   --                          (stale frames whose post never ran). No-op if none matches.
   --   s:clear()              empties the stack (start of every game frame).
   --   s:depth() -> integer
   --   s:swap_id(id) -> real|nil   the top frame's `real` iff id == ids.MAIN_PAWN and the stack is non-empty and the
   --                          top frame's real ~= nil; else nil.
   function M.new() end
   return M
   ```
2. `hooks.lua` `SPECS`: add a `role` field to every entry (`"core"` for the two existing ones) and append:
   - `{ key = "dispLevelUpUI", role = "swap", type = "app.ExpDispenser", sig = "dispLevelUpUI(app.CharacterID, System.Int32, System.Int32)", id_arg = 2 }`
   - `{ key = "reqJobRankUp", role = "swap", type = "app.GuiManager", sig = "reqJobRankUp(app.CharacterID, app.Character.JobEnum, System.Int32, System.Int32)", id_arg = 3 }`
   `install` itself is unchanged (already all or nothing over every entry passed).
3. `Retinue.lua`:
   - `local calls = opencalls.new()`.
   - Core entry (`role == "core"`):
     pre: `local frame, overflowed = calls:push(spec.key)` (if `overflowed`, `report("opencalls", "stack overflow, reset")`);
     then `local id = hooks.arg_u32(args[spec.id_arg]); local new = progression.rewrite_id(id, state)`;
     `if new then args[spec.id_arg] = sdk.to_ptr(new); frame.real = id end` (real set after the write).
     post: `calls:pop(spec.key)`; returns nil (retval passes through).
   - Swap entry (`role == "swap"`): pre only:
     `local real = calls:swap_id(hooks.arg_u32(args[spec.id_arg])); if real then args[spec.id_arg] = sdk.to_ptr(real) end`.
     No push, no post.
   - `re.on_frame`: `calls:clear()` first (outside the refresh pcall, it can't fail), then the existing refresh.
   - Do not gate the swap on `state.enabled`: with progression off no frame has `real`, so nothing swaps; turning it
     off mid-call still lets the open rewritten call's notification be renamed correctly.
   - Header comment: notifications now name the hired pawn; list `opencalls.lua` among the pure modules; four hooks,
     all or nothing.
4. Spec edits (`.scratch/m1-progression/spec.md`): in § Notification swap-back, replace the "Open rewritten calls are
   tracked as a stack ..." bullet with the one-frame-per-call rule above (top frame only, `real` set after the write,
   stale frames dropped by an outer pop, stack cleared every frame). In § Toggle, change "no rewrite and no stack
   push" to "no rewrite (core calls still push a frame without a real ID, which renames nothing)". In § Failure
   handling, change "any entry the failing call pushed is removed" to "a failing call's frame never carries a real ID".
   Keep the rest.
5. Tests:
   - `tests/opencalls_test.lua`: rewritten call open → `swap_id(MAIN)` = real; none open → nil; non-main ID → nil
     even with a rewritten frame on top; nested: rewritten outer (real 1) + non-rewritten inner → nil, after inner pop →
     1; two nested rewritten (1 then 2) → 2, after pop → 1; stale: push A(real 1), push B(real 2) with no pop, `pop("A")`
     → depth 0 and nil; stale in the same game frame: push A(real 1) never popped, then a main-pawn call pushes C
     (real nil) → nil; `clear()` → nil and depth 0; `pop` of an absent key is a no-op; overflow: pushing past MAX_DEPTH
     clears and returns true; a frame whose real was never set (error path) → nil.
   - `tests/hooks_test.lua`: extend the stub so the four SPECS resolve (add `app.GuiManager`); assert install hooks 4
     when all are present and 0 when only `reqJobRankUp` is missing, listing `app.GuiManager.reqJobRankUp(...)`.

**Acceptance criteria**:
- [ ] Exactly four hooks; `addExpAndJobPoint` and `isSubPawn` still never hooked.
- [ ] Swap only when the incoming ID is the main pawn's and the top frame carries a real ID; uses that ID.
- [ ] A notification inside a non-rewritten call (main pawn, toggle off, player via SkillCreator) is never renamed,
      even with a stale entry below.
- [ ] Stack cleared at the start of every `re.on_frame`; stale frames dropped by an outer pop.
- [ ] Every hook body under pcall, CALL_ORIGINAL always, errors logged once; a failing core pre leaves args as passed
      and its frame with `real = nil`.
- [ ] All four methods all or nothing; the notice lists each missing one with its type.
- [ ] Spec updated as in Design 4. `tests/run.sh` passes; `opencalls.lua` has no REFramework globals.

**Verify**: `tests/run.sh`; `luac5.4 -p src/autorun/Retinue.lua src/autorun/Retinue/*.lua tests/*.lua`;
`grep -nE '\b(sdk|re|imgui|log|json)\.' src/autorun/Retinue/{ids,targets,progression,errlog,status,opencalls}.lua` (no hits);
`grep -n 'addExpAndJobPoint\|isSubPawn' src -r` (only the `PawnUtil.isSubPawn` get_method).

**Out of scope**: config.json (10), status line, anything in `tools/`.

# Ticket 10 (Toggle persists in `config.json`)

Source: [issues/10-toggle-persists-in-config.md](issues/10-toggle-persists-in-config.md), spec § `config.json`,
§ Toggle; decision in [issues/07](issues/07-config-and-menu-shape.md). Base commit: `295b5be`.
Tier: **Sonnet** (`implementer`). Cross-review: skipped (Sol unavailable; no Astra trigger).

- [x] Slice 4: Toggle persists in config.json

## Slice 4: Toggle persists in config.json

**Goal**: the progression checkbox survives *Reset scripts* and relaunches, in `reframework/data/Retinue/config.json`
(`{ "version": 1, "progression": true }`). A fresh install writes nothing until the user changes the setting; a
hand-edited file with mistakes never breaks the mod and is never silently overwritten.

**Context**: `src/autorun/Retinue.lua` (state, draw), the pure-module pattern in `src/autorun/Retinue/*.lua` and the
tests in `tests/`. Spec § `config.json` is the behaviour contract.

**Design**:
1. New pure module `src/autorun/Retinue/config.lua` (no REFramework globals):
   ```lua
   local M = {}
   M.PATH = "Retinue/config.json"   -- relative to reframework/data (json.* and fs.* root)
   M.VERSION = 1
   M.DEFAULTS = { progression = true }
   M.TYPES = { progression = "boolean" }

   -- status: "missing" | "unparseable" | "ok"; data: the decoded value when status == "ok".
   -- Returns settings, warnings, base:
   --   settings: { progression = boolean } (a key with the right type is used; otherwise its default)
   --   warnings: array of strings, for log.warn, each prefixed "[Retinue] config.json: "
   --   base: the decoded object to preserve unknown keys from on rewrite, or nil.
   -- "missing"     -> defaults, no warnings, base nil.
   -- "unparseable" -> defaults, one warning ("not valid JSON; using defaults. The file is left as is until a
   --                  setting is changed."), base nil.
   -- "ok" but data is not a table, or is a JSON array (`#data > 0`) -> defaults, one warning ("top level is not
   --                  an object; using defaults ..."), base nil.
   -- "ok" object    -> per known key: right type -> used; missing or wrong type -> default plus one warning
   --                  naming the key, e.g. 'progression is missing or not a boolean; using true'. base = data.
   --                  `version` is not validated and never warns; a higher version is read for the known keys.
   function M.resolve(status, data) end

   -- Returns a NEW table to write: a shallow copy of base (unknown keys kept; base not mutated; nil base -> {}),
   -- with every known key from settings, and version = base.version if it is an integer > M.VERSION, else M.VERSION.
   function M.merge(base, settings) end
   return M
   ```
2. `Retinue.lua` glue:
   - At load (once), `local function read_config()` returns `status, data`:
     - If `fs` and `fs.read` exist: `local ok, text = pcall(fs.read, config.PATH)`. Not ok, nil or `""` → `"missing"`.
       Otherwise `local okd, data = pcall(json.load_string, text)`; not okd or `data == nil` → `"unparseable"`, else
       `"ok", data`.
     - Fallback when `fs.read` is unavailable: `local ok, data = pcall(json.load_file, config.PATH)`; nil or error →
       `"missing"`, else `"ok", data` (unparseable then reads as missing: documented limitation in a comment).
   - `local settings, warnings, base = config.resolve(read_config())`; each warning → `log.warn(w)`;
     `state.enabled = settings.progression`. Keep `config_base = base` (file-local).
   - Checkbox change: `state.enabled = value` first (the toggle takes effect even if the write fails), then
     `local out = config.merge(config_base, { progression = value })`, `pcall(json.dump_file, config.PATH, out)`.
     Success (pcall ok and result ~= false) → `config_base = out`. Failure → `report("config write", err or "dump_file returned false")`
     and show `imgui.text("Could not save config.json (see log)")` under the checkbox until the next successful write.
   - `re.on_config_save` is not used. Nothing is written at load, ever.
   - Header comment: mention config.json and `config.lua`.
3. `tests/config_test.lua`: missing → `{progression=true}`, no warnings, base nil; valid `{version=1, progression=false}`
   → false, no warnings, base is data; wrong type `"yes"` → true plus one warning naming `progression`; missing key
   `{version=1}` → true plus one warning; unparseable → defaults plus one warning; non-object (`"x"`, `42`, `{1,2}`) →
   defaults plus one warning; higher version `{version=3, progression=false}` → false, and `merge` keeps version 3;
   unknown keys `{version=1, progression="yes", extra=1}` → merge with `{progression=false}` gives
   `{version=1, progression=false, extra=1}`; merge(nil, s) → `{version=1, progression=...}`; merge does not mutate
   base; version 0, `"2"`, 1.5 → written as 1.

**Acceptance criteria**:
- [ ] Read once at load; written immediately on every menu change; never written at load or by `re.on_config_save`.
- [ ] Fresh install (no file) → progression on and no file created until a change.
- [ ] Per-key resolution and warnings as specified; garbage or non-object → defaults + warning; file untouched until a change.
- [ ] Rewrite keeps unknown keys and never lowers `version`.
- [ ] A failed write logs once, shows the menu note, and leaves the in-memory toggle as chosen.
- [ ] `config.lua` pure; `tests/run.sh` passes.

**Verify**: `tests/run.sh`; `luac5.4 -p src/autorun/Retinue.lua src/autorun/Retinue/*.lua tests/*.lua`;
`grep -nE '\b(sdk|re|imgui|log|json|fs)\.' src/autorun/Retinue/{ids,targets,progression,errlog,status,opencalls,config}.lua` (no hits);
`grep -n on_config_save -r src` (no hits).

**Out of scope**: the roster (M2), any other setting, docs (12), `tools/`.

# Final pass

Opus reviewer over `11d96d7...HEAD`: CHANGES_REQUESTED, all fixed in `0b9a889` except one recorded gap.

- Fixed: `deploy.sh --experiments` linked the mod too (now mutually exclusive); `sdk.hook` throw aborted the script;
  missing `PawnUtil.isSubPawn` was silent; refresh failure showed `Load a save`; header omitted discipline.
- Known gap (accepted, within the ticket 09 design): a stale rewritten frame (its post never ran) can return to the top
  after a later main-pawn core call pops, and would rename a main-pawn notification fired outside any core call in the
  same game frame. No known caller does this (findings 0004).
- Cross-review: skipped at both gates (Sol unavailable; no Astra trigger).
