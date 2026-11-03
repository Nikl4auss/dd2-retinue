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
