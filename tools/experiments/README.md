# Experiments

Throwaway scripts that **hook the game** and can change state and saves. Not part of the mod. Unlike the
read-only probe, every run needs a backup first.

## `Retinue_Exp_Hooks.lua`: does lifting the `ExpDispenser` gate level up hired pawns?

Question: if `app.ExpDispenser` stops treating hired pawns as hired, do they gain level, discipline and
vocation rank from a fight, and what does each hooked call receive?

Variants (menu: **Retinue Exp Hooks (EXPERIMENT)**; it always starts at 0, nothing is saved between sessions):

| Variant | Effect for hired pawns in the party |
|---|---|
| 0 Off | no overrides, hooks only log |
| 1 isSubPawn | `ExpDispenser.isSubPawn` returns false |
| 2 + checkLevelUp ID rewrite | also `checkLevelUp` gets the main pawn's CharacterID (and Boolean false, if ticked) |
| 3 + addJobPoint ID rewrite | also `addJobPoint` gets the same rewrite |
| 4 + notification swap-back | 3's rewrite with the Boolean left as passed; the real hired-pawn ID is put back into `dispLevelUpUI` and `GuiManager.reqJobRankUp` when they run inside a rewritten call |

Debug sliders (variant ≥ 3): **hired jobPoint x** multiplies the hired pawns' jobPoint in `addJobPoint`, **hired exp x**
their exp in `addExpAndJobPoint(id, exp, jobPoint, chara)`, to reach a rank-up or level-up in a fight or two.
Discipline, rank and levels gained this way are saved: restore the backup after the
run if you don't want to keep them. `PawnPartyCombatInfo.setLevelUp` (pawn chatter) is hooked log-only.

Baseline to compare against: in the same fight the main pawn gained +1891 exp and +479 discipline
(see `docs/findings/0001-hired-pawn-baseline.md`); hired pawns gained +1891 exp, no level, no discipline.

### Procedure

1. Quit the game. Back up, one label per run: `tools/saves.sh backup m1-variant1`.
2. `./deploy.sh --remove`, then `./deploy.sh --experiments` (add `--probe` if you also want the probe). This links
   the experiments instead of the mod: the two hook the same methods and are never linked together.
3. Launch, load the save (two hired pawns in the party), open the REFramework menu, expand
   **Retinue Exp Hooks (EXPERIMENT)**. Check the status line says all hooks are installed (if some are
   missing, note which and stop). Note which other mods touching exp or skills are active.
4. Log-only fight: variant 0, "Log calls" on. Type a label and press **Snapshot** with `before-logonly`,
   fight one enemy group, **Snapshot** `after-logonly`. Watch whether level-up or rank-up notifications
   appear, and for whom.
5. Variant 1: select it in the combo (an `auto:variant->1` snapshot is taken), Snapshot `before-v1`, fight
   one enemy group, Snapshot `after-v1`. On screen note: does a hired pawn level-up notification appear,
   under whose name, several levels at once? Watch discipline and rank in the live table.
6. Persistence: save at an inn or rest, Snapshot `pre-save`, go back to the title, reload, Snapshot
   `after-reload`. Set variant 0 and Snapshot `variant0-after-reload`.
7. Only if variant 1 falls short: restore the backup (below) or continue from the current state, then repeat
   step 5 with variant 2, then variant 3, each run with its own backup first (back to step 1).
### Variant 4 run (notification swap-back and rank-up)

Back up (`tools/saves.sh backup m1-variant4`), deploy, load. Select variant 4, set **hired jobPoint x** to 20,
Snapshot `before-v4`, fight until a hired pawn ranks up (watch Rank in the live table), Snapshot `after-v4`.
On screen note: level-up and rank-up notifications, whose name, how many times, and any odd pawn chatter. Then the
persistence step (6) as above.

8. Quit the game. Copy `reframework/data/Retinue/experiments/run_*.json` (in the game folder) into
   `docs/findings/data/<date>-<topic>/`. Then `./deploy.sh --remove`.

A forgotten script is harmless: it starts at variant 0 on the next launch.

### Rolling back

`tools/saves.sh list`, then `tools/saves.sh restore <backup>` (game closed). Restore first takes a
`pre-restore` backup of the current state, so it can be undone.

### What the run file contains

