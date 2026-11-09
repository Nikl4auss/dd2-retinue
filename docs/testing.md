# In-game testing

## Before every test that changes game state

1. Quit the game and back up: `tools/saves.sh backup <label>` (e.g. `m1-isSubPawn-hook`).
   It copies the save folder and `reframework/data/Retinue/`, verifies the copy, and refuses to run while
   `DD2.exe` is up.
2. Note which other mods are active if they touch pawns, items, skills or experience.

Read-only probes (`tools/probe/`) need no backup. Experiments (`tools/experiments/`) hook the game and can
change saves: they DO need a backup, one per run.

To roll back: `tools/saves.sh list`, then `tools/saves.sh restore <backup>`. Restore first takes a
`pre-restore` backup of the current state, so it can itself be undone.

## Where things are

- **Saves**: the game runs through crucible-launcher, so the live folder is
  `~/.local/share/crucible-launcher/Prefix/dragon_s_dogma_2prefix/drive_c/users/Public/Documents/Steam/RUNE/2054970/remote/win64_save/`.
  `tools/saves.sh where` prints the folder it would use: the most recently written `2054970/remote/win64_save`
  across the known prefixes. An older, stale copy exists under Steam's `compatdata/2434481856/`; ignore it.
  Override with `DD2_SAVE_DIR`.
- **Backups**: `<game>/Retinue-backups/<timestamp>-<label>/` (override with `DD2_BACKUP_DIR`).
  `20261103-092435-m0-baseline` is the state before any Retinue code ran.

## Recording results

- Use the probe's *Save snapshot* at each step; snapshots land in `reframework/data/Retinue/probe/`.
- Copy them into `docs/findings/data/<date>-<topic>/` and write a findings note
  (procedure, results table, conclusions, open questions).
- Experiment runs write JSON logs to `reframework/data/Retinue/experiments/`; the procedure is in
  `tools/experiments/README.md`.
- `tools/experiments/Retinue_Exp_Lifecycle.lua` (M2) is log-only and may be linked together with the mod via
  `./deploy.sh --lifecycle`; it still needs a backup per run, because its test actions (grant exp, dismiss, lost)
  change state.

## Checklists

One section per milestone, written before its implementation starts.

## M1 — Progression

Spec: [.scratch/m1-progression/spec.md](../.scratch/m1-progression/spec.md). Record results in a findings note with
the probe's snapshots. Items marked *(opportunistic)* pass when the situation comes up during play; record each one as
passed or not reached.

### Setup

1. Quit the game and back up: `tools/saves.sh backup m1-checklist`.
2. `./deploy.sh --remove`, then `./deploy.sh --probe`. The experiment script must **not** be linked.
3. Delete `reframework/data/Retinue/config.json` if present (fresh-install state).
4. Use a save with two hired pawns in the party, at least one of them hired long enough to have banked exp.
   Note the other active mods that touch exp or skills (SimpleDifficultyTweaks multipliers, Bestiary, UDD2P,
   SkillCreator).

### Checks

1. **Menu, fresh install**: the *Retinue* section shows the checkbox ticked, no `Progression unavailable` notice,
   and `Applies to:` listing both hired pawns with level, vocation, rank and discipline. No `config.json` was created.
2. **Banked exp**: on the first fight, the long-hired pawn gains its banked levels (possibly several at once). One
   level-up notification, with its own name.
3. **Normal fight**: hired pawns gain exp and discipline (probe snapshot before and after), and level up when exp
   allows. Each notification names the right pawn, once. The main pawn's numbers move only by its own gains, and its
   own level-up notification names the main pawn.
4. **Rank-up**: a hired pawn's vocation rank goes up, and the rank-up notification shows its own name.
   *(opportunistic: needs a pawn close to its next rank)*
5. **Save → title → load right after a hired-pawn level-up**: no freeze, and level, discipline and rank are kept.
   Repeat once.
6. **Full relaunch**: quit, relaunch and load. Gains are kept and the menu state matches.
7. **Toggle off**: untick mid-session. `config.json` now exists with `"progression": false`. In the next fight hired
   pawns gain exp but no level and no discipline, and nothing gained earlier is lost. *Reset scripts*: still off.
8. **Toggle on again**: the next grant applies the exp banked while off, as in check 2.
9. **Party change**: swap a hired pawn at the Rift. The status line follows without *Reset scripts*, and the new
   pawn progresses on its next fight.
10. **Malformed config**: quit, write `not json` into `config.json`, and launch. Progression is on (default), the
    menu and the REFramework log show a `config.json` warning, and the file is unchanged until you toggle. Then put
    `{ "version": 1, "progression": "yes", "extra": 1 }`: progression is on, there is a warning for `progression` (menu and log),
    and after a toggle the file keeps `"extra": 1`.
