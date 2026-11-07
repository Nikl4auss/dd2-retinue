# M2 — Identity and persistence (spec)

Status: ready for `/to-tickets` · Map: [map.md](map.md) · In-game checklist: [docs/testing.md § M2](../../docs/testing.md#m2--identity-and-persistence) · Glossary: [CONTEXT.md](../../CONTEXT.md)

## Goal

The player builds a **retinue**: up to two hired pawns they **adopt**, which progress like the main pawn (M1) and keep
that progress across dismiss, lost and re-hire. The game keeps no progress past dismiss: a returning pawn comes back
from the Rift at its first-hire level, exp 0 ([findings 0006](../../docs/findings/0006-m2-dismiss-lost-rehire.md)). So
the mod keeps a **backup** of each adopted pawn and **restores** it on its **Return**
([ADR 0002](../../docs/adr/0002-restore-writes-hired-pawn-contexts.md)). Everything the player needs is done in the
game itself (native first); the REFramework menu is a development convenience and a fallback. Adopted pawns stay
ordinary hired pawns in the save ([ADR 0001](../../docs/adr/0001-runtime-lift-not-save-injection.md)), so removing the
mod leaves every save playable (the **uninstall guarantee**).

## Scope

In:

- The roster per save slot: file format, validation, locked and read-only states.
- Adopt and Release from the hired party pawn's talk menu, confirmed by the game's own dialog; the "retinue full" flow.
- Departure (dismiss, lost, any other) and Return, by any route; the `returning` state and its retries.
- Backups: contents, when written, restore on Return under the level guard.
- Save-slot identity, new game / NG+, reconciliation of the roster with the loaded save.
- Native status: talk row, Status page header, Rift Previous Hires marks, transient notices, gear warning.
- M1 narrowed: only present adopted pawns progress.
- The mod menu mirroring all of the above.

Out (see the map's Out of scope): online pawns (owner with `_UserId`); the main pawn, never altered; spending
discipline, vocation change, augments (M3); a roster larger than the party; restoring equipment or skills; localized
texts; the 0.1.0 tag and release.

## Terms

As in `CONTEXT.md`: hired pawn, adopted pawn (present / away / returning), roster, locked roster, read-only roster,
adopt, Return, release, backup, restore, save slot, party slot, CharacterID, Offline ID, uninstall guarantee. Below,
**member** is an entry of the active roster, **in the world** means the main pawn is present and
`MainFlowManager.get_IsTitleMenuPhase()` is false and no load is in progress.

## Behaviour

### Identity

From [What identifies an adopted pawn across dismiss and re-hire?](issues/07-identity-key.md):

- A member is identified by `PawnOwnerContext._OfflineID` alone, canonical lowercase GUID string.
- **Adoptable**: a hired pawn in party slot 1 or 2 whose owner is `CAPCOM` with a non-nil, non-zero `_OfflineID`.
  Anything else is refused with reason `no_offline_id`. No surrogate key is ever invented.
- **CharacterID** is a cache: where the member is in this save. It is never used to find or identify a pawn. It is
  refreshed on load, on every party change and on Return. An **away member keeps its last CharacterID** (revised by
  the uninstall-guarantee ticket); it is only compared on load, and only when the hire time is unknown (see
  Reconciliation).
- **Ambiguous**: two party pawns with one member's OfflineID. The member gets no progression, no restore and no
  transition; one warning. Never guess.
- `name` is stored for display and refreshed while present.

### Save slot

From [Which save slot is loaded…?](issues/14-save-slot-identity-experiment.md) and
[findings 0010](../../docs/findings/0010-m2-save-slot-identity.md):

- The save slot is the game's unit (0–2). Its directory is `slots/<unit + 1>/` (1–3, as the player sees them).
- `SLOT_PER_UNIT` is read from `app.GameSystem`'s static at runtime, never hard-coded.
- Session state **loaded unit**, set before the world is entered:
  - `MainFlowManager.requestLoadGameData(Int32)` pre: unit = arg ÷ `SLOT_PER_UNIT` (every load);
  - `MainFlowManager.requestStartType(StartType)` pre with `NewGame`: unit = `GameSystem.UnitNumber` at that moment.
  - **Fallback** when neither was seen this session: in the world, `LastLoadedSlot ÷ SLOT_PER_UNIT` only if it
    equals `UnitNumber`; otherwise the slot is **unknown**.
- **Unknown slot**: no roster is active this session. Adopted pawns behave as ordinary hired pawns, nothing is
  written, Adopt/Release answer with the reason, a notice once on load.
- **New playthrough** (`requestStartType` with `NewGame` or `RedoNewGame`): if the unit has a roster, its directory
  contents (roster and backups) move to `slots/<n>/archive-<yyyymmdd-hhmmss>/`, never deleted, and the unit starts
  with an empty roster. Done from the update loop right after the hook, never inside it.
- **NG+** (`RedoNewGameSkip`): same playthrough, roster kept; members not in the party become away by the general rule.
- Any other `StartType`: a load within the playthrough.
- Switching units in one session (title → another start) activates the new unit's roster and cancels the previous
  one's pending work (returning retries, diff counters) without writing to it.
- `config.json` stays global. Orphan slot directories are ignored, never deleted.

### Roster file

From [What is the shape of the roster file…?](issues/08-roster-file-format.md), made per slot by
[How does the mod reconcile the roster…?](issues/12-roster-save-drift.md):

Path `reframework/data/Retinue/slots/<n>/roster.json`:

```json
{ "version": 1,
  "members": [
    { "offline_id": "426f7888-0cc8-44a4-86b2-1ed445367596", "name": "Folken", "status": "present", "character_id": 1601809365 },
    { "offline_id": "89658ac1-…", "name": "Diamonds", "status": "away", "character_id": 743846891 } ] }
```

- `members` in adoption order. `status`: `"present"` | `"away"` | `"returning"`. `character_id` optional (a member
  never seen in this save has none). `name` display only. The cap, **2**, is one constant (`roster.lua`).
- **Missing file**: empty roster; the file is created on the first adopt.
- **Structural error → locked**: unparseable JSON, non-object top level, `members` not an array, a member without a
  valid `offline_id`, duplicate `offline_id`s, more members than the cap. Locked: no progression for anyone, no
  transitions, no backups written, Adopt/Release answer with the reason, a notice on load and a warning in the menu and
  log, and the file is never rewritten. Fixed by hand and *Reset scripts*.
- **Soft error → corrected per field** with a warning: bad `name` → "(unknown)"; bad `character_id` → no cache; bad
  `status` → away.
- **`version` > 1 → read-only**: members valid as v1 progress; nothing is written (roster or backups), so no restore;
  Adopt/Release answer with the reason; reconciliation in memory only; notice on load.
- Unknown keys are kept on rewrite, top level and per member (same `null` / `{}` caveat as `config.lua`).
- Read when a unit becomes active; written immediately on every change (adopt, release, transitions, cache refresh).
  No atomic write, no `re.on_config_save`.

### Backups

From [What does a pawn's backup hold, and when is it written?](issues/09-backup-contents-and-timing.md) and
[findings 0008](../../docs/findings/0008-m2-restore.md):

Path `slots/<n>/backups/<offline_id>.json`, own `version: 1`. One file per member.

- **Restored fields**: `HumanStatusContext` `_Level`, `_Exp`, `_IncreaseParams` (all eight: `_HitPoint`, `_Stamina`,
  `_Attack`, `_Defence`, `_MagicAttack`, `_MagicDefence`, `_Blow`, `_Weight`), `_AcquiredExtraStatusBoost`;
  `JobContext` `ConsumableExp` (discipline) and the whole `CulmativeExp` array.
- **Recorded, never restored**: `CurrentJob`, `QualifiedJobBits`, `ChangedJobBits` (verification), equipped item IDs
  (display, log), equipped skills per vocation (compared on Return, a mismatch logged; kept for M3), and the **hire
  time** (`SubPawnDataContext._HireTime`, integer milliseconds so the file verifies with `==`), which marks one hire
  (see Reconciliation), and **`restored_from`**, the game's level the last restore started from (a save at or below it
  predates that restore; see Reconciliation).
- **Display**: name, current vocation, level.
- **Written**: on adopt; by a **poll every ~10 s** while present and in the world, only if a value changed; a forced read
  at `PawnManager.dismissPawn` pre. **Frozen** while away or returning: nothing writes it.
- A missing or damaged backup affects only its pawn (no restore, warning); it never locks the roster.
- Release empties the file (REFramework has no working file delete, verified in ticket 18: `os.remove` is tried first; an
  empty file reads as missing). Orphan
  backups are ignored, never deleted.
- **Save wins** within a slot: a present member below its backup (a rollback) keeps the save's state; the poll lowers
  the backup; one warning with both levels. No `.prev` copy.

### Departure and Return

From [How does the mod notice a member leaving and returning…?](issues/11-departure-and-return-flow.md):

- **Dismiss**: `dismissPawn` pre forces the last backup read; `dismissPawn` post marks the member away (roster written)
  only if the pawn is really gone from the party. The CharacterID is kept.
- **Any other departure** (lost, unknown): a **party diff** every ~1 s, only in the world, compares the OfflineIDs in
  party slots 1–2 with the present members; a present member missing for **3 consecutive checks** becomes away. The
  last backup is the last poll: up to ~10 s of progress can be lost (known limit, documented).
- A hire of a member still marked present means it left unseen (a pawn in the party cannot be hired): away with cause `hire`, then a normal Return.
- **Return**: `PawnManager.hirePawn` post where the hired pawn's OfflineID is an away member's → `returning` (roster
  written, backup frozen). Any route counts (Previous Hires, the regular list, a pawn met in the world).
- **Restore**: one frame after `hirePawn` post, retried every frame for up to ~10 s while the actor or contexts are not
  ready. Writes as in findings 0008: `set_Level`, `set_Exp`, `set_field` on the existing `_IncreaseParams` object,
  `setExtraStatusBoost`, `set_ConsumableExpProp`, `CulmativeExp` by 0-based index assignment, then read back every
  field. Success → present, CharacterID cache set, the poll mirrors the game again. Timeout or read-back mismatch →
  stays `returning`, warning, retried on the next load. A Return with no usable backup becomes present with a warning;
  the poll then rewrites the file. A dismiss while `returning` → away, backup untouched.
- **Level guard**: restore when the game's level ≤ the backup's (equal level still restores exp, discipline, vocation
  exp); when greater, skip with a warning, become present, and the game wins.
- Transitions and backups run **regardless of the `progression` toggle**. Locked: nothing tracked. Read-only: nothing
  written, no restore. Ambiguous member: excluded.
- One log line per transition (`log.error`, like the rest of the mod): present→away with the cause, away→returning,
  returning→present with "restored Lv a→b" or "skipped: guard", retry timeout.

### Reconciliation on load

From the drift ticket and the uninstall-guarantee ticket. **One pass per load**, on entering the world, before the party
diff, the poll and the restore attempts act; matching by OfflineID. "Rehired" is the test below.

| Roster says | Loaded party | Rehired | Result |
|---|---|---|---|
| present | in party | no | nothing; the poll lowers the backup if the save is lower (save wins) |
| present | in party | yes | `returning` (a Return the mod did not see; the poll never lowers the backup) |
| present | absent | | away, last backup kept (save from before the adopt, or dismissed with the mod off) |
| away | in party | no | present, no restore (rollback to before the departure; save wins) |
| away | in party | yes | `returning` → restore under the level guard (a Return the mod did not see) |
| away | absent | | away |
| returning | in party | | nothing; `flow.tick` retries the restore under the level guard |
| returning | absent | | away, backup untouched (save from before the re-hire) |

- **The discriminator is the hire time**, kept in the backup (recorded, never restored, frozen while away): a different
  hire time than the backup's means the pawn was hired again since, an equal one means the same hire (but see the floor
  below). Not "later": a
  false Return only gives a pawn its backup back, while a false rollback lowers the backup for good, so a rollback to
  before an earlier Return restores the backup, the one case that departs from "save wins". The hire time is the save's
  clock, so it rolls back with the save.
- **Equal hire times with a floor**: after an unseen Return the restore writes the new hire time onto a backup that holds
  restored progress, while the disk save still has that hire at first-hire level until the next game save. So the backup
  records `restored_from`, the game's level the last restore started from, and on equal times a save at or below it and
  behind the backup (lower level, or equal level with less exp) is a re-hire too (restored again). Without a floor the first-hire signature below decides
  (exp 0, discipline 0 and behind the backup).
- **Fallback when either hire time is unknown** (a backup written before it was recorded, an unreadable context): the
  CharacterID as kept. A different one is a re-hire; none kept is a re-hire for an away or returning member and nothing
  for a present one; the same one is a re-hire only in the first-hire state: exp 0, discipline 0 and behind the backup
  (lower level, or the same level with backup exp or discipline above 0).
- **Gate**: the pass runs once per generation, after the game has left the world since the generation changed (or after
  a 20 s grace, so a start request that never leaves the world cannot hold the session), and after 3 s in the world with
  a complete party read. While it is pending the hook events wait, and the party diff, the restore attempts, the backup
  poll and the cache refresh hold (the refresh would overwrite the kept CharacterID the fallback compares).
- A member with a dismiss queued behind the gate is left to the dismiss: it applies after the pass and logs its own
  cause. Its snapshot is dropped: it may be a save that predates a restore, and storing it would lower the backup.
- A member whose pawn read fails does not hold the pass: its level, exp and hire time count as unknown, and the failure
  is reported. With the CharacterID it kept it gets no correction: nothing proves a rollback or a re-hire, and a false
  rollback lowers the backup. Ambiguous members get no correction.
- One log line per correction, e.g. `Rook: roster away, save has it Lv20 (backup Lv27) → present, save wins`, and one
  roster write per pass.
- Read-only roster: the pass runs in memory only. Locked: no pass. Unknown slot: no roster. The gate opens either way.

### Progression (M1 narrowed)

`targets.is_target` is replaced: a target is a party pawn whose OfflineID is a **present**, non-ambiguous member of the
active roster (locked → none; read-only → its valid present members; unknown slot → none). Returning and away members
are never targets. Ordinary hired pawns are vanilla again. The M1 `progression` toggle stays a global switch with M1's
semantics; everything else in M1 (hooks, swap-back, failure handling) is unchanged.

### Adopt and Release (native)

From [How should adopt and release look and feel?](issues/06-adopt-release-ux.md),
[findings 0007](../../docs/findings/0007-m2-talk-ui.md) and [0009](../../docs/findings/0009-m2-status-ui.md):

- **Fifth row** in the talk menu of a hired party pawn: only on the root `app.ShopChoiceNode` recognised by `_NodeId`
  `4c4acb4e-1531-45ea-9f6a-e4152e473e2e` or by the presence of the Dismiss choice (`7d3962d3…`); never in sub-menus,
  never for a pawn outside the party. A new `ui021601.ListInfo` (`_IsDecideEnable = true`) appended in
  `ui021601.reqDisp` pre. **Fail closed**: an unrecognised node leaves the menu vanilla.
- Labels: "Adopt" for an adoptable pawn; "Release (Retinue · Lv N)" for a present member. Rows for non-adoptable pawns
  (online, no OfflineID) are not added.
- **Picking it**: when `ui021601.get_IsEndGUI()` is true with `SelectedIndex` on the appended row, `SelectedIndex` is
  rewritten to the Never-mind row before the game maps it (start of `UpdateBehavior`), so the talk ends like Never mind.
- **Confirmation**: the game's dialog, `GuiManager.requestDialog` with Yes/No, opened **before the talk ends**; the
  answer read from the widget (`ui010101` `Ret` / `getRawRetVal()`: 1 Yes, 2 No).
  - Adopt: "Adopt <name> into your retinue?\nGear you give them is lost if they're dismissed or lost."
  - Release: "Release <name>? Their progress will be lost."
  - **Fallback**, if the dialog leaks input inside a talk (verified first, see Open assumptions): confirm in the talk
    menu, re-shown with "Confirm adopt" / "Confirm release" and Never mind.
- **Adopt** (Yes): roster add (status present, cache set), first backup written, notice-free (the row label changes on
  the next talk). Errors `full`, `already_adopted`, `locked`, `read_only`, `no_slot`, `no_offline_id` → notice with the
  reason, talk ends like Never mind.
- **Retinue full** (an away member holds a place and a new hired pawn fills its party slot): picking Adopt opens a
  dialog "Your retinue is full." with one button per away member, "Release <name> (away, Lv N)" (backup's level), and
  Cancel; choosing one asks "Release <name>? Their progress will be lost." (Yes/No); Yes releases it (backup deleted)
  and adopts the current pawn.
- **Release** (Yes): roster remove (unknown keys go with it), backup deleted, the pawn stays in the party as an
  ordinary hired pawn at its level and stops progressing.
- Locked, read-only or unknown slot: the row stays, picking it shows the reason in a notice and ends the talk.

### Status (native)

From [Where does the player see the retinue's status in game?](issues/13-native-roster-status.md):

- **Status page**: the name header reads "<name> · Retinue" for a present member (after `ui060601_01.setupPawn`,
  writing `PawnInfo2Ref.TxtName` / `CharaChangeRef.TxtName`). Never for the Arisen or the main pawn.
- **Rift Previous Hires**: in `ui041401.ResItem.updateDisp(ResInfo)`, an entry whose `ResInfo.OfflineId` is a member
  shows "★ <name> · Lv N" in `TxtPawnName`, N the **backup's** level. Ordinary pawns unmarked.
- **Notices** through `GuiManager.requestNoButtonDialog(String, UInt32)`, centred, closed by the mod after ~4 s with
  `requestHideDialog()`:
  - "<name> returned — Lv N restored"; on a guard skip "<name> returned — kept Lv M, newer than the backup";
  - locked / read-only / unknown slot: once per load, with the reason; Adopt/Release refusals.
  - The mod closes only a notice it opened that is still the one displayed, and defers a notice while a game dialog or
    menu is up.
- All widget fields can change with a patch: **fail closed** (no mark, menu vanilla, error logged once).
- All texts are literal English strings.

### Mod menu (dev and fallback)

The *Retinue* tree node gains, below M1's checkbox and status line:

- the active slot (`Slot 2`, `Slot unknown`) and the roster state (ok / locked: reason / read-only);
- one line per member: name, status, level (game's if present, backup's otherwise), and any warning (ambiguous, no
  backup, returning retries);
- per party pawn an **Adopt** / **Release** button with an inline confirm (imgui), same rules and errors as the native
  path; per away member a **Release** button.

### Uninstall guarantee

From [How is the uninstall guarantee verified…?](issues/15-uninstall-guarantee-check.md):

- Removing Retinue (game closed) leaves every save **playable** and every pawn **ordinary**: a present member keeps its
  level and progress; an away member returns at its first-hire level (its progress survives only in its backup);
  `returning` and released pawns are already ordinary.
- `reframework/data/Retinue/` is never deleted by the mod or `deploy.sh --remove`. The README says deleting it by hand
  is the clean uninstall and discards away members' backups.
- On reinstall the reconciliation table above applies; a Return made without the mod is restored.
- No "prepare for uninstall" action.

## Code layout and tests

Pure modules (no REFramework globals) in `src/autorun/Retinue/`, each with a `tests/<name>_test.lua`:

- `roster.lua`: `resolve` / `merge` (validation, locked, read-only, soft corrections, unknown keys) and operations
  `adopt`, `release`, `mark_away`, `mark_returning`, `mark_present`, `refresh_cache`, returning errors `full`,
  `already_adopted`, `locked`, `read_only`, `no_offline_id`; the cap constant.
- `backup.lua`: serialise / validate, "changed?" comparison, level guard decision.
- `slot.lua`: unit from a global slot and `SLOT_PER_UNIT`, `StartType` classification (new playthrough / NG+ / load),
  fallback rule, directory and archive names.
- `reconcile.lua`: the reconciliation table as a pure function (roster, the loaded party `{ [offline_id] = { character_id,
  level, exp, discipline, hire_time } }`, the ambiguous set, the backups) → corrections with their log lines; and the gate
  that runs the pass once per generation.
- `departure.lua`: the party diff counter (3 misses) and the `returning` retry budget.
- `labels.lua`: every player-facing string (rows, dialogs, notices, Rift and Status marks) from data.
- `targets.lua`: the narrowed predicate.

REFramework glue stays thin; it may be split under `src/autorun/Retinue/game/` (talk menu, dialog, notices, Rift and
Status marks, slot hooks, restore writes). `tests/run.sh` runs everything; the tests cover every table row and error
above, the cap, archive naming, and the guard at equal / lower / higher levels.

The experiment scripts stay in `tools/experiments/` and are never deployed with the mod. `deploy.sh` gains
`--probe-only` (the read-only probe without the mod), for the checklist's uninstall checks; `--remove` never touches
`reframework/data/Retinue/`.

## Done when

1. Every `tests/run.sh` check passes.
2. Every item of the in-game checklist in `docs/testing.md` § M2 passes with the user; opportunistic items are recorded
   as passed or not reached.
3. README (status, uninstall, known limits), the roadmap and `CHANGELOG.md` (Unreleased → Added) are updated. No
   version bump here: tagging 0.1.0 (M1 + M2) is a separate step.

## Known limits (documented in the README)

- Up to ~10 s of progress can be lost when a member is lost (last poll).
- Gear given to any hired pawn, adopted or not, is lost on dismiss and lost; equipment and skills are never restored.
- Without the mod, an away member returns at its first-hire level; reinstalling restores it.
- A restored member comes back with its restored maximum health but the current health of its first-hire state (Folken: 1722/1900) until healed.
- A new game started while the mod is not installed is not seen: the old members become away and must be released.
- Texts are English only.

## Open assumptions the checklist verifies

- `requestDialog` opened inside a talk does not leak the confirming press (else the talk-menu confirm fallback).
- The notice shows over menus and inside a talk, and `requestHideDialog()` never closes a game dialog.
- The talk-menu, Status-page and Rift hooks do not clash with Guild Contracts (none seen in 0007).
- Natural lost (down timer, rest sweep) triggers the party diff like *Kill pawns* did.
- The `CulmativeExp` index write and `_IncreaseParams` `set_field` keep working outside the experiment.