`run_<YYYYmmdd_HHMMSS>.json`, one per script session, flushed every 2 s when changed (also via **Flush log
now**):

- `variant_events`: every variant or checkbox change, with a timestamp.
- `lvup_params`: the exp curve (`Level`, `RequiredEXP`), dumped once.
- `snapshots`: `{label, time, pawns}` as the probe's fields plus `consumable_exp` and `culmative_exp`
  (whole array; JSON position = array index, the index-to-vocation mapping is not assumed).
- `calls`: one entry per hooked call: `seq`, `t` (`os.clock()`), `depth` (nesting), `method`, `id`, `tag`
  (`main`/`hired`/`other`), decoded `args`, `ctx_before`/`ctx_after` (level, exp, discipline, culmative exp,
  rank) for the progression methods, `ret` and `count` for `isSubPawn` (consecutive identical entries are
  collapsed), and `override` when a rewrite fired (original and rewritten values).
- `dropped` (entries lost after the 20000-entry cap), `errors` (caught hook errors; empty is the goal),
  `hooks` (installed and missing hooks).

## `Retinue_Exp_Lifecycle.lua`: what does the game do to a hired pawn on dismiss, lost, re-hire and save/load?

Question (M2): when a hired pawn is dismissed or lost, is its ContextDBMS record deleted (and when), what does the
Rift's dismissed list keep (`Level`: generation or current?), and when the same pawn is hired again, does it come
back with the same OfflineID and CharacterID, and in what state (level, exp, discipline, ranks, equipment, skills,
`IsRestore`)? Research and the six open questions: `docs/findings/research-m2-dismiss-lost-rehire.md` (branch
`research/m2-dismiss-lost-rehire`).

Menu: **Retinue Lifecycle (EXPERIMENT)**. Nothing is persisted between sessions.

Unlike `Retinue_Exp_Hooks.lua` this script **can run together with the mod** (`./deploy.sh --lifecycle`): its hooks
are log-only (they never change an argument or a return value) and none of them is a method the mod hooks.
The **Test actions** panel is the part that changes state: it calls `addExpAndJobPoint`, `dismissPawn` and `lost`,
so every run still needs a backup first.

### What it hooks (pre, and post where it matters)

