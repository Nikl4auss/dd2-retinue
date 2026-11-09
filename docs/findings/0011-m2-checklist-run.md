# 0011 — M2 in-game checklist run

Date: 2026-11-08 · Checklist: [testing.md § M2](../testing.md#m2--identity-and-persistence) · Ticket:
[27](../../.scratch/m2-identity/issues/27-docs-probe-only-checklist-run.md) · Mod code at `32074a4` (docs `6eb6a43`) ·
REFramework `d4611aef` · Run files: [data/2026-11-08-m2-checklist/](data/2026-11-08-m2-checklist/) (one `<run>.txt` per run,
logs, sha256 lists `.before` / `.after`, screenshots as 960 px JPEG, the lifecycle snapshot xz-compressed)

Offline play. Two parts on the same build, never at the same time:

- **Headless** (peer session, gamescope, keys and mouse by XTEST, no user): runs A–F, from the fixture
  `20261106-083816-m2-adopted-folken` (slot 2: Folken adopted Lv 28, hired at Lv 23; Diamonds hired, Lv 24) and its derivative
  `20261108-175342-m2-t27-folken-dismissed`. Deploy `./deploy.sh --probe --lifecycle`, or `--probe-only` for the uninstall checks.
- **Manual** (the user, keyboard and pad): checks 2, 14, 17, 27, 34, a real fight and the free play. Backups
  `m2-t27-manual-pre`, `m2-t27-real-pre`. The real save is slot 1 (pawns around Lv 300).

Other mods active throughout, among them Guild Contracts, Nick's Devtools, NickCore, Bestiary, SimpleDifficultyTweaks, UDD2P and
PartyBox. `reframework/autorun/Arisens Own/` is an empty leftover folder, no script.

Rule for checks passed in earlier tickets: a pass on a build whose later changes do not touch the check stands (source in the
table); everything else was run here.

## Results

| # | Result | Run | Evidence |
|---|---|---|---|
| 1 Fresh install | pass | A | `Slot 2: roster ok (0/2)`, no `slots/` created, no warning in 60 s; menu "Slot 2 · roster ok (0/2)" with Adopt per pawn; talk row Adopt 4th of 5, B on Never mind |
| 2 Talk menu | pass | A + user | Field (A) and at the Rift stone (user) |
| 3 Adopt | pass | ticket 24/25, F | "Confirm adopt" / Cancel on `b81adc3`; Diamonds adopted in F |
| 4 Adopted status | pass | ticket 26 | `1abfddc`, peer and user |
| 5 Progression | pass | F + user | Grant exp: Folken 28→30 with his own notification, Diamonds no level; backup in 9.7 s / 8.6 s, mtime unchanged ~110 s idle; only `in the world: no` is the title. Real fight: Folken levelled (user) |
| 6 Toggle off | pass | F | Exp banks (23430→73430) at Lv 30, backup follows in 4 s; re-ticked |
| 7 Release | pass | F, E31 | `released Diamonds (backup emptied)`, root reads Adopt, stays Lv 24, Grant exp no level |
| 8 Cap | pass | F | "Slot 2 · roster ok (2/2)", both with Release |
| 9 Not adoptable | not reached | — | Offline play only |
| 10 Dismiss | pass | D | Real dismiss by the talk menu in the Rift: `present→away (dismiss)`, character_id kept, backup sha256 unchanged |
| 11 Previous Hires mark | pass | D | "★ Folken · Lv 28", others plain |
| 12 Return and restore | pass | D, E29 | `restored Lv 23→28`, notice 3.08 s; m2-a = m2-b on level, exp, discipline, vocation exp, rank, skills; `increase_params` equal (E29, from the backup); save, reload, relaunch: no second restore. Centring seen on E29's shots |
| 13 Retinue full | pass | ticket 25 | `725bbe9`, peer and user |
| 14 Lost | pass | user | *Kill pawns*, main pawn back 22:46:41, `present→away (absence)` 22:46:44; ★ mark, restored 23→28, notice. No false absence through a ferrystone, a death + load last save, and title + load. Natural lost not reached |
| 15 Level guard | pass | ticket 19/23 | Log `8ac13df`, notice `83b4485` |
| 16 Other route | not reached | — | |
| 17 Gear | pass | user | The armour is gone from storage after the dismiss (known limit) |
| 18 Per slot | pass | B | Slot 1 roster ok (0/2), no notice, no `slots/1/` created, Folken not there; slot 2 again (1/2) |
| 19 Rollback | pass | F + user | `save has Lv 28, backup had Lv 30 -> backup lowered, save wins`. The user's death reload hit it too (an autosave from Lv 27) |
| 20 Reconciliation | pass | ticket 21, E29 | `efdabec`; 20b's notice seen in E29 (same code path) |
| 21 New game | pass | ticket 22 | `4636245`; leftovers in ticket 28 |
| 22 NG+ | partial | ticket 22 | Roster kept over a cleared slot (slot 1, 2026-11-07); the valid-backup case is open in ticket 28 |
| 23 Locked | pass | C23 | Notice once; talk row refuses and ends the talk; files unchanged after a dismiss and a save; 3 members locked; Reset scripts normal. Dismiss by the panel (Hail missed Folken) |
| 24 Soft error | pass | C24 | `banana` → away → `present, save wins`; `name: 5` → "(unknown)" → Folken 3 s in. Log only: the menu was not caught before the fix-up |
| 25 Read-only | pass | C25 | Notice once; Release refused; nothing under `slots/2/` changed through a dismiss and two saves. Dismiss by the panel |
| 26 Damaged backup | pass | C26 | Away: `skipped: no backup`, present at Lv 23, rewritten in 4.5 s; "★ Folken" without level. Present: rewritten 13.2 s after the world. Menu note not caught; one member only |
| 27 Present member uninstall | pass | user, slot 1 | Hinata adopted Lv 318; `--probe-only`; no Retinue line; playable; ordinary (exp 6067→156123 at Lv 318, vanilla talk rows, plain Status). Data folder untouched |
| 28 Away member uninstall | pass | E28 | `--remove` left the data folder byte-identical; no Retinue line; plain "Folken" in Previous Hires; re-hired Lv 23, exp 0, vanilla talk rows |
| 29 Reinstall after Return | pass | E29 | `re-hired unseen`, restored 23→28, notice centred; title without saving + load: restored again, backup still Lv 28 |
| 29b Hire time | recorded | E29 | hire_time 37991999→40020926, character_id 1601809365→372209474. A same-ID re-hire was not seen |
| 30 Returning member | covered | 20c + 28 | |
| 31 Released pawn | pass | E31 | Released, roster `null`, backup 0 bytes; uninstalled: Lv 28, vanilla, playable. Previous Hires not reached (camera stuck) |
| 32 New game uninstalled | not reached | — | |
| 33 Notice deferral | pass | ticket 23 | `83b4485` |
| 34 Guild Contracts | pass | user | Its talk options and Retinue's row together; no other mod's error while Retinue was loaded |

## Facts learned

- **character_id is not unique across saves.** Folken's re-hire in slot 2 got 372209474 (twice, from the same state), and Hinata in
  the user's slot 1 has 372209474 too. Identity is the Offline ID; the character_id only tells a re-hire from a rollback for the
  same Offline ID, so this is harmless, but nothing may key on the character_id alone.
- **A death reload can load an older autosave** than the last manual save (Folken Lv 27 there): the save-wins rule handled it.
- The game asks for a gift and a rating on a talk-menu dismiss; cancelling the gift still dismisses.
- Headless: XTEST mouse clicks REFramework widgets (Input Passthrough ticked), so the lifecycle panel and the probe are reachable;
  the full Rift flow works; Hail on a specific pawn in the field is luck.
- The lifecycle experiment's snapshot has no `_IncreaseParams` and its equipment slots error (`Retinue_Exp_Lifecycle.lua:448`):
  experiment tool, out of scope; the backup's `increase_params` served instead.

## Open after the run

- [Ticket 29](../../.scratch/m2-identity/issues/29-status-exp-panel.md) (user, during the run): the Status page shows no exp or
  next-level for a member. The page has its own exp panel (`setExp`, `hideExp`).
- [Ticket 28](../../.scratch/m2-identity/issues/28-new-game-leftovers.md): NG+ with a valid backup, Start from Beginning.
- Not reached: 9, 16, 32, 22's valid-backup case, natural lost, a same-ID re-hire.
