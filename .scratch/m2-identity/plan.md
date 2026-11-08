# M2 plan: ticket 26 (Retinue marks on the Status page and in Previous Hires)

Source: [issues/26-status-page-rift-marks.md](issues/26-status-page-rift-marks.md), [spec.md](spec.md) § Status (native),
[findings 0009](../../docs/findings/0009-m2-status-ui.md) P3 and P4, `tools/experiments/Retinue_Exp_StatusUI.lua` (the verified hook
bodies: `setup_pawn_post`, `name_ref_post`, `rift_item_post`, `mark_text`). Base commit: `492039a`.
(Plans of earlier tickets are in git history.)

- [x] Slice 1: pure marks + glue + wiring + tests + docs. Tier: **Sonnet** (`implementer`). Commit `34f604e`. Two review rounds: round 1 asked for availability guards in the pres (a partial install), a real nil-roster test, push-then-fill frames; round 2 APPROVE. Gap accepted: the Rift guard has no test of its own (same one-line check as the tested Status guard).
- [ ] Slice 2: in-game run, checklist 4 and 11. Tier: **Opus, inline** (driving the peer `dd2-own-pawns-ee`), then the user's look. Run 1 found two game facts (get_elements fails on TxtPawnName; setupPawn's refs are nil), fixed inline in `1abfddc` (reviewer APPROVE); run 2 passes headless. User pass open.

Cross-review: skipped (Sol and Astra unavailable on this account); Opus `reviewer` only.

Decisions:

- **Who is marked.** Status page: a roster member with status `present` whose CharaData is not the main pawn (`IsMainPawn`); the Arisen
  and the main pawn have no member Offline ID, so they never match. Previous Hires: every roster member, any status (away, returning,
  present: the list shows party pawns too, P4), matched by `ResInfo.OfflineId`.