| Group | Methods |
|---|---|
| Dismiss | `PawnManager.dismissPawn` (3 overloads; pre records the pawn's full state), `SoundVoiceManager.onDismissUnloadPawnEvent`, `NPCManager.addStrayPawn_DisMissList` (decodes the `StrayPawnFactoryDataOffline`: CharaID, OfflineID, Level, Job, name), `ItemManager.returnSubPawnItems` |
| Record and store | `ContextDBMS.deleteRecord` (2 overloads), `ContextDatabase.deleteContexts` (2), `Human.setDisableContextStoreOnDissmissPawn`, `Human.setEnableContextStoreOnHirePawn`, `ContextDBMS.restoreContextsToHolder` (2), `ContextDBMS.createNewRecordIfNotExist` |
| Lost | `PawnManager.setPawnLostTimer`, `resetPawnLostTimer` (2), `lost(CharacterID, bool, bool)` (both bools logged; pre records full state), `pawnLost` (2), `lostDeadPawns`, `lostAllPawns`, `NPCManager.eventStrayPawnLost`, `NPCManager.addStrayPawn_HireTime_DismissNotInstance` |
| Hire and re-hire | `PawnManager.hirePawn` (pre + post), `ItemManager.onHirePawn`, `StrayPawnManager.getUnusedOfflineCharacterID` (2; args and return), `StrayPawnFactoryProductOffline.restorePastInformation`, `StrayPawnFactory.preOrderFromRecord`, `StrayPawnFactory.makeRimSearchedOfflineProduct`, `PawnManager.registPawn` / `unregistPawn` |
| Rift | `FacilityManager.startRim`, `endInteractRimAction` (2 overloads) |

The status line says `all N hooks installed` or lists the missing ones. Consecutive identical entries of the chatty
hooks (`deleteContexts`, `createNewRecordIfNotExist`, `restoreContextsToHolder`, the lost-timer calls) collapse into
one with a `count`.

**Caps.** Some hooks fire thousands of times a second (the first in-game run: `restorePastInformation`, 10000 calls in
6 s), so every hook has its own cap of logged entries: 300 by default, 2000 for the hooks that matter most
(`dismissPawn` x3, `addStrayPawn_DisMissList`, `deleteRecord` x2, `lost`, `hirePawn`, `getUnusedOfflineCharacterID` x2).
The lost-group hooks (`lost`, `pawnLost` x2, the lost-timer calls) keep logging past 300 (up to 2000) while the pawn is
one seen in the party. Beyond its cap a hook only increments counters: `count_by_spec[hook] = {pre, post}` always holds
the true number of calls, so the file tells you how often each hook fires. The shared 20000-entry cap stays as a last
guard. The status line shows calls logged/dropped/seen, snapshots by class and the three most-called hooks, so
flooding is visible live.

### Snapshots

`{label, kind, time, t, seq, pawns, world}`. Taken by the **Snapshot** button (type a label first), and
automatically, a couple of frames after the event and never inside the hook: dismiss, lost, hire (post), Rift start
and end. Every test action takes one immediately (`before`) and one about 1 s later (`after`). Untick *Auto snapshots
on events* to keep only the manual and action ones. Automatic snapshots are throttled to one per kind (label) per 5 s
(`suppressed_auto_by_kind` counts the skipped ones); the lost-group ones are raised only for pawns seen in the party, not
for stray/world pawns (`lostDeadPawns` and `lostAllPawns` take no pawn and rely on the throttle). Automatic snapshots
are capped at 200 and manual + test-action ones at 200 of their own, so a manual snapshot is never lost to automatic ones.

- `pawns`: the current party plus every CharacterID/OfflineID seen since the session started (so a dismissed pawn is
  still looked up): CharacterID, OfflineID, `owner` (`capcom` when `_UserId` is all zeros, else `user`; to be confirmed),
  name, level, exp, discipline, current job, `job_ranks` (index = JobEnum 1..10), `culmative_exp` (whole array, index
  not mapped), `is_restore`, `weapons`, `equipment` (`item_ids` plus `slots`, index = position in the equip list),
  `skills`, `owner_offline_data` (the `PawnOwnerContext._OfflineData`), `record` (`by_charid` from
  `CharacterID2Keys:ContainsKey`, `by_uniqid` from `ContextDBMS.hasRecord`), `in_dismissed_list`, `source`
  (`actor`, or `record` when only the ContextDBMS record could be read, or `none`).
- `world`: `party` (CharacterIDs in slot order), `saved_party` (`_SavedPartyPawnList`), `lost_timers`
  (`_PawnLostTimers`), `lost_disabled`, `pawn_lost_time`, `dismissed_list` (`getStrayPawn_DisMissList()`: CharaID,
  OfflineID, Level, Job, name).

### Test actions

Party slot N (1-based, the live table shows who sits where). The main pawn (`ch100000_00`, 2283028347), the player and
non-hired pawns are always refused (the refusal is logged as an action with `ok = false`).

| Action | Call |
|---|---|
| Grant exp | `app.ExpDispenser.addExpAndJobPoint(CharacterID, exp, jobPoint, Character)`, defaults 10000 / 233 (as UDD2P). It goes through the mod's hooks, so a hired pawn levels. |
| Dismiss slot N | `PawnManager.dismissPawn(CharacterID)`. Two clicks: the first arms (10 s), the second runs. |
| Force lost slot N | `PawnManager.lost(CharacterID, bool1, bool2)`, the two checkboxes (default false/false). Two clicks. |

Calls are queued by the button and run in the next game update (`re.on_pre_application_entry("UpdateBehavior")`, as
the mod does), not in the UI callback; the same callback runs the deferred snapshots, the refresh and the flush. A direct call skips whatever the game's UI or death flow does
around it: use it to iterate, and do the real flow (steps b and e) at least once per checklist run.

### Procedure

Needs a save with two hired (CAPCOM) pawns in the party and a Rift stone within reach (Nick's Devtools *Warp*, or Content
Editor bookmarks). Optional but useful: the REFramework log (`re2_framework_log.txt` in the game folder).

0. Quit the game. `tools/saves.sh backup m2-lifecycle-start`.
   `./deploy.sh --remove && ./deploy.sh --probe --lifecycle`. Launch, load. Open **Retinue Lifecycle (EXPERIMENT)**:
   the status line must say all hooks are installed (if some are missing, note which). Check that Retinue is also
   active (progression on) and note other mods touching pawns, exp or items.
1. **(a) Fixture.** Pick a hired pawn. In *Test actions* set its party slot and press **Grant exp** until its level is
   past the level it was hired at (`owner_offline_data.Level` in a snapshot; the live table shows `Lv`). Fight a bit if you
   also want discipline and rank. Snapshot `a-levelled`. Rest/save at an inn, quit, then
   `tools/saves.sh backup fixture-levelled-pawn`. Other fixtures worth keeping: `fixture-2hired-at-rift` (two fresh
   hired pawns beside a Rift stone), `fixture-1hired-1slot-free`. Backups are named `<timestamp>-<label>`: restore with
   the name `tools/saves.sh list` shows (e.g. `<timestamp>-fixture-levelled-pawn`). Before each cycle below: quit,
   `tools/saves.sh backup m2-lifecycle-<step>` (so the cycle itself is undoable), then
   `tools/saves.sh restore <timestamp>-fixture-levelled-pawn`, launch, load. Each launch writes its own run file.
   **Restore wipes `reframework/data/Retinue`, run files included**: at the end of each cycle, with the game closed, copy
   its `lifecycle_*.json` to `docs/findings/data/<date>-m2-lifecycle/<step>/` (step = `b`, `c`, `d`, ...) before the
   next restore.
2. **(b) Real dismiss at a Rift stone.** Warp to a Rift stone. Snapshot `b0-before-dismiss`. Open the Rift and dismiss
   the levelled pawn through the dialogue. Wait until the pawn has walked off, then Snapshot `b1-after-dismiss` (the
   automatic `auto:rift-start`, `auto:dismiss`, `auto:rift-end` snapshots are in the file too). On screen note: item
   return messages, the farewell talk. Save (inn/rest), Snapshot `b2-saved`, go back to the title, load, Snapshot
   `b3-after-reload`. Answers: is the record gone and when (order of `deleteRecord`/`deleteContexts` against
   `dismissPawn` pre/post in `calls`; `record.by_charid` per snapshot), what `Level` the dismissed-list entry holds
   (`world.dismissed_list` and the `addStrayPawn_DisMissList` call against the pawn's level before), whether the list
   survives save and reload (`b3`). Then quit, copy the run file (see step 1), and
   `tools/saves.sh backup m2-after-dismiss`: step (c) restores that.
3. **(c) Re-hire from the Rift's dismissed list.** Restore `<timestamp>-m2-after-dismiss` (the state after (b)'s save), launch, load:
   at a Rift stone open the list of previously dismissed pawns (the "recently dismissed" tab of the search) and hire the
   same pawn. Snapshot `c1-after-rehire` once it stands next to you, and again after ~10 s. Compare against `b0`: same
   OfflineID? same CharacterID (`getUnusedOfflineCharacterID` return against the old id)? level, exp, discipline,
   ranks, equipment, skills, `is_restore`? Did `restorePastInformation`, `preOrderFromRecord`,
   `restoreContextsToHolder` fire, with which arguments? Save, reload, Snapshot `c2-after-reload`.
4. **(d) Test-action dismiss.** Quit (copy the run file), restore `<timestamp>-fixture-levelled-pawn`, launch, load. Snapshot `d0`. *Test actions*:
   slot N, **Dismiss slot N**, confirm. Wait ~10 s, Snapshot `d1`. Compare `calls` and the snapshots with (b): same
   hooks in the same order? Is the dismissed-list entry the same? What is missing (Rift events, item return)? Then
   re-hire it at a Rift as in (c) and compare.
5. **(e) Real lost.** Restore the fixture (`<timestamp>-fixture-levelled-pawn`), launch, load. Snapshot `e0`. Down the pawn with Nick's Devtools *Kill pawns*
   and record whether `setPawnLostTimer` and `lost` fire (this is what the hooks are for; the Nexus text says the pawns
   return to the Rift immediately, unverified). Snapshot `e1-killed` (note `world.lost_timers`). Then both paths:
   *timer*: let it run out or skip time (Devtools *Time & weather*), Snapshot `e2-timer`; *rest sweep*: rest at an inn or
   camp with the pawn still down (`lostDeadPawns`), Snapshot `e3-rest`. Do the two paths in separate cycles (restore
   between them) so each result is clean. Then go to a Rift: is the pawn in the dismissed list (`world.dismissed_list`,
   `in_dismissed_list`), the hire-time list, or anywhere? Are its items back in your inventory? Which Booleans did `lost`
   get (`args.b1`, `args.b2`)?
6. **(f) Test-action lost.** Restore the fixture (as in (e)). Snapshot `f0`. *Test actions*: both lost checkboxes unticked, **Force
   lost slot N**, confirm. Snapshot `f1`. Compare with (e). Repeat in a fresh cycle with `b1` ticked (and then `b2`) to
   see what the Booleans select (`PawnManager.lost` and `eventStrayPawnLost` in `calls`, whether the record survives).
7. **(g) Collect.** Quit the game. Copy the last cycle's `reframework/data/Retinue/experiments/lifecycle_*.json` (game
   folder) and the REFramework log into `docs/findings/data/<date>-m2-lifecycle/<step>/`, next to the earlier cycles'. The
   limit values for open question 6 are in `constants`. Then `./deploy.sh --remove`, and restore a backup if you do not
   want to keep the changes. Where to look in the file: `calls` filtered by `method` and `phase`, `snapshots[].pawns`
   by `character_id`/`offline_id`, `actions[].snapshot_before/after` (indices into `snapshots`).

