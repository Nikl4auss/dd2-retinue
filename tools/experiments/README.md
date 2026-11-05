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
  to); the **Label** (default "Adopt") and the toggles: *Relabel (newChoiceInfo, by Guid)*, *Relabel (list, by row)*, *Catch pick*, *Redirect target pick to Never-mind*, *Append fifth entry*, *Raise DispMax* (value, default 5).
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
2. **Q2.** The first run showed the party-pawn menu is an `app.ShopChoiceNode` with 10 choices of which 4 are shown,
   and the game hands the list straight to `ui021601.reqDisp` (`requestTalkSelect` is not used; `DispMax` is already 8).
   After talking to the pawn once, the *Q1/Q2 talk menu* panel lists the 4 shown entries as
   `row N [choice M] msg=...`: row = position on screen, choice = index in the node (what `nextNode` receives).
   Set **Target** on the `msg=Add to Favorites` row (row 2, choice 7) and **Never-mind** on the `msg=Never mind.` row
   (row 3, choice 9). Save. Then, one at a time, each followed by talking to the pawn again (add a marker before each):
   a. *Relabel (newChoiceInfo)* on, talk, note whether the entry reads "Adopt". Off.
   b. *Relabel (list)* on, talk, note again (which path renders?). Off.
   c. *Catch pick* on (and a relabel that worked), pick the entry: the panel shows `ADOPT picked for ...`; note what the
      game does with the pick (Favorite toggled?). Off.
   d. *Catch pick* + *Redirect* on, pick it: note what the screen shows and whether the conversation ends cleanly (like
      Never mind). Off.
   e. *Append fifth entry* on, talk: does a fifth row show? Pick it: the selected index is rewritten to the Never-mind row
      (event `fifth_selected`), so it should behave as Never mind. Off.
   f. Only if the fifth row did not show or showed cut off: same with *Raise DispMax* on as well (value 5 or more).
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

## `Retinue_Exp_Restore.lua`: can a backup be written into a re-hired pawn?

Question (M2, ticket `.scratch/m2-identity/issues/10-restore-experiment.md`): can a stored backup (level, exp, stat growth
`_IncreaseParams`, extra status boost, discipline, `CulmativeExp`) be written into a pawn just re-hired from the Rift,
matched by OfflineID on `hirePawn` post; does it stick through save, reload and a full relaunch (and with the mod and
the experiment removed); when does the pawn's ContextDBMS record become writable; is `PawnOwnerContext._OfflineID`
readable inside `hirePawn` post; and where does equipment the player gave the pawn go on dismiss and on lost?
Background: `docs/findings/0006-m2-dismiss-lost-rehire.md`, `docs/adr/0002-restore-writes-hired-pawn-contexts.md`.

Menu: **Retinue Restore (EXPERIMENT)**. It runs together with the mod and with the lifecycle script
(`./deploy.sh --restore`): it hooks none of the methods the mod hooks, and its hooks are log-only. With the default settings
it writes nothing to the game (restore mode 0, no button pressed). The run file and the **backups persist between
sessions** (the restore happens after a relaunch); the backups are the only thing this script reads back at start.

### What it hooks

| Group | Methods |
|---|---|
| Hire and dismiss | `PawnManager.hirePawn` (pre keeps the `Character`, post reads its OfflineID, level, exp and record state directly), `PawnManager.dismissPawn` (3 overloads; pre captures the backup when *Auto-capture on dismiss* is ticked and schedules `item_counts` at +1 s and +5 s) |
| Equipment destination | `ItemManager.addStorageNoLock`, `addItemToStorageNoLock`, `subStorageNoLock(Int32,Int32,CharacterID,Int32)` (item id, count, CharacterID in pre), `removeEquipData`, `returnSubPawnItems` (pre + post) |

Caps as in the lifecycle script: 300 entries per hook, 2000 for `hirePawn` and `dismissPawn`. The item hooks fire on
every pickup, so past 300 they keep logging (up to 2000) for CharacterIDs of pawns in the party or with a backup
(`known_pawn` in the entry). The status line says `all N hooks installed` or lists the missing ones. The item id / count /
CharacterID order of the three storage methods is an assumption (the dump has no parameter names): check it against
a known pickup.

### Panel

- *Settings*: **Restore mode** (0 Log only, default; 1 Auto: next frame after `hirePawn` post; 2 Auto: after 2 s),
  **IncreaseParams write** (0 fields on the existing object, default; 1 `setIncreaseParam(new object)`), *Ignore level
  guard* (off), *Auto-capture on dismiss* (on), *Log calls*. Each change is logged in `notes` (`kind: setting`).
