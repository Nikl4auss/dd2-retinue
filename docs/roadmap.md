# Roadmap

Each milestone runs the same loop: **experiment → findings → decision (ADR if there is a real choice) →
implementation → review → in-game test checklist → commit** (and a tag when it completes a release).

Releases: **0.1.0** = M1 + M2 (first playable). Later milestones bump the minor version.

This file is the index of milestones, not a task list. Bullets under a milestone that has not started are a scope
sketch. When a milestone starts, its work moves to the issue tracker under `.scratch/<milestone-slug>/`
(see [agents/issue-tracker.md](agents/issue-tracker.md)): a `/wayfinder` map while there are open questions, then a
spec and tickets. The sketch is then replaced by a link to that folder, and the status line is kept up to date here.

## M0 — Research · done

- [x] Dump the type database and build query tools (`tools/dump/`)
- [x] Read Arisen's Own 1.3.2 to locate the relevant game systems
- [x] Probe how hired pawns behave across combat and save/load → [findings/0001](findings/0001-hired-pawn-baseline.md)
- [x] Map the API needed for M1–M5 → [findings/api-map.md](findings/api-map.md)
- [x] Locate the save folder and script the backup step → `tools/saves.sh`, [testing.md](testing.md)

## M1 — Progression · done

Adopted pawns gain levels and discipline like the main pawn. In M1 this applies to every hired pawn in the party;
M2 narrows it to the roster. All tickets done; checklist run in
[findings/0005](findings/0005-m1-checklist-run.md).
Spec: [.scratch/m1-progression/spec.md](../.scratch/m1-progression/spec.md) (from the wayfinder map
[map.md](../.scratch/m1-progression/map.md)); in-game checklist in [testing.md](testing.md#m1--progression).

## M2 — Identity and persistence · done

Adopt up to two pawns (the party is main pawn + two adopted); they keep their identity and progress across dismiss,
lost and re-hire, and uninstalling leaves ordinary hired pawns. Tickets 16–27 are done; checklist run in
[findings/0011](findings/0011-m2-checklist-run.md). Follow-ups done: ticket 28 (a restart over a cleared slot keeps the
roster), ticket 29 (a member's exp on the Status page).
Spec: [.scratch/m2-identity/spec.md](../.scratch/m2-identity/spec.md) (from the wayfinder map
[map.md](../.scratch/m2-identity/map.md)); in-game checklist in [testing.md](testing.md#m2--identity-and-persistence).

## M3 — Vocation

- Allow vocation change for adopted pawns at the Vocation Guild (`CharaChangeJobGuildRef.ListInfo.IsSubPawn`)
- Augments and skills per vocation

## M4 — Equipment

- Lift hired-pawn equip restrictions (`ItemIDUtil.isSubPawnDisableEquipItem`, `GUIBase.isSubpawnDisableEquipStorage`)
- Items stay with the pawn (no `ItemManager.returnSubPawnItems` for adopted pawns)
- Gear across dismiss / lost / re-hire: refund gifts at departure **or** re-equip from the backup on re-hire, never both
  (duplication). Skipping `returnSubPawnItems` probably loses carried items (inferred; test on a throwaway save first).
  Prior art and pitfalls: [findings/research-pawn-gear-mods.md](findings/research-pawn-gear-mods.md) (Arisen's Company 1.2
  overlaps Retinue: detect and warn). Decided 2026-11-08: nothing of this in M2 (the backup keeps item IDs only).

## M5 — Name

- Rename (`PawnDataContext.setName`, `_Nickname`), persisted across save/load

## M6 — Appearance

- Open the game's appearance editor for an adopted pawn

## M7 — Creation from scratch (optional)

- Re-evaluate after M6; this is where Arisen's Own spends most of its complexity