A forgotten script is harmless to saves while you do not press a test action, but the hooks keep logging; remove it
with `./deploy.sh --remove`.

### What the run file contains

`lifecycle_<YYYYmmdd_HHMMSS>.json`, one per script session, flushed every 2 s when changed (also via **Flush log now**):

**Empty collections.** REFramework's `json.dump_file` writes an empty Lua table as `null`. The script therefore writes
`{"_empty": true}` for every empty list or table (top level, `hooks.installed`/`missing`, and inside snapshots and
entries); read it as `[]`/`{}`. Entry fields that would be empty (`args` of a hook without parameters) are left out.

**File size.** Typically 1 to 5 MB (a snapshot is about 13 KB, a call entry about 0.2 KB). Worst case with every cap hit
is roughly 10 MB compact, up to about twice that as REFramework pretty-prints it. The first run, with no per-hook caps,
wrote 21 MB.

- `summary`: `calls_logged`, `calls_dropped`, `snapshots`, `snapshots_auto`, `snapshots_manual`, `actions`, `errors`.
- `count_by_spec`: for every installed hook, `{pre, post}` = every call seen, logged or not (a hook that never fired is
  listed with zeros).
- `snapshots`: as above (automatic capped at 200, manual and action at 200; `dropped_snapshots_auto` and
  `dropped_snapshots_manual` count the rest; `suppressed_auto_by_kind` counts the throttled automatic ones).
