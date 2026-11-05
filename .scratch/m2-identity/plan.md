# M2 plan: ticket 16 (The mod knows which save slot is loaded)

Source: [issues/16-save-slot-known.md](issues/16-save-slot-known.md), [spec.md](spec.md) § Save slot, § Code layout and
tests; [findings 0010](../../docs/findings/0010-m2-save-slot-identity.md). Base commit: `75b0ec7`.

Two slices, sequential (slice 2 edits files slice 1 creates).

- [x] Slice 1: Prefactor the entry script into `Retinue/game/` modules (no behaviour change). Tier: **Sonnet** (`implementer`).
- [ ] Slice 2: Save-slot tracking: pure `slot` module + tests, slot hooks, fallback, menu line. Tier: **Sonnet** (`implementer`).

Facts the design rests on (from the experiment run files in `docs/findings/data/2026-11-05-saveslot/`):

- `requestStartType` always fires **before** `requestLoadGameData` (30–60 ms apart): `Latest`→load 0,
  `SystemMenuSave`→load 4/9, `RedoNewGame`→load 8, `RedoNewGameSkip`→load 3. `NewGame` (empty unit) has no load.
  A death reload is `restart()` → `requestLoadGameData(n)` with no start. `ExitGame` is also a start type.
- So: a start request clears the unit (except `NewGame`, which sets it from `UnitNumber`) and the load request that
  follows sets it. A unit switch in one session therefore never shows the previous unit.
- Every load passes through `requestLoadGameData`, so "no such call seen this session" also means "no load is in
  progress": the fallback needs only "main pawn in the party and `get_IsTitleMenuPhase()` false".

---

## Slice 1: Prefactor the entry script into game modules

**Goal**: no player-visible change. The REFramework-facing code of `src/autorun/Retinue.lua` (244 lines) is split
into thin game-facing modules under `src/autorun/Retinue/game/`, so later M2 tickets add files there instead of
growing the entry script. The menu, config handling, hooks, logs and failure behaviour are byte-for-byte the same in
effect.

**Context** (read first):
- `src/autorun/Retinue.lua` (all of it), `src/autorun/Retinue/hooks.lua`, `src/autorun/Retinue/config.lua`.
- `.scratch/m2-identity/spec.md` § Code layout and tests ("REFramework glue stays thin; it may be split under
  `src/autorun/Retinue/game/`").
- REFramework resolves `require("Retinue.game.x")` to `reframework/autorun/Retinue/game/x.lua`; `deploy.sh` links
  the whole `src/autorun/Retinue` directory, so no deploy change is needed.
- The modules under `game/` use REFramework globals (`sdk`, `json`, `fs`, `log`, `re`, `imgui`) and are not tested
  under plain Lua; the pure modules and their tests stay as they are.

**Design** — move code, do not rewrite it. Keep every comment that explains a decision (move it with its code).

1. `src/autorun/Retinue/game/config_store.lua`: `read_config`, `written`, `save_config` and their state.
   ```lua
   local M = {}
   -- report: errlog reporter. Reads config.json once (as today), logs the warnings with log.error.
   -- Returns a store: { settings = <config.resolve settings>, warnings = {...}, save_failed = false,
   --                    save = function(self, value) ... end }
   function M.open(report) ... end
   return M
   ```
   `store:save(value)` is today's `save_config` (merge into the base, dump, read back, set `save_failed`, clear
   `warnings` on success, `report("config write", err)` on failure).
2. `src/autorun/Retinue/game/progression_hooks.lua`: `make_entry`, the entries loop, `hooks.install`, the `isSubPawn`
   lookup (and its "missing" line), the open-call stack.
   ```lua
   local M = {}
   -- state: the shared { enabled, available, targets } table (read by progression.rewrite_id).
   -- Returns { available = bool, missing = {strings}, is_hired = function(id) -> bool | nil (nil when isSubPawn
   --           is missing), clear_calls = function() }
   function M.install(state, report) ... end
   return M
   ```