- **Texts.** Status: the game's shown name + " · Retinue". Previous Hires: "★ " + the game's shown name + " · Lv N", N = the backup's
  level (`backups.level(id)`); no backup level -> "★ <name>". The shown text is the base (not the roster's name), as in the experiment.
- **Idempotent and self-cleaning.** Each write starts from the shown text with our own mark stripped, so a re-run never stacks a mark, a
  changed backup level replaces the old one, and a widget reused for a non-member loses a stale mark. Nothing is written when the text is
  already right.
- **Fail closed per surface.** Two hook groups (Status: 3 hooks; Rift: 1 hook), each looked up and installed all-or-nothing on its own: a
  missing type, method or field leaves that surface vanilla, shows in the mod menu and logs once. At run time an unreadable widget or
  argument writes nothing (no mark), reported once through `report` (errlog dedups).
- **Shared helpers.** `guid_str`, `to_managed` and `as_string` move from `game/talk_menu.lua` into `hooks.lua` (`hooks.guid_str`,
  `hooks.to_managed`, `hooks.as_string`); talk_menu aliases them as locals. Pure move, no behaviour change.

## Slice 1: The marks

**Goal**: opening pause > Status on a present member shows "<name> · Retinue" in the name header (both the page's `PawnInfo.TxtName` and
`CharaTab.TxtName`); the Arisen, the main pawn and non-members stay plain. The Rift's Previous Hires shows "★ <name> · Lv N" for every
roster member (N the backup's level), other entries plain. A game update that removes a hooked method or field leaves that surface
vanilla with a menu line and one log line.

**Context**: read first `tools/experiments/Retinue_Exp_StatusUI.lua` l. 985-1005 (`mark_text`), 1157-1312 (hook bodies), 1381-1405 (hook
specs: types and signatures), findings 0009 P3/P4; `src/autorun/Retinue/hooks.lua` (`install`: entry.pre(args), entry.post(retval) only, so
pre must hand `this`/the argument to post through an upvalue); `src/autorun/Retinue/game/talk_menu.lua` (the lookup pattern `type_of` /
`method_of` / `field_of` / `missing`, `guid_str`, `to_managed`, `as_string`); `labels.lua`; `roster.lua` (`find`, `PRESENT`,
`canonical_id`); `game/backup_store.lua` (`backups.level(id)`); `src/autorun/Retinue.lua` (wiring, header comment, `draw` "unavailable"
lines); `tests/talk_menu_glue_test.lua` (the fake sdk to copy); `tests/labels_test.lua`.

Game facts (dump, verified 2026-11-08):

| Type | Member |
|---|---|
| `app.ui060601_01` | F `app.GUIBase.PawnInfo2Ref PawnInfo`, F `app.GUIBase.CharaChangeRef CharaTab`, M `setupPawn(app.GUIBase.CharaData)` |
| `app.GUIBase.PawnInfo2Ref` | F `via.gui.Text TxtName`, M `setup(app.GUIBase.CharaData)` |
| `app.GUIBase.CharaChangeRef` | F `via.gui.Text TxtName`, M `updateName()`, M `get_SelectedCharaData()` |
| `app.GUIBase.CharaData` | F `app.PawnOwnerContext CopyOwner`, F `System.Boolean <IsMainPawn>k__BackingField` |
| `app.PawnOwnerContext` | F `System.Guid _OfflineID` |
| `app.ui041401.ResItem` | F `via.gui.Text[] TxtPawnName`, M `updateDisp(app.ui041401.ResInfo)` |
| `app.ui041401.ResInfo` | F `System.Guid OfflineId` |
| `via.gui.Text` | M `get_Message()`, M `set_Message(System.String)` |

Instance methods: `this` is `args[2]`, the first parameter `args[3]` (raw pointers: `hooks.to_managed`).

**Design**

`hooks.lua` gains (moved verbatim from `game/talk_menu.lua`, which then uses them as `local guid_str = hooks.guid_str` etc.):

```lua
function M.guid_str(v) end   -- System.Guid / string -> canonical lowercase string | "unreadable" | nil
function M.to_managed(a) end -- raw hook argument -> managed object | nil
function M.as_string(v) end  -- Lua or managed string -> Lua string | nil
```

`labels.lua`:

```lua
M.STATUS_MARK = " \194\183 Retinue"   -- " · Retinue"
M.RIFT_STAR = "\226\152\133 "          -- "★ "
function M.status_name(name) end       -- name .. STATUS_MARK
function M.rift_name(name, level) end  -- "★ <name> · Lv N" (num() as the other labels); level nil -> "★ <name>"
```

New pure module `src/autorun/Retinue/marks.lua`:

```lua
-- status_member(r, offline_id, is_main_pawn) -> boolean: not is_main_pawn, and roster.find(r, offline_id) has status roster.PRESENT.
--   r nil, offline_id nil/unreadable -> false.
function M.status_member(r, offline_id, is_main_pawn) end
-- rift_member(r, offline_id) -> member | nil: roster.find(r, offline_id), any status.
function M.rift_member(r, offline_id) end
-- status_text(shown, member) -> text | nil (nil = write nothing). shown nil or "" -> nil. base = shown without a trailing
--   labels.STATUS_MARK. member -> labels.status_name(base), else base. nil when the result equals shown.
function M.status_text(shown, member) end
-- rift_text(shown, member, level) -> text | nil. shown nil or "" -> nil. base = shown; if it starts with labels.RIFT_STAR, drop the
--   star and then a trailing " · Lv <digits>" if present. member -> labels.rift_name(base, level), else base. nil when equal to shown.
--   An empty base (shown was only our mark) -> nil.
function M.rift_text(shown, member, level) end
```

New glue `src/autorun/Retinue/game/marks.lua`:

```lua
-- M.new(report, deps) -> marks
--   deps = { store = game/roster_store's (reads store.roster at each call), backups = game/backup_store's (optional: no level) }
--   marks.status_available, marks.rift_available  booleans: that group's lookups passed and its hooks are installed
--   marks.missing  { string }  "<type>.<member>" not found, for the menu
function M.new(report, deps) end
```

- Lookups at `new` (pcall'd `sdk.find_type_definition`, `hooks.find_method`, `td:get_field`), per group, as talk_menu's `type_of` /
  `method_of` / `field_of`. Status group: every Status row of the table above plus `CharaData`, `PawnOwnerContext._OfflineID`,
  `via.gui.Text`'s two methods. Rift group: `ResItem`, `ResInfo`, `via.gui.Text`. A group with anything missing installs nothing; one
  `report("status marks" | "rift marks", "unavailable, not found (game update?): ...")`. The other group is unaffected.
- Hooks via `hooks.install`, one call per group. Each pre pushes `{ this, arg }` (`hooks.to_managed(args[2])`, `args[3]` where it
  exists) onto that hook's own stack; its post pops it and does the work (a stack, not one slot, so a nested call of the same method
  cannot cross wires). A post with an empty stack does nothing.
- CharaData decode: `cd:get_field("CopyOwner")` -> `owner:get_field("_OfflineID")` -> `hooks.guid_str`; `cd:get_field("<IsMainPawn>k__BackingField")`.
  `cd` nil -> write nothing at all. Owner nil / id unreadable -> not a member.
- `setupPawn` post: `cd = hooks.to_managed(arg)`; for `page.PawnInfo.TxtName` and `page.CharaTab.TxtName`: `apply(text, marks.status_text(read(text), member))`.
- `PawnInfo2Ref.setup` post: `this.TxtName`, cd from the argument. `CharaChangeRef.updateName` post: cd = `this:call("get_SelectedCharaData")`.
- `ResItem.updateDisp` post: `info = hooks.to_managed(arg)`; id = `hooks.guid_str(info:get_field("OfflineId"))`; `m = marks.rift_member(store.roster, id)`;
  level = `m and backups and backups.level(m.offline_id)`; for each `via.gui.Text` of `TxtPawnName` (get_elements, at most 6):
  `apply(text, marks.rift_text(read(text), m ~= nil, level))`.
- `read(text)` = `hooks.as_string(text:call("get_Message"))`; `apply(text, new)`: new nil -> nothing; else `text:call("set_Message", new)`.
  A nil widget or field read where one is expected -> `report("status marks" | "rift marks", "<what> unreadable")` and write nothing.
- One log line `[Retinue] marked (status|rift): <text>` the first time a given written text is seen (a seen set), so the in-game
  run can grep it without a line per refresh.
- Header comment explaining both surfaces, as the other game/ modules.

`Retinue.lua`: `local marks_glue = require("Retinue.game.marks")`; `local marks = marks_glue.new(report, { store = retinue, backups = backups })`
after `talk`; in `draw`, per `marks.missing`: `"Retinue marks unavailable: " .. name .. " not found (game update?)"`. Header comment: one
paragraph for the marks; add `marks` to the pure module list and `marks` to the game/ list.

Docs: `CHANGELOG.md` [Unreleased] Added: one line for the two marks. `spec.md` § Status (native): already matches; add "(no backup level:
"★ <name>")" to the Rift bullet. Ticket 26: append a `## Comments` line naming the slice commit (the ticket's checkboxes stay unticked
until slice 2).

