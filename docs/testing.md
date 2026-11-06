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
reached. "**Snapshot X**" means the probe's *Save snapshot* with label X.

**Ordinary** (used in checks 27–32): the pawn's level, exp, discipline and Status page equal the snapshot taken before
the step; its talk menu has the four vanilla entries (Talk / Dismiss / Add to Favorites / Never mind); Previous Hires
shows its plain name (no "★", no "Lv"); in a fight it gains exp but no level. **Playable**: the save loads, the world
is entered, a fight, a save and a reload work, the Rift hires and dismisses, and no Retinue notice or error appears.

### Setup

1. Quit the game and back up: `tools/saves.sh backup m2-checklist`.
2. `./deploy.sh --remove`, then `./deploy.sh --probe --lifecycle` (mod, probe and the lifecycle test actions: *Grant
   exp*, *Dismiss slot N*, *Force lost slot N*). No other experiment is linked.
3. Fresh state: move `reframework/data/Retinue/slots/` aside if present (keep `config.json` with progression on).
4. Fixtures (from the lifecycle and restore runs; `tools/saves.sh list` for their full names):
   `fixture-levelled-pawn` (Folken, hired at Lv 23, now Lv 27, next to a Rift stone), `fixture-2hired-at-rift`,
   `fixture-1hired-1slot-free`. Restore one with `tools/saves.sh restore <timestamp>-<label>` (game closed) where a
   check says so. The **real save** is the user's own playthrough, slot noted here: ____.
5. Nick's Devtools installed (teleport, *Kill pawns*). Note other active mods touching pawns, talk menus or exp (Guild
   Contracts hooks the same talk methods).

### Adopt and release

1. **Fresh install**: load `fixture-2hired-at-rift`. The mod menu shows `Slot N` (matching the slot loaded), an empty
   roster, no warnings; no `slots/` directory was created. In a fight neither hired pawn levels (ordinary again: M1 is
   narrowed). *Grant exp* on one: exp rises, level does not.
2. **Talk menu**: talk to a hired party pawn, in the field and at a Rift stone. A fifth row "Adopt" follows Never mind;
   Talk's sub-menu has no extra row; a pawn not in the party (Hire menu) has none.
3. **Adopt**: pick Adopt. The game's Yes/No dialog shows "Adopt <name> into your retinue?" and the gear warning line,
   **while the talk is still open**; confirming with A does not make the Arisen jump and the d-pad issues no pawn
   command. *Yes*: the talk ends like Never mind; `slots/<n>/roster.json` has the member (`present`, `character_id`)
   and `backups/<offline_id>.json` exists. *No* on a second try: nothing changes. If the press leaks, record it: the
   spec's talk-menu confirm fallback applies.
4. **Adopted status**: talking again shows "Release (Retinue · Lv N)"; the Status page header reads "<name> · Retinue"
   for that pawn only (not the Arisen, the main pawn or the other hired pawn).
5. **Progression**: in a fight (or *Grant exp*) the adopted pawn levels with its own notification; the other hired pawn
   does not. Within ~10 s of the level-up the backup file shows the new level; 30 s idle (or a fight with no kill: any exp
   gain changes the file) leaves the file's modification time alone. The log shows `in the world: yes` after the
   load and never `in the world: no (phase N)` during normal play.
6. **Toggle off**: untick progression. The adopted pawn stops levelling (exp banks), its backup still follows exp
   changes. Tick it again.
7. **Release**: pick "Release (Retinue · Lv N)" → "Release <name>? Their progress will be lost." *Yes*: the pawn stays in
   the party at its level, the row reads "Adopt" again, the member is gone and its backup file is gone or 0 bytes (log: `(backup removed)` or `(backup emptied)`;
   `(backup left in place)` is a failure), it no longer levels.
8. **Cap**: adopt both hired pawns. Mod menu lists two members. (The full-retinue flow is check 13.)
9. **Not adoptable** *(opportunistic)*: an online pawn (owner not `CAPCOM`) in the party gets no fifth row.

### Departure and Return