3. `src/autorun/Retinue/game/party.lua`: `refresh_targets`, `read_row`, the `getName` lookup, and the party state
   (`party_loaded`, `target_charas`).
   ```lua
   local M = {}
   -- state: shared table; refresh writes state.targets. is_hired may be nil.
   -- Returns an object with:
   --   refresh()  -- today's refresh_targets + the pcall/refresh_failed handling from re.on_frame (reports "refresh")
   --   rows()     -- nil when no party is loaded, else an array of read_row results (the status.format input)
   --   failed     -- boolean, last refresh threw
   function M.new(state, is_hired, report) ... end
   return M
   ```
4. `src/autorun/Retinue.lua` becomes the wiring: header comment (updated to describe the new layout; keep the
   warning about `Retinue_Exp_Hooks.lua`), the `state` table, `report`, `config_store.open`, `progression_hooks.install`,
   `party.new`, the three callbacks (`re.on_pre_application_entry("UpdateBehavior", clear_calls)`,
   `re.on_frame(party:refresh)`, `re.on_draw_ui`) and `draw`. `draw` produces exactly the same imgui calls in the same
   order as today.

**Acceptance criteria**:
- [ ] `tests/run.sh` passes (no test changes needed; none may be removed or weakened).
- [ ] `luac5.4 -p` (or `lua5.4 -e 'loadfile(...)'`-style syntax check) passes on every changed/new `.lua` file.
- [ ] Every function and branch of the old `Retinue.lua` exists in exactly one new place; behaviour identical: same
  log strings and `report` keys ("config write", "opencalls", "refresh", "pre <key>", …), same menu texts and order,
  same order of side effects at load (config read and warnings logged before hooks are installed).
- [ ] `Retinue.lua` holds no `sdk.` calls: only requires, wiring, callbacks and `draw`.
- [ ] No new behaviour, no new menu lines.

**Verify**: `tests/run.sh`; `for f in src/autorun/Retinue.lua src/autorun/Retinue/game/*.lua; do luac5.4 -p "$f"; done`
(use `lua5.4 -e "assert(loadfile('$f'))"` if `luac5.4` is not installed).

**Out of scope**: any slot code; changing pure modules; renaming user-visible strings; deploy.sh; docs.

---

## Slice 2: The mod knows which save slot is loaded

**Goal**: the *Retinue* menu shows `Slot N` (1–3) for the loaded save slot, or `Slot unknown`. The unit is set from
the game's start and load requests; a fallback covers a mod loaded mid-session (Reset scripts) only when two game
values agree. The start type is classified and kept for later tickets. A missing hook leaves the slot unknown.

**Context** (read first):
- `.scratch/m2-identity/issues/16-save-slot-known.md`, `.scratch/m2-identity/spec.md` § Save slot.
- `docs/findings/0010-m2-save-slot-identity.md` (layout, which unit is loaded, new game and NG+).
- This plan's "Facts the design rests on" section above.
- Slice 1's modules (`src/autorun/Retinue.lua`, `src/autorun/Retinue/game/*.lua`), `src/autorun/Retinue/hooks.lua`
  (`install`, `arg_u32`), `src/autorun/Retinue/errlog.lua`, `src/autorun/Retinue/status.lua` + `tests/status_test.lua`
  (pure-module and test style: plain `assert`s, run by `tests/run.sh` under Lua 5.4).
- `tools/experiments/Retinue_Exp_SaveSlot.lua`: how it reads statics (`td:get_field(name):get_data(nil)`), enum names
  (`enum_name`: static fields of the enum type, value → name), `arg_i32`, and `world_state` (in_world).
- Terms (CONTEXT.md): "save slot" is the player's slot = the game's **unit** (0–2). A **global slot** is
  `unit × SLOT_PER_UNIT + type`.

**Design**:

1. Pure `src/autorun/Retinue/slot.lua` (no REFramework globals):
   ```lua
   local M = {}
   M.NEW_PLAYTHROUGH, M.NG_PLUS, M.LOAD = "new_playthrough", "ng_plus", "load"
   M.ROOT = "Retinue/slots" -- relative to reframework/data, like config.PATH

   -- Integer view of a number: integral floats accepted (2.0 -> 2); anything else -> nil.
   -- unit_of(global_slot, per_unit) -> integer unit >= 0, or nil when either is not an integer, per_unit < 1,
   -- or global_slot < 0 (the system save is -1). Floor division: 9, 5 -> 1; 4, 5 -> 0.
   function M.unit_of(global_slot, per_unit) end

   -- classify(start_name) -> NEW_PLAYTHROUGH for "NewGame" and "RedoNewGame", NG_PLUS for "RedoNewGameSkip",
   -- LOAD for any other string, nil for a non-string (name unreadable).
   function M.classify(start_name) end

   -- fallback(last_loaded_slot, unit_number, per_unit) -> unit_of(last_loaded_slot, per_unit) when that is non-nil
   -- and equals unit_number (integer view), else nil.
   function M.fallback(last_loaded_slot, unit_number, per_unit) end

   -- dir(unit) -> "Retinue/slots/<unit + 1>"; archive_name(t) -> "archive-<yyyymmdd-hhmmss>" from an os.date("*t")
   -- shaped table (zero-padded); archive_dir(unit, t) -> dir(unit) .. "/" .. archive_name(t).
   function M.dir(unit) end
   function M.archive_name(t) end
   function M.archive_dir(unit, t) end

   -- label(unit) -> "Slot <unit + 1>" or "Slot unknown" for nil.
   function M.label(unit) end

   -- Session state. Fields read by the glue and later tickets:
   --   unit        integer | nil  the loaded unit
   --   source      "load" | "new_game" | "fallback" | nil  how unit was set
   --   seen        boolean  a start or load request was seen this session (disables the fallback for good)
   --   last_start  nil | { name = string|nil, kind = classify(name) }  the last start request
   --   starts      integer  count of start requests seen (later tickets detect a new start by comparing it)
   function M.new_session() end
   -- requestLoadGameData pre: seen = true; unit = unit_of(global_slot, per_unit); source = unit and "load" or nil.
   function Session:on_load_request(global_slot, per_unit) end
   -- requestStartType pre: seen = true; starts += 1; last_start = { name, kind }. If name == "NewGame": unit =
   -- unit_number's integer view if >= 0 else nil, source = unit and "new_game" or nil. Any other name (including
   -- nil): unit = nil, source = nil (the load request that follows sets it).
   function Session:on_start_request(name, unit_number) end
   -- Called by the glue every frame while in the world. Does nothing once seen. Otherwise unit = fallback(...),
   -- source = unit and "fallback" or nil.
   function Session:on_world(last_loaded_slot, unit_number, per_unit) end
   return M
   ```
2. `tests/slot_test.lua`: `unit_of` (0..14 with 5 → 0..2, 9→1, 8→1, 3→0, -1→nil, nil/strings/non-integer floats →
   nil, integral floats ok, per_unit 0/nil → nil); `classify` (the 3 kinds, `Latest`, `Base`, `SystemMenuSave`,
   `ExitGame` → load, nil → nil); `fallback` (agree → unit, disagree → nil, LastLoadedSlot 0 + UnitNumber 0 → 0,
   nil inputs → nil); `dir` (0→`Retinue/slots/1`, 2→`Retinue/slots/3`); `archive_name` zero padding
   (`{year=2026,month=1,day=5,hour=3,min=4,sec=9}` → `archive-20260105-030409`) and `archive_dir`; `label`; the
   session: the experiment sequences (start `SystemMenuSave` + load 9 → unit 1; `Latest` + load 0 → 0; death reload
   load 0 without start → 0; `NewGame` with UnitNumber 2 → 2, source new_game; `RedoNewGame` + load 8 → 1 and
   `last_start.kind == NEW_PLAYTHROUGH`; `RedoNewGameSkip` + load 3 → 0, NG_PLUS); a start alone (not NewGame)
   clears a previous unit; load with per_unit nil → unknown; unreadable start name → unit nil, kind nil;
   `on_world` before anything seen → fallback applied, disagreeing values → nil, after any request → ignored;
   `starts` counts.
3. `src/autorun/Retinue/hooks.lua`: add `M.arg_i32(a)` (signed 32-bit view, as in the experiment) next to
   `arg_u32`, plus a test line in `tests/hooks_test.lua` (`arg_i32(0xFFFFFFFF) == -1`, `arg_i32(9) == 9`).