**Acceptance criteria**:
- [ ] `tests/marks_test.lua`: `status_member` (present yes; away, returning, non-member, main pawn, nil roster, nil id no);
      `status_text` (marks; already marked -> nil; non-member with a stale mark -> stripped; non-member plain -> nil; nil/"" -> nil);
      `rift_text` (marks with level; level nil; level change replaces the old " · Lv N"; already right -> nil; non-member with a stale
      mark -> stripped; non-member plain -> nil; only-mark text -> nil); `rift_member` any status.
- [ ] `tests/labels_test.lua`: `status_name`, `rift_name` with and without level (an integral float prints without ".0").
- [ ] `tests/marks_glue_test.lua` (fake sdk modelled on talk_menu_glue_test): both groups install (4 hooks); a missing Status field
      installs only the Rift hook and lists the name in `missing` (and vice versa); setupPawn post marks both TxtName for a present
      member, leaves an away member, the main pawn and a non-member plain; updateName marks; a second identical call writes nothing;
      updateDisp marks a member with the backup's level, without backups -> "★ <name>", a non-member untouched; set_Message throwing ->
      reported once, no error escapes; nil CharaData -> nothing written.
- [ ] `tests/talk_menu_test.lua` and `tests/talk_menu_glue_test.lua` pass untouched after the helper move.
- [ ] Retinue.lua wiring, menu lines, header comment; CHANGELOG; spec line; ticket comment.

**Verify**: `tests/run.sh` (all PASS); `luac5.4 -p` on every changed `.lua` if available.

**Out of scope**: the talk menu's behaviour, notices, the mod menu's roster lines, any other Rift list (Hire / Favorite), marking by name
instead of Offline ID, gear.

## Slice 2: In-game run (checklist 4 and 11)

Headless, by the peer session `dd2-own-pawns-ee` (gamescope, XTEST keys): check 4 (Status page header for an adopted present member only)
and check 11 (Previous Hires mark with the backup's level after a dismiss). Then the user's look at both pages. Results go into ticket 26's
comments.