- *Actions*: **Capture backup of slot N**, **Restore backup into slot N** (two clicks, restores the backup matching the
  slot pawn's OfflineID, refuses if none), **Compare slot N with backup** (label field), **Marker** field + button,
  **Flush now**. Slot N is a party slot; the main pawn, the player, non-hired pawns and pawns without an OfflineID are refused.
- *Backups*: one line per stored backup (name, OfflineID, level, exp, discipline, captured, source) with a two-click
  **Delete**, and **Item counts for backup N** (pick N with the slider; logs `item_counts` for that backup's item ids).
- Below: the last restore's diff (updates at after, +1 s and +10 s) and the last compare's diff (differing fields only), and
  the last calls.

### Backups

`reframework/data/Retinue/experiments/restore_backups/<offline_id>.json`, listed in `index.json` (`offline_ids`; Lua
cannot list a directory), loaded at script start. One per OfflineID; a capture overwrites the previous one. A capture is
refused (and an existing backup kept) when a restored field cannot be read.

- `version` (1), `offline_id`, `name`, `character_id`, `captured`, `source` (`button` or `dismissPawn-pre`).
- Restored: `level`, `exp`, `increase_params` {hit_point, stamina, attack, defence, magic_attack, magic_defence, blow,
  weight}, `extra_status_boost`, `discipline` (`ConsumableExp`), `culmative_exp` (whole array, JSON position = array index).
- Verification only: `current_job`, `qualified_job_bits`, `changed_job_bits`, `job_ranks` (index = JobEnum 1..10),
  `max_hp`, `max_stamina` (`calcMaxHp`/`calcMaxStamina` of `CurrentJob`), `increase_params_readonly`,
  `increase_params_caps` (the `IsCap*` flags).
- Recorded only: `item_ids` (equipped item ids; the `slots` decoding of the lifecycle script is known broken and skipped),
  `item_have_all_num` and `item_have_party_num` (`getHaveAllNum`/`getHavePartyNum` per item id, keys are strings), `skills`.

### The restore write

Update callback only, on the LIVE actor (`get_Human():get_StatusContext()` / `get_JobContext()`); the ContextDBMS record is
never written. Refused when the live level is above the backup's (unless *Ignore level guard*). Steps, each in its own
`pcall` and logged in `writes` as `{field, method, ok, error}`: `set_Level`, `set_Exp`; `_IncreaseParams` (mode 0: if
`ReadOnly` is true `setReadOnly(false)`, `set_field` on the eight int fields, then the old `ReadOnly` back; mode 1: a new
`app.IncreaseStatus` from `sdk.create_instance` + `add_ref` + `.ctor`, the eight fields, `setIncreaseParam`);
`setExtraStatusBoost` (read back from `_AcquiredExtraStatusBoost`, `set_field` fallback logged as `FALLBACK`);
`set_ConsumableExpProp` (read back from `ConsumableExp`, same fallback); `CulmativeExp` in place (length must match;
`arr:call("SetValue", sdk.create_int32(v), i)` (a no-op in game), then index assignment `arr[i] = v` (works, findings 0008),
then `set_NowJobCulmativeExpProp` / `addJobExp(job, delta)` (untested); a method counts only when reading the
array back gives the backup, the attempts are in the `writes` entry). Then `after` is read at once and `after_1s`,
`after_10s` later (the game might overwrite values); `diff` = backup against `after_10s`, field by field. Equipment, skills,
`CurrentJob` and the job bits are never written.

### Procedure

Needs the fixture `<timestamp>-fixture-levelled-pawn` from the lifecycle run (Folken Lv 27, hired at Lv 23) and a Rift stone
within reach (Nick's Devtools *Warp*). **`tools/saves.sh restore` wipes `reframework/data/Retinue`, backups and run files
included**: capture the backup in the same cycle after restoring the fixture, and copy the run files (and
`restore_backups/`) out before the next restore, into `docs/findings/data/<date>-m2-restore/<step>/`.

0. Quit the game. `tools/saves.sh backup m2-restore-start`. Restore the fixture. `./deploy.sh --remove && ./deploy.sh --probe
   --lifecycle --restore`. Launch, load. Check the status lines of both experiments say all hooks are installed, and that
   Retinue is active. Take a Status-page screenshot of the pawn (Level, HP, Stamina, Attack, Defence, ...).
1. **(a) Capture.** Before the dismiss, give the pawn a piece of equipment from the player's storage (note its name).
   **Capture backup of slot N**; check the backup list (level 27, the item id in `item_ids` once the file is flushed).
2. **(b) Real dismiss at a Rift stone.** Dismiss through the dialogue (auto-capture overwrites the backup, `source`
   `dismissPawn-pre`). Check where the given item went (storage chest, inventory) and the `item_counts` entries
   (`dismiss+1s`, `dismiss+5s`), and the item-hook entries in `calls`. Save (inn/rest), Marker `saved`.
3. **(c) Restore after re-hire.** Set Restore mode to 1. Re-hire the pawn from the Rift's "previously hired" list. In the
   run file: `calls` `hirePawn` post `offline_id_in_post` (value or error), `returns` (`hire_post`, `return_matched`,
   `reread` 1f and 1s), the `restore` action (`writes`, `before`/`after`/`after_1s`/`after_10s`, `diff`). Open the Status
   page and note Level, HP, Stamina, Attack, Defence etc., compare with the screenshot from step 0; check the vocation rank
   and discipline on the vocation screen. Marker, save, Marker `saved`; back to the title; reload; Marker `reloaded`;
   **Compare** with label `reloaded` (`auto:first-seen` fires only once per OfflineID per session). Then quit the game
   fully, relaunch, load, Compare again (`relaunch`; the auto compare fires here, the backup is loaded from file).
   `record_transitions` shows when the record became visible and `IsRestore`/`IsStore` changed.
4. **(d) Only if (c) did not stick after save/reload:** restore the post-dismiss state, re-hire with Restore mode 0, save
   once, then **Restore backup into slot N** manually, save, reload, Compare. This tells whether the record must exist before
   the write. Try IncreaseParams write 1 in a separate cycle if the Status page did not move.
5. **(e) Uninstall check.** Quit, `./deploy.sh --remove` (nothing linked: neither mod nor experiments), launch, load the save
   from (c): the pawn loads at the restored level, the Status page as restored, no errors in the REFramework log; save once and
   reload. Then redeploy (`./deploy.sh --probe --lifecycle --restore`) and Compare again.
6. **(f) Lost path for equipment.** Restore the fixture, give the pawn an item, Capture, Nick's Devtools *Kill pawns*, travel to
   a Rift, **Item counts for that backup**; note where the item went (compare `all`/`party` against `at_backup_*`, and
   `equip_now`). The lifecycle script's `lost` entries show which path fired.
7. **(g) Collect.** Quit. Copy the last cycle's `restore_*.json`, `restore_backups/` and the REFramework log into
   `docs/findings/data/<date>-m2-restore/<step>/`. `./deploy.sh --remove`, and restore a backup if you do not want to keep
   the changes.

### What the run file contains

`restore_<YYYYmmdd_HHMMSS>.json`, one per script session, flushed every 2 s when changed (also via **Flush now**). Empty
collections are written as `{"_empty": true}`.

- `summary`, `count_by_spec` (`{pre, post}` per hook), `calls` (per-hook caps, `dropped_by_spec`), `hooks`, `errors` (empty is
  the goal), `constants`.
- `calls`: `seq`, `t`, `wall`, `method`, `phase`, `id`, `name`, decoded `args`. `hirePawn` pre has `offline_id_in_pre`; its post
  has `offline_id_in_post`, `level_in_post`, `exp_in_post`, `record`. `dismissPawn` pre has `auto_capture` (what happened)
  and `item_counts_scheduled`. Item hooks: `args.item_id`, `count`, `chara_id`, plus `known_pawn` / `backup_offline_id`.
- `actions`: `capture`, `restore` (with `writes`, `before`, `after`, `after_1s`, `after_10s`, `diff_*`, `diff`),
  `delete_backup`, and refused or failed button presses (`ok: false`, `error`).
- `returns`: `hire_post`, `reread` (labels `1f`, `1s`, `2s`: CharacterID, OfflineID, level, exp, `record`, `is_restore`,
  `is_store`), `return_matched` / `return_unmatched`, `restore_waiting`.
- `compares`: `label`, `n_diff`, `all_equal`, `diff` rows `{field, expected, actual, equal}` (restored fields, verification
  fields, `item_ids`), `live`, `record`, `is_restore`, `is_store`.
- `record_transitions`: one entry per change of `by_charid`, `by_uniqid`, `is_restore`, `is_store` of a party pawn with a
  backup. `markers` `{t, wall, label}`. `item_counts`: per item id `all`, `party`, `at_backup_all`, `at_backup_party`, and
  `equip_now`. `notes`: `setting` changes and `pawn-absent` (a backed-up OfflineID never seen 30 s after the party became
  non-empty).

## `Retinue_Exp_StatusUI.lua`: where does the player see the retinue's status in game?

Question (M2, ticket `.scratch/m2-identity/issues/13-native-roster-status.md`): the player must see, without the REFramework
menu, who is adopted, who is away, a Return and its restore ("Folken returned — Lv 27 restored"), a locked / read-only roster
and a warning that gear given to an adopted pawn is lost on dismiss or lost. Which native surface should carry each? The script
only **shows candidate surfaces with sample text** so the player can judge them in game. It is purely visual: it never writes
the roster, a backup, pawn data or a save. **Not run in game yet**: every API name was checked against the dump, but none of
the new calls has been tried, and the probes that depend on guessed arguments say so below.

Menu: **Retinue Exp StatusUI**. Nothing is persisted between sessions; every toggle that changes what the player sees is OFF at
load. It can run together with the mod (`./deploy.sh --statusui`): none of its hooks is a method the mod hooks.

### What it hooks

| Group | Methods | Behaviour |
|---|---|---|
| Talk menu (P2) | `TalkEventPlayer.startNode`, `newChoiceInfo` (2 overloads), `updateChoiceNode`, `ui021601.reqDisp`, `ui021601.reqEnd` | log; with the P2 toggles `reqDisp` pre appends a fifth row to the root menu of a hired party pawn and the pick is rewritten to Never mind (the path verified in finding 0007) |
| Status page (P3) | `ui060601_01.setupPawn`, `app.GUIBase.PawnInfo2Ref.setup`, `app.GUIBase.CharaChangeRef.updateName` | log; with the P3 toggle appends a suffix to `TxtName` (page's `PawnInfo` and `CharaTab`) of a pawn whose `CopyOwner._OfflineID` is non-zero |
| Rift list (P4) | `ui041401.setupPawnList` (page, `FlowNow`, `SearchListPos` as the SearchId guess), `ui041401.ResItem.updateDisp` (one call per listed entry: name, level, OfflineId, favourite, summoned) | log; with the P4 toggle writes prefix / suffix into the entry's `TxtPawnName` texts |
| The game's own calls (P1) | `GuiManager.requestNoButtonDialog` (2 overloads), `requestDispPupUpMessage`, `requestDispSystemPopupMessage`, the three `requestHide*`, `reqLevelUp`, `setTalkBalloonMessage`, `addTalkSubtitleMessage` (10-arg) | log-only: shows what the game passes for the unknown `UInt32` / `Boolean` arguments (the flag `self_call` marks calls made by this script's buttons) |
| Message lookup (P1, lazy) | `via.gui.message.get` (1 and 2 args), `app.GUIBase.getMsg(Guid)`, `via.gui.MessageAccessData.get_Message` / `getMessage(Language)` | installed the first time *Substitute text* is ticked (they sit on the path of every piece of text, and REFramework cannot remove hooks); return the sample text only for the Guid chosen in the panel. The panel counts hits per hook: that shows which one the popup text goes through |

The status line says `all N hooks installed` or lists the missing ones; a missing method disables only its probe (the button
shows `[disabled: ...]`). Every hook has its own cap of logged entries (200, 600 for the important ones, 8 for the chatty ones).

### The panel

- Top: markers, the run file, counters, and **Sample pawn** (radio over the hired party pawns): its name and level fill `{name}` / `{lv}`
  in every text (fallback "Folken" / 27). A literal `\n` in a text is a line break.
- **P1 transient notices**
  - *B1* `requestNoButtonDialog(String, UInt32)`: buttons *show with UInt32 = 0* and *show with the UInt32 above*, `requestHideDialog`,
    and an *auto-hide* (default 10 s, 0 = never) so a dialog that sticks cannot trap you; the log says whether the dialog was still
    displayed when it was hidden.
  - *B2* popups need a message Guid. Choose the **script-owned Guid** (nothing in the game uses it), a **new random Guid**, or a
    **real game Guid** (the "Never mind." choice: it surely resolves, but while *Substitute text* is on every "Never mind." shows the sample
    text). *Substitute text* installs the lookup hooks. Buttons: `requestDispPupUpMessage(Guid, UInt32)`,
    `requestDispSystemPopupMessage(Guid, Guid[])` (params nil / an empty array), `requestHidePopUpMessage`,
    `requestHideSystemPopupMessage`, and *Probe Guid* (`message.isExistGuid` + `message.get` for the Guid, which also shows whether
    the substitution works at all).
  - *B3* `reqLevelUp(CharacterID, oldLv, newLv)` for the sample pawn (argument order from findings 0002 / 0003: `reqLevelUp(id, old,
    new)`, the reverse of `dispLevelUpUI`). Findings show it only as the notice the game raises; a **standalone call has never been
    made**, so it is not verified to leave stats alone: that is why a backup comes first.
  - *B4* a line over the sample pawn's head: `setTalkBalloonMessage(GameObject, Guid, GenderType, GenderType, Boolean, Single, UInt32,
    ..., Boolean)` with the Guid above, `GenderType.Unknown` for both genders, the editable duration and the two Booleans (meaning
    unknown), and `addTalkSubtitleMessage` (10-arg) as a second button.
- **P2 talk-menu status row**: *Row label* (default `Release (Retinue · Lv {lv})`), *Append a fifth row*, *Disabled-row label*
  (default `Adopt — retinue locked`), *Make that row disabled* (`_IsDecideEnable = false`). It acts only on the root menu of a hired
  party pawn (the `ShopChoiceNode` `_NodeId` `4c4acb4e-…`, or a Dismiss entry among the shown choices). The last such menu is listed.
- **P3 Status page mark**: *Suffix* (default ` · Retinue`), the toggle, **Arm text dump** (dumps every `via.gui.Text` of the page at the
  next tab change, the safe way) and **Dump status page now** (uses the last seen page object: press it only while the page is open).
- **P4 Rift previously hired mark**: *Prefix* (`★ `), *Suffix* (` — Retinue, Lv {lv}`, `{lv}` = the entry's level), an *OfflineID filter*
  (empty = every entry), the toggle, the same two dump buttons, and the first listed entries.
- **P5 adopt confirmation**: main text (`Adopt {name} into your retinue?\nGear you give them is lost if they're dismissed or lost.`), the
  two button texts, **open the adopt dialog**; `requestDialog` with TalkUI's verified neutral arguments, and the answer read from the
  widget (`SelYes` / `SelNo`).
- **Recent events** and the last calls.

### Procedure

Needs a save with at least one hired (CAPCOM) pawn in the party, and a Riftstone within reach (Nick's Devtools *Warp*) for P4.
**Back up first.** Nothing is expected to change state, but the talk-menu row can end a conversation oddly and none of the P1 calls
has been made before.

0. Quit the game. `tools/saves.sh backup m2-statusui`. `./deploy.sh --remove && ./deploy.sh --statusui`. Launch, load, open
   **Retinue Exp StatusUI**; the status line must say all hooks are installed (note any missing). Select the sample pawn.
1. **P1 in the field** (marker `p1`). Note for each button what appears (where on screen, how long, wording, line wrapping), and
   press the matching hide button. Watch the log for exceptions.
   a. *B1*: *show with UInt32 = 0*; then with another value (try 1, 2, 5); is a button or prompt shown, does it close by itself, does
      the hide button close it?
   b. *B2*: tick *Substitute text* with the script-owned Guid, press *Probe Guid* (is the text returned?), then
      `requestDispPupUpMessage` and both `requestDispSystemPopupMessage` buttons. If nothing shows or the text is the native one, try
      *Use real game Guid (Never mind)*, press *Probe Guid* again, and the popup again. Untick *Substitute text* afterwards.
   c. *B3*: *reqLevelUp* with 26 -> 27: does a level-up notice with the pawn's name show? Check the pawn's level in the Status page
      afterwards (it should not have changed).
   d. *B4*: with the Guid and *Substitute text* from (b), press *setTalkBalloonMessage* and *addTalkSubtitleMessage*: does a line show over
      the pawn's head, for how long, with which text?
2. **P2** (marker `p2`). Tick *Append a fifth row*, talk to a hired party pawn: is there a fifth row with the label? Pick it (the talk
   should end like Never mind). Then also tick *Make that row disabled*, talk again: is the row greyed out, can the cursor land on it, can
   it be picked? Open the pawn's Talk sub-menu: no extra row there. Untick both.
3. **P3** (marker `p3`). Pause > Status, cycle the tabs once (Arisen, main pawn, a hired pawn). Tick *Mark hired pawns*, cycle again: does only the
   hired pawn's tab show the suffix (name in the info block and in the tab header)? If not, press **Arm text dump**, change the tab, and
   the file lists every text of the page.
4. **P4** (marker `p4`). At a Riftstone open the previously hired list. Note what is logged. Tick *Mark listed pawns*, reopen / scroll the
   list: do the entries show the prefix and suffix (and does the font draw `★` and `—`)? Set the OfflineID filter to one entry's value (from
   the panel) and check only it is marked. If nothing changes, use **Arm text dump** and reopen the list.
5. **P5** (marker `p5`). From the field press **open the adopt dialog**: note wrapping and length of the two lines, answer it (the A press can
   reach the character: stand somewhere safe). Edit the text and repeat if it wraps badly.
6. Quit the game. Copy `reframework/data/Retinue/experiments/statusui_*.json` (game folder) into `docs/findings/data/<date>-m2-statusui/`. Then
   `./deploy.sh --remove`. If anything odd happened (a stuck dialog, a changed level, a broken talk), quit and restore the backup
   (`tools/saves.sh restore <backup>`, game closed).

A forgotten script is harmless: it starts with everything off on the next launch (the hooks keep logging).

### What the run file contains

`statusui_<YYYYmmdd_HHMMSS>.json`, one per script session, flushed every 2 s when changed (also via **Flush log now**). Empty
collections are written as `{"_empty": true}`.

- `markers`: `{t, wall, label}`. `party`: the cached party (id, slot, name, level, OfflineID). `hooks`, `count_by_spec`, `dropped*`,
  `errors` (empty is the goal), `probes_disabled` (methods missing in this game version), `constants`.
- `calls`: one entry per hooked call phase. Menu: `ui021601.reqDisp` pre has `root`, `node_id`, `pawn_id`, `has_dismiss`,
  `never_mind_row`, and `row_appended_at` / `row_skipped` / `row_error`. Status page: `ui060601_01.setupPawn` has the decoded `chara_data`
  (`CharaId`, `OfflineID`, `hired`, `name`), post has `names_before` and `marked`. Rift: `ui041401.setupPawnList` has `FlowNowName`,
  `SearchListPos`, `SearchId_guess`; `ResItem.updateDisp` has `entry` (name, level, OfflineId, favourite, summoned, `shown_names`), `match`,
  `marked`. `game: ...` entries are the game's own calls to the P1 methods with their decoded arguments (Single arguments travel in
  registers: read `f32` values with suspicion).
- `events`: `call` (one per button: `probe`, `args`, `ok`, `result` or `error`), `probe_unavailable`, `toggle`, `guid_set`, `text_hooks_installed`,
  `subst_hit` (which lookup hook substituted the text), `pawn_menu` (the entries of every hired-pawn menu with their Guids), `row_appended`,
  `cursor` (SelectedIndex changes while the row exists, with `on_row`), `row_picked`, `armed`, `text_dump` (summary), `dialog_*`,
  `adopt_dialog_answer`, `sample_pawn`.
- `text_dumps`: per dump `label`, `count`, `truncated` and `texts` `{path, name, message, visible}`: every `via.gui.Text` found under the
  page (fields scanned two levels deep, panels walked).
- `rift_entries`: the last seen entry per OfflineID. `status_page_last`, `rift_page_last`, `settings_now` (toggles, texts, substitution hits).

## `Retinue_Exp_SaveSlot.lua`: which save slot is loaded, and can a new game be told apart?

Question (M2, ticket `.scratch/m2-identity/issues/14-save-slot-identity-experiment.md`): the mod keeps one roster per save slot, so it
must know which of the player's three slots is loaded (it activates no roster otherwise). In the game's code the three player-visible
slots are **units** (`app.GameSystem.UnitNumber`, `UNIT_MAX_COUNT`, `SLOT_PER_UNIT`) and each unit has several internal save **slots**
(auto, add-auto, manual, back, clear); on disk that is `data000.bin`, `data00-1.bin`, `data001slot.bin` ... `data009slot.bin`. On every
load and every save the script records every value that could identify the unit and the save type, and every hook that could signal a
new game or NG+. A run answers:

1. Which value maps to the player's slot 1-3, and how the `dataNNNslot.bin` files group per unit (with the file watcher below).
2. Whether that value is stable across save types (auto / inn / manual / clear), a reload and a relaunch.
3. When during a load it is first correct (the `changes` list against `entered-world`: before the world is entered?).
4. How a **new game** over an existing unit and an **NG+** (`Clear`) can each be detected: a hook, a counter or play time that drops,
   the slot type.

It is **log-only**: it never changes an argument or a return value and calls only getters (`getLatestSaveSlot`, `getSaveSlotType`,
`getDetailContents`, ...); its only output is its run file. **Not run in game yet**: every signature was checked against the dump, but
no hook has been installed in game. Menu: **Retinue Exp SaveSlot (EXPERIMENT)**. It can run together with the mod
(`./deploy.sh --saveslot`): none of its hooks is a method the mod hooks. **Back up before every run** (`tools/saves.sh backup
<label>`): the runs load and overwrite the player's real slots.

### What it hooks

| Group | Methods | Notes |
|---|---|---|
| `app.GameSystem` | `loadGameSaveData(SaveDataBase)` (pre also reads slot-, unit-, count- and time-like fields of the argument), `saveGameSaveData()` (ret: hash and version), `loadSystemSaveData`, `saveSystemSaveData`, `setLatestSaveSlotNum`, `updateLatestSaveSlot`, `checkLatestSaveSlot` (arg and ret), `setUnitNumber`, `set_UnitNumber`, `updateUnitDataList(Int32, Boolean)`, `updateUnitDataPlayMode`, `setCleared`, `resetCleared`, `clear`, `BootConvertUnitData`, `updateSlotTimeStamp`, `updateSlotCheckCache`, `setGameClearDataMidst`, `setGameLstSave` | cap 300 each, 1000 for load / save |
| `app.SaveDataManager` | `requestLoad`, `requestLoadAuto`, `requestLoadManual`, `requestLoadSlot`, `requestSave`, `requestSaveAuto`, `requestSaveManual`, `requestSaveSlot` (the Int32 slot and the `UInt32[]`, cap 16), `loadGame`, `loadGameSaveData`, `saveGameSaveData`, `isExistSaveData(Int32)` and `getLoadingGameSlotId()` (chatty: cap 30, ret logged) | request hooks cap 1000 |
| `app.MainFlowManager` | `requestStartType` (arg and enum name), `requestLoadGameData`, `setContinueSlot`, `set_LastLoadedSlot`, `restart`, `LoadSaveDataSuccess`, `onCompleteSceneLoad`, `onPlayStartEvent`, `addContinueCount` | cap 300, 1000 for `requestStartType` |
| `app.SaveUnitSelectGUIFlowController` | `setUseUnitNo`, `resetUseUnitNo`, `onDecideUnitList` and `onExecuteGameRestart` (UnitNo, IsEmpty, IsCurrentUnit, IsRestartData, Arisen / Pawn name and level, UnitInfo), `onDecideSaveList` (SaveSlotNo, IsEmpty, IsLatestData, IsRestartData, names and levels, SlotInfo), `set_IsNewGame`, `set_SelectStartType`, `requestStartFlow`, `executeConfirm` (+ enum name), `transitFlow` (+ enum name, cap 200), `onDestroy` (counted only; forgets the remembered instance) | `this` is remembered for the snapshots (it is a component, not a singleton) |
| `app.ui030901` | `calcSaveSlotNo(SaveDataType)` (enum name and ret, cap 60) | |

The status line says `all N hooks installed` or lists the missing ones. Every pre and post entry of a hook that is not chatty carries
`state`: the cheap field reads `LatestSaveSlot`, `LatestSaveSlotArray`, `UnitNumber`, `UnitPlayCountList`, `LastLoadedSlot`, `ContinueSlot`,
`IsNewGameFlow`, `IsContinueFlow`, `CurrentProcess` as they stand just before and just after the call.

### Snapshots

A snapshot is `{label, kind, seq, t, wall, state}` (cap 400 automatic, 100 manual). `state` has the sections `gs` (`app.GameSystem`:
`LatestSaveSlot`, `LatestSaveSlotArray`, `SlotTimeStampArray`, `UnitNumber`, the per-unit lists, `getLatestSaveSlot()`,
`getLatestSaveSlotNum(unit)`, `getSaveSlotType(slot)` and `getSlotTimeStamp(slot)` for every slot, the `CachedSlot*` / `CachedExistSlot*`
values, `detail` = `getDetailContents()` with `SaveCount`, `ActualPlayingTime`, `Difficulty`, `MainPlayer`, `Memo`, and
`UnitInfoDataList`), `sdm` (`getLoadingGameSlotId()`, `CurrentProcess`, `CurrentRequest`), `mfm` (`LastLoadedSlot`, `ContinueSlot`,
`IsContinueFlow`, `IsNewGameFlow`, `ContinueCount`, `IsRestart`, `IsTitleMenuPhase`, `IsSuccessLoadSaveData`), `suc` (the last-seen unit-select
controller: `UseSaveUnitNo`, `UseSaveSlotNo`, `LatestUnitNo`, `IsNewGame`, `SelectStartType`, `CurrFlow`, `CachedExistUnitData`; dropped when a
read on it errors) and `world` (`in_world`, the party, the player's name). Arrays are lists in index order: element 1 is index 0.

| Kind (`label`) | When |
|---|---|
| `poll` (`poll-initial`, `poll-change`) | once a second the script compares a small key (`LatestSaveSlot`, `UnitNumber`, `getLatestSaveSlot()`, `getLoadingGameSlotId()`, `LastLoadedSlot`, `SaveCount`, `in_world`, `IsTitleMenuPhase`, `UnitPlayCountList`); on a change it stores a snapshot and a `changes` entry `{t, wall, from, to}` with only the changed keys. Identical consecutive states are not stored |
| `world` (`entered-world`, `left-world`) | `in_world` (the main pawn in the party and not the title menu) turns true / false; replaces the `poll-change` snapshot of that second |
| `hook` (`after:<hook key>`) | the frame after a hook fired, at most one per hook key per 2 s (`after_suppressed` counts the skipped ones); not for the chatty `isExistSaveData`, `getLoadingGameSlotId`, `calcSaveSlotNo` |
| `manual` | the **Snapshot now** button and **Add marker** (`marker:<text>`) |

### The panel

Status line (hooks, calls logged / dropped / seen, snapshots, changes, errors, flush status), a **Live state** table refreshed every second
(`UnitNumber`, `LatestSaveSlot`, `getLatestSaveSlot()` and its slot type, `getLatestSaveSlotNum` per unit, `LastLoadedSlot`,
`getLoadingGameSlotId`, `SaveCount`, `ActualPlayingTime`, `UnitPlayCountList`, `IsGameClearedList`, `in_world`, party, player), a **Marker** text
input with **Add marker**, **Snapshot now**, **Flush log now** and the last 8 `changes` lines. No button calls a game method with side effects.

### The save-file watcher

`tools/experiments/watch_saves.sh` polls the save folder once a second (the folder `tools/saves.sh where` prints, or `DD2_SAVE_DIR`) in a
second terminal and appends one line per created / changed / deleted file, plus the full listing as `initial` at start, to
`reframework/data/Retinue/experiments/savefiles_<timestamp>.log` and stdout:

```
HH:MM:SS <event> <file> size=<n> mtime=<HH:MM:SS> sha1=<first 12 hex>
```

Read-only on the save folder; Ctrl-C stops it. Match its timestamps against the run file's `wall` fields to see which `dataNNNslot.bin`
each save type writes, and whether a load rewrites any file.

### Procedure

Every step that loads, saves or starts a game gets a **Marker** first (e.g. `slot2-load-manual`), so the run file and
the watcher log can be lined up by wall time.

1. Game closed: `tools/saves.sh backup m2-saveslot`. `./deploy.sh --saveslot`. In a second terminal:
   `tools/experiments/watch_saves.sh` (leave it running the whole session).
2. Launch. At the title, before choosing anything, marker `title`. Then for each slot 1, 2, 3 that holds a playthrough:
   marker `slotN-pick`, choose it, load its latest save; once in the world marker `slotN-in-world`. Back to the title.
3. In one slot (the one played most): load each save type it offers (latest/auto, inn, manual, "start from the
   beginning" if listed), one marker per load. In the world make a manual save, rest at an inn (inn save), and let an
   autosave happen (cross an area), one marker before each. Die once and use "load last save" (marker first).
4. Quit to desktop, relaunch, load the same slot again (marker `relaunch-load`): stability across relaunch.
5. New game: game closed, `tools/saves.sh backup m2-saveslot-pre-newgame`. Start a **new game over an occupied slot**
   (markers at every confirm), play until you can save, save, back to the title. Quit, then
   `tools/saves.sh restore <the pre-newgame backup>` to get the real playthrough back.
6. NG+: only if a slot already has a cleared / NG+ save: load it and, if offered, start NG+ from it (markers). Restore
   the pre-newgame backup again after it.
7. **Flush log now**, quit, Ctrl-C the watcher. `./deploy.sh --remove` then `./deploy.sh`. The run files
   (`saveslot_*.json`, `savefiles_*.log` in `reframework/data/Retinue/experiments/`) go to
   `docs/findings/data/<date>-saveslot/`.

### What the run file contains

`saveslot_<YYYYmmdd_HHMMSS>.json`, one per script session, flushed every 2 s when changed (also via **Flush log now**). Empty collections
are written as `{"_empty": true}`.

- `constants`: the statics of `app.GameSystem` (`SAVE_SLOT_*`, `SLOT_MAX_COUNT`, `SLOT_PER_UNIT`, `UNIT_MAX_COUNT`), the unit-select
  controller's `UnitMaxCount` / `UnitPerModelCount`, `app.ui030901.SaveDataTypeCount`, and the caps.
- `snapshots`, `changes` (the poll's changed keys with times), `markers` (`{t, wall, label}`), `last_state` (the newest poll).
- `calls`: one entry per hooked call phase (`method`, `phase`, `args`, `ret`, `state`, `pre_seq` on post).
- `hooks` (installed / missing), `count_by_spec` (every call seen), `dropped*`, `self_calls` (hooks fired by the script's own getters, not
  logged), `after_suppressed`, `snapshots_dropped`, `summary`, `errors` (empty is the goal).
