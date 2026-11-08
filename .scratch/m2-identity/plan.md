# M2 plan: ticket 24 (Adopt and Release from the talk menu)

Source: [issues/24-talk-menu-adopt-release.md](issues/24-talk-menu-adopt-release.md), [spec.md](spec.md) § Adopt and Release (native),
[findings 0007](../../docs/findings/0007-m2-talk-ui.md) Q1–Q3. Base commit: `4c99ee5`.
(Plans of earlier tickets are in git history.)

- [x] Slice 1: pure `talk_menu.lua` and `confirm.lua`, labels, glue `game/talk_menu.lua` and `game/confirm_dialog.lua`, wiring, tests. Tier: **Sonnet** (`implementer`). Two review rounds; the round-2 findings (re-arm on a reused list, the TalkSelect check after the row) applied inline.
- [x] Slice 2: in-game run, checklist 2–4 and 7 (keys). Tier: **Opus, inline**; the user only if a step cannot be driven.
- [ ] Slice 3 (only if a run sees the confirming press leak; none on run 3 with F taps, so not built; the manual pass checks pad A and a held F): the talk-menu confirm fallback. Designed after slice 2, from what it saw.

Cross-review: skipped (Sol and Astra unavailable on this account); Opus `reviewer` only.

Facts the design rests on (findings 0007, run files `docs/findings/data/2026-11-04-m2-talkui/`):

- The root menu is an `app.ShopChoiceNode`, `_NodeId` `4c4acb4e-1531-45ea-9f6a-e4152e473e2e`, 10 `_Choices`; Dismiss `_ChoiceId`
  `7d3962d3-10ca-4c11-805e-f2df655f1f10`, Never mind `cde9623d-2e45-424a-b326-daa8c3b7078c` (the last choice, so the last shown row).
- At `ui021601.reqDisp` pre, `TalkEventManager.<CurrentTalkInfo>k__BackingField.<CurrentNode>k__BackingField` is already this node, and
  `<Speaker>k__BackingField` is the pawn's CharacterID (listener the Arisen). Every run file agrees.
- A `ListInfo` appended in `reqDisp` pre shows as a last row. Picked: at the start of `UpdateBehavior`, `TalkSelect.get_IsEndGUI()` true and
  `SelectedIndex` on it → write `SelectedIndex` = the Never-mind row → the game runs Never mind.
- `GuiManager.requestDialog` (21 args) with main text, "Yes", "No", the rest false / 0 / nil / 0.0 opens the Yes/No dialog. On the widget
  (`GuiManager.Dialog`, `app.ui010101`) `getRawRetVal()` is 0 (None) when it opens, then 1 (Yes) or 2 (No) at once on a pick; `get_IsDisp()` goes
  false a frame or two later. The values stay after a close.
- Opened from the field, the answering press also reached the character (it jumped). Inside a talk: unknown; slice 2 checks.

## Slice 1: Talk-menu row, confirm and act

**Goal**: talking to a hired party pawn shows a last row "Adopt" (adoptable, not a member) or "Release (Retinue · Lv N)" (a member in the party).
Picking it ends the talk like Never mind and opens the game's Yes/No dialog; Yes adopts or releases with the same rules as the mod menu.
A refusal (locked, read-only, unknown slot, full, or an error at Yes) shows a notice. Anything unrecognised or missing leaves the menu vanilla.

**Context**: read first `src/autorun/Retinue.lua` (wiring, the `UpdateBehavior` callback, `tick_notices`), `game/notice_screen.lua` (the pattern to copy:
resolve every name at load, `available`, pcall everything, fail safe; it also owns the shared dialog widget's reads), `game/roster_menu.lua` (the mod
menu's adopt/release and `view_by_id`), `game/roster_store.lua` (`store:adopt(view)`, `store:release(id)`, `store.found`, `store.ambiguous`,
`store.generation`, `store.unit`), `roster.lua` (`adoptable`, `find`, `canonical_id`, `ERRORS`, `error_text`, `CAP`, `LOCKED`, `READ_ONLY`), `labels.lua`,
`hooks.lua` (`find_method`, `install`, `to_u32`), `game/party.lua` (`views()`: `{ slot, character_id, owner, offline_id, name, chara }`, `level(view)`),
`tests/notice_screen_test.lua` (fake sdk style), findings 0007 Q1–Q3. The experiment `tools/experiments/Retinue_Exp_TalkUI.lua` has working code
for each game call: `guid_str` (l. 229), the `ListInfo` creation in `mutate_talk_select` (l. 610–660), the redirect `selected_index_post` (l. 680–705),
the `requestDialog` signature and argument guess (l. 46–60, 996–1000, `open_dialog` l. 1287–1335), `talk_info` (l. 415). Copy, don't import.