11. **Main pawn untouched**: across all of the above, nothing about the main pawn differs from vanilla.
12. **Mod-originated grant**: UDD2P's Sphinx reward (or any mod that grants exp) levels hired pawns. This verifies
    that `sdk.hook` fires for Lua `method:call`. *(opportunistic)*
13. **Player rank-up from SkillCreator's refund**: the notification still names the player. *(opportunistic)*
14. **SimpleDifficultyTweaks multiplier ≠ 1**: the main pawn is scaled and hired pawns are not (known difference).
    *(opportunistic: only if the user changes the preset)*
15. **Uninstall**: `./deploy.sh --remove`, then launch and load. The save loads, and hired pawns keep their levels as
    ordinary hired pawns.

Afterwards: restore `m1-checklist` only if you do not want to keep the gains.

## M2 — Identity and persistence

Spec: [.scratch/m2-identity/spec.md](../.scratch/m2-identity/spec.md). Record results in a findings note with the probe's
snapshots, the roster and backup files at each step (`reframework/data/Retinue/slots/`), and the REFramework log lines
of each transition. Items marked *(opportunistic)* pass when the situation comes up; record each as passed or not
reached. "**Snapshot X**" means the lifecycle panel's *Snapshot label* X, then *Snapshot* (the probe's *Save snapshot* takes no label: where only the probe is linked, note the X and the time of the press).

**Ordinary** (used in checks 27–32): the pawn's level, exp, discipline and Status page equal the snapshot taken before
the step; its talk menu has the four vanilla entries (Talk / Dismiss / Add to Favorites / Never mind); Previous Hires
shows its plain name (no "★", no "Lv"); in a fight it gains exp but no level. **Playable**: the save loads, the world
is entered, a fight, a save and a reload work, the Rift hires and dismisses, and no Retinue notice or error appears.

### Setup

1. Quit the game and back up: `tools/saves.sh backup m2-checklist`.
2. `./deploy.sh --remove`, then `./deploy.sh --probe --lifecycle` (mod, probe and the lifecycle test actions: *Grant
   exp*, *Dismiss slot N*, *Force lost slot N*). No other experiment is linked.
3. Fresh state: move `reframework/data/Retinue/slots/` aside if present (keep `config.json` with progression on).
4. Fixtures (`tools/saves.sh list` for their full names): `fixture-levelled-pawn` (slot 2, Folken hired at Lv 23, now
   Lv 27, next to a Rift stone) and `m2-adopted-folken` (the same with Folken adopted at Lv 28 and a second hired pawn;
   for check 1, restore it and move `slots/` aside). The `fixture-2hired-at-rift` and `fixture-1hired-1slot-free` saves
   of the early runs are gone. Restore one with `tools/saves.sh restore <timestamp>-<label>` (game closed) where a
   check says so. The **real save** is the user's own playthrough, slot noted here: ____.
5. Nick's Devtools installed (teleport, *Kill pawns*). Note other active mods touching pawns, talk menus or exp (Guild
   Contracts hooks the same talk methods).

### Adopt and release

1. **Fresh install**: load `m2-adopted-folken` with `slots/` moved aside (Setup 4). The mod menu shows `Slot N` (matching the slot loaded), an empty
   roster, no warnings; no `slots/` directory was created. In a fight neither hired pawn levels (ordinary again: M1 is
   narrowed). *Grant exp* on one: exp rises, level does not.
2. **Talk menu**: talk to a hired party pawn, in the field and at a Rift stone. A row "Adopt" comes before Never mind
   (4th of 5; Never mind stays last); B in the menu puts the cursor on Never mind. Talk's sub-menu has no extra row; a
   pawn not in the party (Hire menu) has none.
3. **Adopt**: pick Adopt. There is no Yes/No dialog: the talk goes on to the Talk sub-menu, which reads "Confirm adopt" /
   Cancel (no warning line: gear waits for M4). *Confirm adopt*: back to
   the root menu, which now shows "Release (Retinue · Lv N)"; `slots/<n>/roster.json` has the member (`present`,
   `character_id`) and `backups/<offline_id>.json` exists; the Arisen does not jump and the d-pad issues no pawn command.
   *Cancel* (or any other pick) on a second try: back to the root with nothing changed. A refusal (locked, read-only,
   unknown slot, full) ends the talk like Never mind, then the notice shows.
4. **Adopted status**: Release shows on the root menu the confirm returns to, and on the next talk; the Status page
   header reads "<name> · Retinue" for that pawn only (not the Arisen, the main pawn or the other hired pawn).