4. `src/autorun/Retinue/game/slot_hooks.lua` (REFramework glue):
   ```lua
   local M = {}
   -- Installs the two pre-hooks (hooks.install, all or nothing, own entries; does not touch hooks.SPECS):
   --   app.MainFlowManager requestLoadGameData(System.Int32)          global slot at args[3] (instance method)
   --   app.MainFlowManager requestStartType(app.MainFlowManager.StartType)  enum value at args[3]
   -- Returns a tracker: { available = bool, missing = {strings}, session = slot.new_session(),
   --                      update(in_world) -- call every frame; in_world: boolean
   --                      unit() -> integer|nil }
   function M.install(report) end
   return M
   ```
   - `SLOT_PER_UNIT`: read from `app.GameSystem`'s static field (`get_field("SLOT_PER_UNIT"):get_data(nil)`) at first
     need and cached once it is an integer ≥ 1; while unreadable, `report("slot", "SLOT_PER_UNIT unreadable")` and pass
     nil (→ unit unknown). Never a hard-coded 5.
   - Start name: value → name map from the static fields of `app.MainFlowManager.StartType` (as the experiment's
     `enum_name`), built once; an unknown value → name nil and `report("slot", "StartType <v> has no name")`.
   - `UnitNumber`: `sdk.get_managed_singleton("app.GameSystem"):call("get_UnitNumber")` (nil on failure).
     `LastLoadedSlot`: `app.MainFlowManager` singleton `:call("get_LastLoadedSlot")`.
   - Pre bodies run inside `hooks.install`'s pcall; they only update the session (no world reads beyond the two
     getters above), and never change args.
   - `update(in_world)`: if `available` and `in_world`, call `session:on_world(LastLoadedSlot, UnitNumber, per_unit)`
     (reads under pcall; a failure reports "slot" once and changes nothing).
   - If `available` is false the session is never fed and `unit()` is always nil (fail closed, no fallback). The
     missing methods are logged once each with `log.error("[Retinue] slot tracking unavailable: <method> not found")`.
   - **Log one line on every change of `unit` or `source`** (compare after each hook and after `update`):
     `[Retinue] slot: Slot 2 (load request, global slot 9)`, `… (new game)`, `… (fallback: LastLoadedSlot 4, UnitNumber 0)`,
     `[Retinue] slot: unknown (start request <name>)` etc. Use `log.error` (the mod's convention: another mod may raise
     the log level and drop warnings). These lines are how the in-game check is read.
5. `game/party.lua`: expose whether the main pawn (`ids.MAIN_PAWN`) is in `_PartyPawnList` (from the same party read;
   false when no party). `Retinue.lua` computes `in_world = party.has_main_pawn() and not title_phase`, where
   `title_phase` is `app.MainFlowManager:get_IsTitleMenuPhase()` read in slot_hooks (put the read inside
   `update`, i.e. `update(has_main_pawn)` and slot_hooks reads the title phase itself — implementer's choice, but
   the definition is exactly "main pawn in the party and not the title menu phase"; an unreadable title phase counts
   as not in the world). `on_frame` calls `party:refresh()` then the tracker's `update`, each under its own pcall.
6. Menu (`draw` in `Retinue.lua`): after the M1 status line and before the "Progression unavailable" lines, one line
   `slot.label(tracker.unit())`; and for each `tracker.missing`: `Slot tracking unavailable: <method> not found (game
   update?)`. Nothing else changes.
7. Update the header comment of `Retinue.lua` (one sentence: the menu shows the loaded save slot; the decisions live in
   `Retinue/slot.lua` too).

**Acceptance criteria**:
- [ ] `tests/run.sh` passes with the new `tests/slot_test.lua` covering every case listed in Design 2.
- [ ] `slot.lua` has no REFramework globals; `SLOT_PER_UNIT` appears nowhere as a literal 5 in `src/` (tests may use 5).
- [ ] Start classification exposed on the session (`last_start`, `starts`); nothing is archived or written.
- [ ] Missing hook method → slot always unknown, logged once per method, menu line shown; M1 progression unaffected.
- [ ] One log line per slot change; none per frame.
- [ ] Syntax check of all changed Lua files passes.

**Verify**: `tests/run.sh`; syntax check as in slice 1.

**Out of scope**: roster, archiving, notices, reading `UNIT_MAX_COUNT`, docs/README/CHANGELOG (ticket 27), the
in-game check (done with the user after commit).