**Design**

`labels.lua` gains (pure; `roster.error_text` for reasons):

```lua
labels.YES, labels.NO = "Yes", "No"
labels.adopt_row()                -- "Adopt"
labels.release_row(level)         -- "Release (Retinue · Lv N)"; level nil -> "Release (Retinue)". "·" is U+00B7, as in the mod menu.
labels.ask_adopt(name)            -- "Adopt <name> into your retinue?\nGear you give them is lost if they're dismissed or lost."
labels.ask_release(name)          -- "Release <name>? Their progress will be lost."
labels.refused(action, name, err) -- "Cannot adopt <name>: <roster.error_text(err)>" / "Cannot release <name>: ..."
```

New pure `Retinue/talk_menu.lua`:

```lua
talk_menu.ROOT_NODE  = "4c4acb4e-1531-45ea-9f6a-e4152e473e2e"
talk_menu.DISMISS    = "7d3962d3-10ca-4c11-805e-f2df655f1f10"
talk_menu.NEVER_MIND = "cde9623d-2e45-424a-b326-daa8c3b7078c"
-- is_root(node_id, choice_ids) -> boolean: lowercase GUID strings. True when node_id == ROOT_NODE or choice_ids holds DISMISS,
--   and in both cases the last element of choice_ids is NEVER_MIND (the redirect needs Never mind to be the last shown row). Else false.
-- view_of(views, character_id) -> view | nil: the view with that character_id in party slot 1 or 2 (hired); nil for the main pawn, nil id.
-- row(store, view, level) -> nil | { action = "adopt"|"release", label, offline_id, name }
--   store: { roster, found, ambiguous } (roster_store's fields). view nil -> nil.
--   id = roster.canonical_id(view.offline_id). id nil -> nil. store.ambiguous[id] -> nil.
--   A member (roster.find(store.roster, id)) whose store.found[id] is this view (same character_id) -> release, label labels.release_row(level),
--     name = the member's name.
--   A member not found as this view -> nil (fail closed).
--   Otherwise roster.adoptable(view) -> adopt, label labels.adopt_row(), name = view.name or roster.UNKNOWN_NAME; else nil (online pawn).
--   A nil, locked or read-only roster still gives the row (spec: the row stays, the pick says why).
-- refusal(store, action) -> err | nil, checked before the dialog opens:
--   store.unit nil or store.roster nil -> "no_slot"; mode LOCKED -> "locked"; READ_ONLY -> "read_only";
--   action "adopt" and #store.roster.members >= roster.CAP -> "full". Else nil.
```

New pure `Retinue/confirm.lua`, the answer of one open dialog:

```lua
confirm.SHOW_SECONDS = 2
confirm.new(text, now) -> c      -- c.text, c.opened = now, c.seen = false
c:step(now, w) -> nil | "yes" | "no" | "gone" | "never_shown"
--   w: nil (unreadable) or { shown = bool, no_button = bool, text = string|nil, ret = integer|nil }, read in that callback.
--   Not seen yet: w and w.shown and not w.no_button and w.text == c.text and w.ret == 0 -> seen = true, nil.
--     Otherwise, now - opened >= SHOW_SECONDS -> "never_shown"; else nil.  (ret 0 first: a 1 or 2 left by an older dialog never answers.)
--   Seen: w nil -> nil (ask again). w.text ~= c.text -> "gone" (replaced). w.ret == 1 -> "yes"; w.ret == 2 -> "no" (read before shown:
--     the value arrives before the close). not w.shown -> "gone". Else nil.
```