Restore `fixture-levelled-pawn`, adopt Folken (Lv 27), grant exp until Lv 28. Snapshot `m2-a`. Back up:
`tools/saves.sh backup m2-adopted-folken`; checks 10–17 start from it.

10. **Dismiss**: dismiss Folken at the Rift. Log line `present→away (dismiss)`; roster `away` with its
    `character_id` kept; backup unchanged since the dismiss (Lv 28).
11. **Previous Hires mark**: the Rift's Previous Hires shows "★ Folken · Lv 28" (backup's level, not the list's 23);
    other entries plain; the other party member, if adopted, is marked too.
12. **Return and restore**: re-hire Folken from Previous Hires. The notice "Folken returned — Lv 28 restored" shows
    centred and closes by itself after ~4 s. Snapshot `m2-b`: level, exp, discipline, `_IncreaseParams`, vocation exp
    equal `m2-a` (equipment differs: regenerated). Status page matches. Log `away→returning`, `returning→present
    restored Lv 23→28`. Save, reload, then full relaunch: unchanged.
13. **Retinue full**: from `m2-adopted-folken`, adopt the second hired pawn too, dismiss Folken, hire a fresh pawn into
    the free slot and pick Adopt. Dialog "Your retinue is full." with "Release Folken (away, Lv 28)" and Cancel.
    Cancel: nothing changes. Again, choose Folken → "Release Folken? Their progress will be lost." → Yes: Folken's
    member is gone, its backup gone or 0 bytes (as in check 7), the new pawn is adopted.
14. **Lost**: restore `m2-adopted-folken`. *Kill pawns* (Nick's Devtools) and leave Folken down until he leaves the
    party. Within ~3 s of leaving: log `present→away (absence)`; backup = the last poll (Lv 28). Re-hire: restored as
    in check 12. Natural lost (down timer or rest) *(opportunistic)*.
15. **Level guard**: restore `m2-adopted-folken`, dismiss Folken, quit; hand-edit his backup's level to 22 (below the
    first-hire 23), launch, re-hire. Notice "Folken returned — kept Lv 23, newer than the backup"; log `skipped: guard`;
    the backup is then overwritten by the poll with Lv 23.
16. **Return by another route** *(opportunistic)*: an away member hired from the regular Rift list or met in the world
    is restored the same way.
17. **Gear**: give Folken a piece of armour, dismiss him: the armour is gone from storage (known limit, matches the
    Adopt warning).

### Save slots and reconciliation

Use a test slot, never the real save's slot, for 21 and 22.

18. **Per slot**: adopt a pawn in slot A; load a save in slot B: the mod menu shows slot B with its own (empty) roster,
    no notice; the slot-A pawn is not adopted there. Back in slot A the member is still there.
19. **Rollback**: from `m2-adopted-folken` (Folken Lv 28), save; *Grant exp* to Lv 30, wait 10 s (backup Lv 30); load
    the earlier save. Folken stays Lv 28 (save wins); log line with both levels; backup lowered to 28.
20. **Reconciliation table**, from `m2-adopted-folken`, each with a quit, hand-edit of `roster.json` and relaunch;
    expected log line and roster after load:
    - roster `away`, same `character_id`, Folken in party → present, no restore;
    - roster `away`, `character_id` changed to another number, Folken in party at his saved level → `returning`, then
      restored under the guard (level ≤ backup: restore; notice shown);
    - roster `returning`, Folken in party → restore retried;
    - roster `present`, Folken dismissed in that save (load a save taken after a dismiss with the mod removed) → away.
21. **New game** *(opportunistic)*: in a test slot with a roster, start a New Game over it (or restart, `RedoNewGame`).
    `slots/<n>/archive-<date-time>/` holds the old roster and backups; the slot starts empty.
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
26. **Damaged backup**: `not json` in an **away** member's backup: warning for that pawn only; on its Return no restore;
    the other member works. In a **present** member's backup: warning and a note in the menu, rewritten within ~10 s
    (the game is the authority while present).

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
    (`./deploy.sh --probe --lifecycle`), load. Log: away with a different CharacterID → `returning` → restored Lv 23→28,
    notice shown. Snapshot equals `m2-a` except equipment.
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
