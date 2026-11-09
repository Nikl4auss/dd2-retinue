# Plan: ticket 29, exp and next level on the Status page for members

Spike (peer, 2026-11-09, comment in ticket 29, data `docs/findings/data/2026-11-09-t29-exp-spike/`): the "-" in "Experience",
"Current Discipline" and "Next" comes from `ui060601_01.setupStatus(CharaData)` and `setupJob(CharaData)`, which gate on the
CharaData's `<IsMainPawn>k__BackingField`. Setting it true in their pre and back in their post shows the member's own numbers
(exp 2960/17030, 2078 Dcp, Next 2922 Dcp); switching to the main pawn or Arisen afterwards shows theirs; no error.
`hideExp`/`setExp` are the row-description box, not involved. `_OfflineID` is not the gate.
Cross-review: skipped (unavailable, see memory); the Opus reviewer covers the plan gate.

Scope decision (orchestrator): present members only, the same rule as the header mark (`marks_logic.status_member`). A hired
non-member keeps the vanilla "-" (it does not progress). Away members are not in the party, so not on the page.

## Slice 1: show a member's exp on the Status page — implementer (Sonnet) — [ ]

**Goal**: pause > Status shows a present member's own exp / next level (Status tab) and discipline / next rank (Vocation tab),
like the main pawn's. The Arisen, the main pawn and hired non-members are unchanged. A missing type, method or field leaves
the page vanilla (menu "unavailable" line, one log line).

**Context**: read `src/autorun/Retinue/game/marks.lua` (whole file: lookups/finish, new_stack, the Status group's
pre/post-with-stack pattern, `status_member`), `src/autorun/Retinue/marks.lua` (`status_member`), `src/autorun/Retinue.lua`
lines ~90-130 and ~215-230 (construction, the menu's `marks.missing` lines and any `status_available` use),
`tests/marks_glue_test.lua` (the fake sdk: TYPES table, `hooked`, `world`, `missing_name`; copy its style),
`src/autorun/Retinue/hooks.lua` (`install`, `find_method`, `to_managed`). Spike script for reference only:
`docs/findings/data/2026-11-09-t29-exp-spike/Retinue_Spike_ExpPanel.lua` (variant c).

**Design**:
- `game/marks.lua`: a third hook group, "status exp", independent of the other two (its own lookups and `finish`, so a
  missing member disables only it). New field `marks.exp_available` (boolean). Its missing names go into the shared
  `marks.missing`.
  - Lookups: type `app.ui060601_01` methods `setupStatus(app.GUIBase.CharaData)` and `setupJob(app.GUIBase.CharaData)`;
    `app.GUIBase.CharaData` fields `CopyOwner` and `<IsMainPawn>k__BackingField`; `app.PawnOwnerContext` field `_OfflineID`.
  - Two entries, keys `marks.setupStatus` and `marks.setupJob`, same shape. Pre (when `marks.exp_available`):
    1. Restore first: if the hook's stack still holds frames (a post that never came), pop every frame and put back any flag
       it set (below), reporting once `("status exp", "a post did not run; flag restored")` through `report`.
    2. Push a frame `{}` before reading anything (same rule as the other hooks), then `frame.cd = hooks.to_managed(args[3])`.
    3. If `cd` is non-nil, its `IS_MAIN_PAWN` field is not `true`, and `status_member(cd)` (reuse the existing local, it reads
       CopyOwner._OfflineID and checks present-member and not-main) is true: `cd:set_field(IS_MAIN_PAWN, true)` and
       `frame.flipped = true`. Any throw in steps 2-3: report `("status exp", <what> .. " failed: " .. err)`, and if the
       set_field happened, frame.flipped is true so the post still restores. Wrap so the pre never raises.
    4. Return nothing (call the original).
  - Post: pop the frame; if `frame.flipped`, `cd:set_field(IS_MAIN_PAWN, false)` under pcall (report on failure). The flag
    is only ever written back to false, and only on a CharaData we set to true (a member is never a main pawn: the
    member check requires the flag false).
  - The first time a member's flag is set per offline id, `log.error("[Retinue] status exp: shown for member <offline_id>")`
    (a `seen` key such as `"exp " .. id`), so the in-game run can grep it without a line per refresh.
  - Update the module header comment: three surfaces, and a short paragraph for this one (the gate is `IsMainPawn` in
    setupStatus/setupJob, findings: ticket 29 spike; set only for the call, never left set).
- `Retinue.lua`: nothing new is needed if the menu already lists `marks.missing`; if any code or menu line reports the
  status/rift availability by name, add the exp group the same way. Update the header comment line about marks to mention
  the exp panel.
- `marks.lua` (pure): no change expected. If you add a helper, test it in `tests/marks_test.lua`.

**Acceptance criteria**:
- [ ] `tests/marks_glue_test.lua` (extend the fake: TYPES gets the two methods and nothing else breaks):
  - present member: in the pre the CharaData's IsMainPawn is set true; after the post it is false again; the log line once
    over two calls; for both setupStatus and setupJob.
  - main pawn (flag already true), Arisen-like CharaData (no CopyOwner / zero id), hired non-member, away member: the flag is
    never written (assert no set_field call), for both hooks.
  - a missing pre/post pair: pre, pre (no post between) → the first frame's flag is restored at the second pre, one report.
  - a throwing set_field in the post is reported, not raised; a nil CharaData arg writes nothing, no raise.
  - a missing `setupJob` signature (missing_name) leaves `exp_available` false and lists it in `marks.missing`, while
    `status_available` and `rift_available` stay true; and a missing Status-group member leaves `exp_available` true.
- [ ] Existing marks tests unchanged and passing; `tests/run.sh` all PASS.
- [ ] `luac5.4 -p` (or `luac -p`) on every changed .lua file.

**Verify**: `tests/run.sh`; `luac5.4 -p src/autorun/Retinue/game/marks.lua src/autorun/Retinue.lua tests/marks_glue_test.lua`.

**Out of scope**: docs (spec, CHANGELOG, findings: the orchestrator writes them), any in-game run, deploy.sh, experiments,
writing exp texts by hand, non-member hired pawns, `setupPawn`/`setupExp`/`setExp`.

## After slice 1 (orchestrator)

- Docs: spec § Status (native) bullet; findings 0009 gets a P7 section from the spike comment; CHANGELOG unreleased; CONTEXT
  only if a term changes.
- In-game check to the peer: Slot 2 member Diamonds (Status and Vocation tabs show her own numbers; Shaira and Klauss
  unchanged after switching; header mark still there); a non-member hired pawn if one can be hired in the Rift (stays "-");
  a fight's exp moves Diamonds' numbers. Manual feel pass for the user after that.