New glue `game/confirm_dialog.lua` (the Yes/No on the shared dialog widget):

- `new(report)` resolves at load: `app.GuiManager` `requestDialog(System.String, System.String, System.String, System.String, System.String,
  System.Boolean, System.Int32, System.Boolean, System.UInt32, System.Int32, System.Int32, via.render.TextureResourceHolder, System.Boolean,
  System.Boolean, System.Boolean, System.Boolean, System.Boolean, System.Single, System.Boolean, System.Boolean, System.Boolean)`, `IsDispDialogGui()`,
  field `Dialog`; `app.ui010101` `get_IsDisp()`, `getRawRetVal()`, fields `IsNoButton`, `MainText`. Anything missing: `available = false`, one report line naming it.
- `ask(text) -> boolean`: false when not available or `IsDispDialogGui()` is not exactly false (a dialog is up). Else the call with
  `(text, "Yes", "No", "", "", false, 0, false, 0, 0, 0, nil, false, false, false, false, false, 0.0, false, false, false)` (managed strings for 1–5),
  under pcall; a throw is reported, `available = false`, returns false.
- `read() -> nil | { shown, no_button, text, ret }`: one pcall; any nil singleton, widget or value, or a throw -> nil. `text` through the same
  `as_string` helper as notice_screen (Lua or managed string). `ret` from `getRawRetVal()` (never `getRetVal`: it may consume).

New glue `game/talk_menu.lua`:

```lua
M.new(report, deps) -> talk
-- deps = { store = roster_store, party = party_reader, dialog = confirm_dialog, notify = function(text) }
-- talk.available, talk.missing (strings)
-- talk.tick(now)       -- from Retinue.lua's UpdateBehavior callback, first in it after life_hooks.begin_update, under its own pcall
-- talk.confirming()    -- true while a confirm is open (Retinue.lua then holds the notices)
```