5. **Progression**: in a fight (or *Grant exp*) the adopted pawn levels with its own notification; the other hired pawn
   does not. Within ~10 s of the level-up the backup file shows the new level; 30 s idle (or a fight with no kill: any exp
   gain changes the file) leaves the file's modification time alone. The log shows `in the world: yes` after the
   load and never `in the world: no (phase N)` during normal play.
6. **Toggle off**: untick progression. The adopted pawn stops levelling (exp banks), its backup still follows exp
   changes. Tick it again.
7. **Release**: pick "Release (Retinue · Lv N)" → the Talk sub-menu reads "Confirm release" /
   Cancel. *Confirm release*: back to the root, which now reads "Adopt"; the pawn stays in
   the party at its level, the member is gone and its backup file is gone or 0 bytes (log: `(backup removed)` or `(backup emptied)`;
   `(backup left in place)` is a failure), it no longer levels.
8. **Cap**: adopt both hired pawns. Mod menu lists two members. (The full-retinue flow is check 13.)
9. **Not adoptable** *(opportunistic)*: an online pawn (owner not `CAPCOM`) in the party gets no Adopt row.

### Departure and Return

Restore `fixture-levelled-pawn`, adopt Folken (Lv 27), grant exp until Lv 28. Snapshot `m2-a`. Back up:
`tools/saves.sh backup m2-adopted-folken`; checks 10–17 start from it.

10. **Dismiss**: dismiss Folken at the Rift. Log line `present→away (dismiss)`; roster `away` with its
    `character_id` kept; backup unchanged since the dismiss (Lv 28).
11. **Previous Hires mark**: the Rift's Previous Hires shows "★ Folken · Lv 28" (backup's level, not the list's 23);
    other entries plain; the other party member, if adopted, is marked too.
12. **Return and restore**: re-hire Folken from Previous Hires. The notice "Folken returned — Lv 28 restored" shows
    centred and closes by itself after 3 s. Snapshot `m2-b`: level, exp, discipline, `_IncreaseParams`, vocation exp
    equal `m2-a` (equipment differs: regenerated). Status page matches. Log `away→returning`, `returning→present
    restored Lv 23→28`. Save, reload, then full relaunch: unchanged.
13. **Retinue full**: from `m2-adopted-folken`, adopt the second hired pawn too, dismiss Folken, hire a fresh pawn into
    the free slot and pick Adopt. The Talk sub-menu opens with "Release Folken (away, Lv 28)" and Cancel (no dialog).
    Cancel: nothing changes, back at the root. Again, pick Folken: Folken's member is gone, its backup gone or 0 bytes
    (as in check 7), the new pawn is adopted, and the root shows its "Release (Retinue · Lv N)" row. No movement or
    attack on the picks (pad A and F).
14. **Lost**: restore `m2-adopted-folken`. *Kill pawns* (Nick's Devtools): the main pawn leaves too, so the log shows
    `in the world: no` and Folken stays `present`. Revive the main pawn (or travel to a Rift stone): within ~3 s of its return
    (`in the world: yes`), log `present→away (absence)`; backup = the last poll (Lv 28). Re-hire: restored as in
    check 12. Natural lost (down timer or rest) *(opportunistic)*: the main pawn stays, so away comes ~3 s after the
    pawn leaves.
    **No false absence**: from a save with Folken present, use a ferrystone, die and load the last save, then go to
    the title and load: no `absence` line in the log, `present` in the roster.
15. **Level guard**: restore `m2-adopted-folken`, dismiss Folken, save, quit; hand-edit his backup's level to 22 (below the
    first-hire 23), launch, re-hire. Notice "Folken returned — kept Lv 23, newer than the backup"; log `skipped: guard`;
    the backup is then overwritten by the poll with Lv 23.
16. **Return by another route** *(opportunistic)*: an away member hired from the regular Rift list or met in the world
    is restored the same way.
17. **Gear**: give Folken a piece of armour, dismiss him: the armour is gone from storage (known limit until M4; the
    talk menu no longer warns about it).

### Save slots and reconciliation

Use a test slot, never the real save's slot, for 21 and 22.

18. **Per slot**: adopt a pawn in slot A; load a save in slot B: the mod menu shows slot B with its own (empty) roster,
    no notice; the slot-A pawn is not adopted there. Back in slot A the member is still there.
19. **Rollback**: from `m2-adopted-folken` (Folken Lv 28), save; *Grant exp* to Lv 30, wait 10 s (backup Lv 30); load
    the earlier save. Folken stays Lv 28 (save wins); log line with both levels; backup lowered to 28.
