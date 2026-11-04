# Run the dismiss / lost / re-hire experiment in game

Type: task
Status: claimed
Blocked by: 03

## Question

With the M1 mod active and a hired pawn levelled past its Rift level: dismiss it and re-hire it; let a pawn be lost;
save/load between steps. Answer, with data: is the re-hired pawn recognised by `_OfflineID` (same or new
CharacterID)? Which state survives (level, exp, discipline, vocation ranks, equipment) and which is lost?
Does a lost pawn ever come back? `tools/saves.sh backup <label>` first; findings note after.

## Run log

- Step 0 (2026-11-03): backup `m2-lifecycle-start`, deployed `--probe --lifecycle`; all hooks installed, pawn data visible.
- Step 1 (a): pawn **Folken**, CharacterID 1601809365, OfflineID `426f7888`, Warrior (5), party slot 3.
  Lv 23 (exp 210) → Lv 27 via Grant exp. Snapshot `a-levelled`, saved, backup `fixture-levelled-pawn`.
- Step 2 (b): real dismiss of Folken through the Rift menu. Snapshot labels: `b0-before-dismiss` before touching the
  stone; the post-dismiss snapshot was **also labelled b0** (take the later one, or `auto:dismiss`), then `b2-saved`,
  `b3-after-reload`. On screen: no item-return message, nothing odd. Live table after dismiss and after reload:
  Folken "record gone"; dismissed list count 7.
- **Run files of steps 1–2 are unusable for the dismiss** (`docs/findings/data/2026-11-03-m2-lifecycle/b/`, 21 MB each):
  at load `StrayPawnFactoryProductOffline.restorePastInformation` filled the 20000-call cap in ~6 s (pre+post, not
  capped per hook), and a lost-group hook fired an `auto:lost` snapshot ~10/s, filling the 400-snapshot cap within
  ~40 s of load. Every later call and every manual snapshot (incl. the dismiss) was dropped. Step 2 must be redone
  from `fixture-levelled-pawn` after a script fix.
- Salvaged facts: `StrayPawnPastInformationMax` = 100, `RelationPawnDismissNum` = 30. The dismissed list held 7 entries
  *before* the step-2 dismiss, Folken already among them at **Level 23** while he was hired at Lv 23–27 (a past
  dismissal of him; his entry's `CharaID` 1857826560 is the same for all 7 entries, probably not a real id).