- `calls`: one entry per hooked call phase: `seq`, `t` (`os.clock()`), `depth` (nesting of in-flight hooked calls), `method`,
  `phase` (`pre`/`post`), `id` (CharacterID), `offline_id` (when readable from the actor's `PawnOwnerContext` or from
  what was seen earlier), `name`, decoded `args`, `ret` (post), `pre_seq` (post), `state` (the pawn's full state, in the
  pre of `dismissPawn`/`lost`/`pawnLost`; `{same_as_seq}` when a nested overload of the same moment already recorded it),
  `count`/`last_seq`/`last_t` for collapsed entries.
- `actions`: one entry per test action: `kind`, `slot`, `args`, `id`, `name`, `offline_id`, `ok`, `result` or `error`,
  `seq_before`/`seq_after` (the range of `calls` it produced), `snapshot_before`/`snapshot_after` (indices into `snapshots`).
- `errors` (caught hook errors; empty is the goal), `hooks` (installed and missing), `dropped` (call entries lost after
  the shared 20000 cap or a hook's own cap; `dropped_by_spec` has the second part per hook), `constants` (`main_id`, all
  caps, `StrayPawnPastInformationMax`, `RelationPawnDismissNum`).

## `Retinue_Exp_TalkUI.lua`: how should adopt and release look and feel in the game's own UI?

Question (M2, ticket 06; probes Q1-Q4 of `docs/findings/research-m2-native-ui.md`, branch `research/m2-native-ui`):

- **Q1** What does the talk menu of a hired party pawn look like, in the field and at a Rift stone: node class
  (`PawnRentalNode` per choice, or one `ChoiceSegmentNode`), `_RentType`, each choice's `ChoiceId` / text / next node,
  the `ListInfo` entries and the pawn each one carries?