20. **Reconciliation table**, from `m2-adopted-folken`, each with a quit, hand-edit of `roster.json` and relaunch;
    expected log line and roster after load:
    - roster `away`, same `character_id`, Folken in party → present, no restore;
    - roster `away`, Folken in party, `hire_time` removed from his backup and `character_id` changed to another number
      → `returning` (log `re-hired unseen`), then restored under the guard (level ≤ backup: restore; notice shown);
    - roster `returning`, Folken in party → restore retried;
    - roster `present`, Folken dismissed in that save (load a save taken after a dismiss with the mod removed) → away;
    - roster `present`, Folken in party, `hire_time` in his backup changed to another number (after ~15 s in the world
      with this build, so the backup has one) → `returning`, log `re-hired unseen`, restored.
21. **New game** *(opportunistic)*: in a test slot with a roster, start a New Game over it and play to its first save.
    `slots/<n>/archive-<date-time>/` holds the old roster and backups; the slot starts empty. Giving up instead: close
    the game in the prologue and load the old save: no archive, the roster and its members as before. A restart
    (`RedoNewGame`, Change Save Slot, hold Shift) archives at once.
22. **NG+** *(opportunistic)*: over a cleared test slot, the roster is kept; members not in the party become away.

### Damaged roster

23. **Locked**: quit, write `not json` into the slot's `roster.json`, launch, load. Notice once with the reason; the
    adopted pawn does not level; the talk row shows, picking it shows the reason and ends the talk; the file is
    unchanged after a fight, a dismiss and a save. Repeat with three members (over the cap). Restore the file, *Reset
    scripts*: normal again.
24. **Soft error**: `"status": "banana"` on a present member → warning, treated as away then corrected to present on
    load (save wins); `"name": 5` → "(unknown)" until refreshed.
25. **Read-only**: `"version": 2`. Notice on load; present members level; Adopt/Release refused with the reason; no file
    under `slots/<n>/` changes (roster or backups) through a fight and a dismiss.
26. **Damaged backup**: `not json` in an **away** member's backup: warning for that pawn only; on its Return no restore
    (it becomes present at the game's level, log `skipped: no backup`, and the poll rewrites the file);
    the other member works. In a **present** member's backup: warning and a note in the menu, rewritten within ~15 s of
    entering the world (3 s settle, then the poll; the game is the authority while present).

### Uninstall guarantee

Each check: back up first, take the probe snapshot **before** quitting, then `./deploy.sh --remove` and
`./deploy.sh --probe-only` (the read-only probe without the mod), relaunch and load. Compare with a snapshot after the
removal. To reinstall: quit, `./deploy.sh --remove`, `./deploy.sh --probe --lifecycle`.

27. **Present member** (real save): adopt a pawn, play until it levels, snapshot, quit, remove, relaunch, load. Playable,
    and the pawn is ordinary at its levelled state. `reframework/data/Retinue/` is untouched by `--remove`, and no
    `Retinue` script is left in `reframework/autorun/` except the probe.
28. **Away member** (`m2-adopted-folken`, Folken dismissed): remove, load. Playable; Folken in Previous Hires with a plain
    name; re-hired he comes back at Lv 23, exp 0, ordinary (known limit).
29. **Reinstall after a Return without the mod**: continue 28: save with Folken re-hired at Lv 23, quit, reinstall
    (`./deploy.sh --probe --lifecycle`), load. Log: `Folken: roster away, save has it Lv23 (backup Lv28) → returning,
    re-hired unseen`, then restored Lv 23→28, notice shown. Snapshot equals `m2-a` except equipment. Then wait 15 s in the
    world without saving, go to the title and load the same save: the log shows `re-hired unseen` again, Folken is
    restored again, and his backup is still Lv 28.
29b. **Hire time of a re-hire** *(records a fact)*: in 29, note `hire_time` in `backups/<offline_id>.json` before the
    dismiss and read the new one from the backup after the re-hire and the next poll. If the re-hire kept Folken's
    CharacterID, record whether the time changed (the pass assumes it does).
30. **Returning member**: nothing new to run. A member that is `returning` is, in the save, a re-hired pawn at its
    first-hire level: ordinary, as in 28; on reinstall its restore is retried, as in 20 (third case). Record as covered
    by 28 and 20.
31. **Released pawn**: release a member, remove the mod, load: ordinary at its level.
32. **New game while uninstalled** *(opportunistic, test slot)*: with the mod removed, start a new game over a slot with
    a roster; reinstall and load: old members are away, take the cap, and the full-retinue dialog offers to release
    them.

### Notices and other surfaces

33. A notice while a menu or a game dialog is open is deferred until it closes, and the mod never closes a game dialog.
    *(opportunistic: e.g. Return with the Rift menu still open)*
34. With Guild Contracts active, its talk options and Retinue's row coexist; no errors in the log.

Afterwards: restore `m2-checklist` if you do not want to keep the state.