- Resolution at load, all or nothing (copy notice_screen's `type_of` / `method_of` / `field_of`): `app.ui021601` `reqDisp(System.Collections.Generic.List`1<app.ui021601.ListInfo>,
  System.Boolean, via.gui.GenderType, via.gui.GenderType, System.Boolean, System.Boolean, System.Int32)`, `get_IsEndGUI()`, field `SelectedIndex`;
  type `app.ui021601.ListInfo` with fields `Msg`, `_IsDecideEnable`, `ListenerType`, `SpeakerType`, `Listener`; `app.GuiManager` field `TalkSelect`;
  `app.TalkEventManager` field `<CurrentTalkInfo>k__BackingField`; `deps.dialog.available`. Anything missing: no hook installed, one report line, `available = false`.
  The `reqDisp` hook goes through `hooks.install` with one entry (it pcalls the body).
- `reqDisp` pre (args[2] the widget, args[3] the list): first `menu = nil`. Then, any failure or nil returns leaving the list alone:
  read the talk info and its current node; `node_id` = `guid_str(_NodeId)`, `choice_ids` = `guid_str(_ChoiceId)` of each `_Choices` element (cap 16);
  `talk_menu.is_root` false -> return. The pawn: `talk_menu.view_of(party.views(), to_u32(speaker))`, else the same for the listener. `row = talk_menu.row(store, view,
  party.level(view))`; nil -> return. `count = list:get_Count()`; `count < 1` -> return. Build the `ListInfo` exactly as the experiment
  (`create_instance`, `add_ref`, `.ctor`, Listener / ListenerType / SpeakerType from entry 0, `_IsDecideEnable = true`, `Msg` a managed string of `row.label`),
  `list:Add`. Then `menu = { widget = <address of args[2] widget>, pos = count, never_mind = count - 1, row = row, generation = store.generation }`.
- `tick(now)`:
  1. A menu: read `GuiManager.TalkSelect` (`w`). `w` nil or its address ~= `menu.widget` -> keep waiting. `get_IsEndGUI()` ~= true -> keep waiting.
     `SelectedIndex` ~= `menu.pos` -> `menu = nil` (another row was picked). On it: `set_field("SelectedIndex", menu.never_mind)`, then
     read it back; not `never_mind` -> report, `menu = nil`, stop (the game's own unknown end path follows; nothing else is done). Then `menu = nil` and `pick(row, generation)`.
  2. `pick`: `store.generation ~= generation` -> nothing. `err = talk_menu.refusal(store, row.action)`; err -> `notify(labels.refused(action, name, err))`.
     Else `text = ask_adopt / ask_release(name)`; `dialog.ask(text)` true -> `pending = { c = confirm.new(text, now), row, generation }`; false -> log line `[Retinue] talk
     menu: the confirm dialog did not open` (no notice).
  3. A pending confirm: `res = pending.c:step(now, dialog.read())`. nil -> keep. `store.generation ~= pending.generation` -> drop, log. "yes" -> act.
     "no" -> nothing. "gone" / "never_shown" -> log line, nothing. Every non-nil result clears `pending`.
  4. act: adopt -> the view in `party.views()` whose `roster.canonical_id(offline_id)` is the row's id; none -> err "not_in_party"; else `store:adopt(view)`.
     release -> `store:release(id)`. An error -> `notify(labels.refused(...))`. Success: no notice (the store logs it).
- Log one line per pick and per answer: `[Retinue] talk menu: <action> <name>: <result>`.

`Retinue.lua`: require and build after `screen` and `flow` (`deps.notify` = the same `queue:push`). In the `UpdateBehavior` callback call `talk.tick(os.clock())`
under pcall (reported as "talk menu") before `flow.tick`. In `tick_notices` pass `state.in_world and not talk.confirming()` to `notices.drive` (a notice must not
replace our dialog; closing does not depend on it). Menu: when `talk.missing` is not empty, one line "Talk menu unavailable: <name> not found (game update?)" per
name, like the others. Update the header comment (one paragraph on the talk menu) and the layout lines.

**Acceptance criteria**

- [ ] `tests/talk_menu_test.lua`: `is_root` by node id, by Dismiss, false for a sub-menu, false when Never mind is not last; `view_of` skips slot 0 and unknown ids;
      `row` adopt / release (label with level, U+00B7) / nil for online pawn, ambiguous, member found as another view, nil view; locked and nil roster still give a row;
      `refusal` for each case and nil when fine.
- [ ] `tests/confirm_test.lua`: yes, no, a stale 1 before the 0 never answers, never_shown at 2 s, gone on close without an answer, gone on replaced text,
      unreadable keeps waiting, the answer read in the frame the dialog is still shown.
- [ ] `tests/labels_test.lua`: the new strings exactly.
- [ ] `tests/talk_menu_glue_test.lua` (fake sdk, like `notice_screen_test.lua`): a missing method or field installs no hook and never calls the game;
      `confirm_dialog.ask` refuses while `IsDispDialogGui` is true or nil.
- [ ] `tests/run.sh` passes; `luac5.4 -p` on every changed Lua file.

**Verify**: `tests/run.sh`; `luac5.4 -p src/autorun/Retinue.lua src/autorun/Retinue/*.lua src/autorun/Retinue/game/*.lua`.

**Out of scope**: the Retinue-full flow with an away member (ticket 25: here `full` is a refusal notice); the Status-page header (ticket 26); the talk-menu
confirm fallback (slice 3); changing the mod menu; any `nextNode` hook.

## Slice 2: In game

Backup first (`tools/saves.sh backup`). Keys, screenshots. Checklist 2–4 and 7 of `docs/testing.md` § M2: fifth row in the field and at a Rift stone, none in
Talk's sub-menu nor for a pawn outside the party; Adopt → dialog with the gear line; Yes: talk ends, `roster.json` and the backup exist, no jump, no pawn command;
No on a second try changes nothing; talking again shows "Release (Retinue · Lv N)"; Release Yes: member and backup gone, row "Adopt" again. A refusal: a
read-only roster (`"version": 2`) → the notice after the talk. Record the leak outcome (A / F press on Yes) in the ticket and in findings 0007.