- **Q2** Can one entry be relabelled ("Adopt"), can its pick be caught in `nextNode` and redirected to "Never mind" so
  the conversation just ends, and does a fifth entry appended to the list show (with and without raising the widget's
  `DispMax`)?
- **Q3** Can the mod menu open the game's own dialog box (`GuiManager.requestDialog`) and read the answer, and which
  arguments give a Yes/No layout?
- **Q4** Does the Status page (`ui060601_01`) tell us which hired pawn a tab shows?

Menu: **Retinue Talk UI (EXPERIMENT)**. Nothing is persisted between sessions; every mutating feature is OFF at load.
It can run together with the mod (`./deploy.sh --talkui`): none of its hooks is a method the mod hooks.

### What it hooks

| Group | Methods | Behaviour |
|---|---|---|
| Talk flow (Q1/Q2) | `TalkEventPlayer.startNode`, `startPawnRentalNode`, `updatePawnRentalNode` (chatty: counted, first 5 logged), `startChoiceNode`, `nextNode(Int32)`, `checkNextCandidate(Int32)`, `newChoiceInfo` (2 overloads), `GuiManager.requestTalkSelect`, `ui021601.reqDisp` (list count and `DispMax`), `FacilityManager.startDismiss` (Rift context) | log; the Q2 toggles may edit `ListInfo.Msg`, the list passed to `requestTalkSelect`, the `nextNode` / `checkNextCandidate` index, `TalkSelect.DispMax` |
| Dialog (Q3) | `GuiManager.requestDialog` (String overload, 21 args), `ui010101.reqDisp` (24 args) | log-only |
| Status page (Q4) | `ui060601_01.setupPawn`, `setPawnData`, `partyListCtrlSelectionChangedIsPC`, `setTabId` | log-only |

The status line says `all N hooks installed` or lists the missing ones. Every hook has its own cap of logged entries
(300 by default, 1000 for the ones that matter, 5 for `updatePawnRentalNode`); beyond it only `count_by_spec` counts and
mutations still run.

### The panel

- **Marker** field and button: appends `{t, label}` to the file. Use it to say where you are ("field", "rift", "status").
- **Q1/Q2 talk menu**: the last menu as rows (`index`, list `Msg`, `_Choice`, `ChoiceId`, next node, the pawn the entry
  is about) with a **Target** radio (the row to relabel / catch) and a **Never-mind** radio (the index a redirect jumps
  to); the **Label** (default "Adopt") and the toggles: *Relabel (newChoiceInfo, by Guid)*, *Relabel (requestTalkSelect,
  by index)*, *Catch pick*, *Redirect target pick to Never-mind*, *Append fifth entry*, *Raise DispMax* (value, default 5).
  An on-screen line says `ADOPT picked for <name> <id>` when the Target is picked; nothing is adopted.
- **Q3 native dialog**: texts (main, sel0..sel3), **Open test dialog (defaults)**, **Open with captured args**
  (disabled until the game opened a yes/no dialog and the hook captured its arguments), and the live
  `getDialogState` / `getRawDialogState` / `IsDispDialogGui` / `isWaitDialogMessage` values.
- **Q4 Status page**: the current Status pawn (last `setupPawn`: id, name, hired party pawn or not) and the last
  `PawnDataList` read.

### Procedure

Needs a save with at least one hired (CAPCOM) pawn in the party and a Rift stone within reach (Nick's Devtools *Warp*).
**Back up first and expect Q2 redirect and fifth entry to be able to end a conversation oddly (or leave a choice pointing
nowhere): save before each Q2 step.**

0. Quit the game. `tools/saves.sh backup m2-talkui`. `./deploy.sh --remove && ./deploy.sh --talkui`. Launch, load, open
   **Retinue Talk UI (EXPERIMENT)**; the status line must say all hooks are installed (if some are missing, note which).
1. **Q1 (field).** Type marker `field`, press **Add marker**. Walk up to a hired party pawn and talk to it: the menu
   appears. Do not pick anything yet (press Never mind). Look at the *Q1/Q2 talk menu* node: node class, rent type, rows.
   Then **Q1 (Rift).** Marker `rift`, warp to a Rift stone, talk to the same pawn there (and open the Rift's dismiss flow
   with a spare pawn only if you want `startDismiss` logged). Note whether the menu differs.
2. **Q2.** In the talk-menu panel, after Q1 has shown the menu once: set **Target** on the "Add to Favorites" row and
   **Never-mind** on the "Never mind" row. Save. Then, one at a time and each followed by talking to the pawn again:
   a. *Relabel (newChoiceInfo)* on, talk, note whether the entry reads "Adopt". Off.
   b. *Relabel (requestTalkSelect)* on, talk, note again (which path renders?). Off.
   c. *Catch pick* on (and a relabel that worked), pick the entry: the panel shows `ADOPT picked for ...`; note what the
      game does with the pick (Favorite toggled?). Off.
   d. *Catch pick* + *Redirect* on, pick it: note what the screen shows and whether the conversation ends cleanly (like
      Never mind). Off.
   e. *Append fifth entry* on, talk: does a fifth row show? Pick it (it is redirected to Never-mind). Off.
   f. Same with *Raise DispMax* on as well (leave the value at 5; try 6 if the fifth row shows cut off). `DispMax` is
      restored when the talk select ends; the events `dispmax_raised` / `dispmax_restored` record it. Try (e) first
      without, then with Raise DispMax.
   Add a marker before each step so the file can be read per step.
3. **Q3.** Press **Open test dialog (defaults)**: note whether a dialog shows, its layout and buttons, and answer it; the
   panel and the file record every state change for 60 s. Then trigger any yes/no game dialog (e.g. Return to Title and
   cancel), so the hook captures its arguments, and press **Open with captured args**. Compare.
4. **Q4.** Marker `status`. Open pause, Status, and cycle the party tabs (a hired pawn, the main pawn, the Arisen). The
   panel's *Q4 Status page* shows the current Status pawn; the file has every `setupPawn`, `setTabId` and
   `partyListCtrlSelectionChangedIsPC` with the `PawnDataList`.
5. Quit the game. Copy `reframework/data/Retinue/experiments/talkui_*.json` (game folder) into
   `docs/findings/data/<date>-m2-talkui/`. Then `./deploy.sh --remove`, and restore the backup if you do not want to keep
   the changes.

A forgotten script is harmless: it starts with everything off on the next launch (the hooks keep logging).

### What the run file contains

`talkui_<YYYYmmdd_HHMMSS>.json`, one per script session, flushed every 2 s when changed (also via **Flush log now**).
Empty collections are written as `{"_empty": true}`.

- `markers`: `{t, wall, label}`.
- `menus`: one snapshot whenever `startNode`, `startPawnRentalNode` or `requestTalkSelect` fires: `source`, `node`
  (`class`, `NodeId`, `NodeName`, `NodeNameHash`, `NodeType`, `RentType`/`RentTypeName` for a `PawnRentalNode`, `choices`
  with `index`, `ChoiceId`, `Choice`, first `next` candidate), `talk` (speaker / listener CharacterIDs, event type), `rift`
  (`DismissStateNow`, `DismissPawnCharaId`), `disp_max` (`TalkSelect.DispMax`), `marker` (latest), and for
  `requestTalkSelect` the `list` (`Msg`, `IsDecideEnable`, listener id, level, official, slot), `pawn_id`. The
  `requestTalkSelect` snapshot is taken before any mutation.
- `calls`: one entry per hooked call phase: `seq`, `t`, `method`, `phase` (`pre`/`post`), decoded arguments, and
  `override` (original and new index) when a Q2 rewrite fired. `newChoiceInfo` post has the returned `Msg` and listener.
- `events`: `toggle`, `label`, `set_target`, `set_nevermind`, `relabel` (path, old, new), `picked`, `picked_fifth`,
  `redirect`, `redirect_skipped`, `fifth_appended`, `dispmax_raised` / `dispmax_restored`, `dialog_open`, `dialog_state`
  (every change of the four dialog values, with the elapsed time), `dialog_poll_end`.
- `captured_dialog_args`: the latest `requestDialog` the game made (strings, flags, ints, the float), `settings_now`,
  `status_page_last`, `count_by_spec`, `dropped` / `dropped_by_spec`, `errors` (empty is the goal), `hooks`, `constants`
  (including the guessed default dialog arguments).
