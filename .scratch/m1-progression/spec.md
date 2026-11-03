# M1 — Progression (spec)

Status: ready for `/to-tickets` · Map: [map.md](map.md) · In-game checklist: [docs/testing.md § M1](../../docs/testing.md#m1--progression)

## Goal

Hired pawns in the party gain levels, discipline and vocation rank exactly as the main pawn does, using the game's
own exp curve and per-level stat gains. This is the first mod code in `src/autorun/`. Progression is lifted at
runtime only and nothing is written to the save ([ADR 0001](../../docs/adr/0001-runtime-lift-not-save-injection.md)).

## Scope

In:

- Level, discipline (`JobContext.ConsumableExpProp`) and the current vocation's rank (from `CulmativeExp`) for every
  **hired pawn currently in the party**, behind one toggle that is on by default.
- Level-up and rank-up notifications that show the hired pawn's own name.
- `config.json` holding the toggle, and a REFramework menu section.

Out (see the map's Out of scope): online pawns get no special handling (offline play is the target, and online pawns
are untested); the main pawn is never altered; roster, adopt/release, dismissal and re-hire are M2; spending discipline,
vocation change and augments are M3; balance options or exp multipliers of any kind.

## Behaviour

### Targets

A **target** is a CharacterID that, at the moment of the hooked call, belongs to a pawn in
`PawnManager._PartyPawnList`, differs from the main pawn's fixed ID `ch100000_00` (2283028347), and for which
`app.PawnUtil.isSubPawn(id)` returns true. `PawnUtil.isSubPawn` may be **called**, but is never hooked (the guild,
equipment and the Rift use it). Party membership may be cached, but the cache must be refreshed at least once per
game frame, so that a pawn swapped at the Rift stops or starts being a target without reloading scripts.

M2 will narrow targets to the roster. Keep the target predicate a single function so that M2 can replace it.

### Progression hooks (the core)

When progression is on, pre-hooks on two `app.ExpDispenser` methods replace a target's CharacterID (argument 1) with
`ch100000_00`:

- `checkLevelUp(app.CharacterID, app.HumanStatusContext, app.Character.JobEnum, System.Boolean, app.DragonHermitContext)`
- `addJobPoint(app.CharacterID, app.JobContext, System.Int32, System.Boolean)`

All other arguments are left as the game passes them. In particular, the Boolean (notification flag) and the exp and
job-point amounts are untouched, and Retinue applies no multiplier of its own.

Rules (findings [0002](../../docs/findings/0002-exp-hook-variants.md), [0004](../../docs/findings/0004-other-mods-on-exp-path.md)):

- **Hook the leaves only.** Never hook or rewrite either `addExpAndJobPoint` overload. Doing so would make
  SimpleDifficultyTweaks treat hired pawns as the main pawn, and would hide the real ID from other mods' hooks.
- **No `isSubPawn` hook anywhere** (`ExpDispenser.isSubPawn` is never called; `PawnUtil.isSubPawn` is shared).
- **Banked experience** is applied as the game computes it. A long-hired pawn may jump several levels on its first
  grant and get one notification for the range. Exp is never zeroed or clamped.
- **No retroactive gains.** Progression starts when the hooks are active and the toggle is on.

### Notification swap-back

`checkLevelUp` and `addJobPoint` call `dispLevelUpUI` and `GuiManager.reqJobRankUp` synchronously with the rewritten
ID. Retinue puts the real ID back so the notification names the hired pawn ([0003](../../docs/findings/0003-notification-swap-back.md)):

- Pre-hooks on `app.ExpDispenser.dispLevelUpUI(app.CharacterID, System.Int32, System.Int32)` and
  `app.GuiManager.reqJobRankUp(app.CharacterID, app.Character.JobEnum, System.Int32, System.Int32)` replace argument 1
  **only when** it equals `ch100000_00` **and** the innermost open `checkLevelUp` / `addJobPoint` call was rewritten. The
  replacement is that call's real ID.
- The core pre-hook pushes one frame per `checkLevelUp` / `addJobPoint` call, whether or not it rewrote; the
  matching post-hook pops it. A frame carries the real ID (`real`) only when the call was rewritten, and `real` is
  set after the argument write succeeds. The swap looks only at the **top** frame, so a main-pawn or toggle-off call
  (a frame with no real ID) always shadows a stale rewritten frame below it. Frames whose post-hook never ran are
  dropped when an outer post-hook pops, and the stack is cleared at the start of every game frame (on the game thread, before
  `UpdateBehavior`, so a clear can never fall between a core call and its notification). A stale entry
  must never rename a later notification, such as the player's rank-up from SkillCreator's `addJobPointInternal`
  call or the main pawn's own level-up.
- Every other call to these methods passes through untouched.

### Toggle

- When progression is **off**, the hooks stay installed but do nothing: no rewrite (core calls still push a
  frame without a real ID, which renames nothing). Hired pawns behave as in vanilla, so exp banks and no discipline is gained.
- A change takes effect **immediately**, including mid-fight. The next call reads the current value.
- Turning progression off reverts nothing. Levels, discipline and rank already gained stay.

### Failure handling

- Every hook body runs under `pcall`, and every pre-hook returns `CALL_ORIGINAL`. On an error the arguments are left
  as passed (no partial rewrite), a failing call's frame never carries a real ID, and the error is logged once per
  method and message, not every frame.
- Hooks are installed once at script load. Methods are looked up by full signature first, then by name plus parameter
  type names. Reuse `find_method` from `tools/experiments/Retinue_Exp_Hooks.lua`.
- **All or nothing.** If any of the four methods is not found, progression is unavailable for the session. Hooks that
  did install do nothing, and the menu shows the notice (below). A game update that renames one member must not leave
  progression without notifications, or notifications without progression.

### `config.json`

Path `reframework/data/Retinue/config.json` (`json.load_file` / `json.dump_file` path `Retinue/config.json`). It is
separate from M2's roster. The answer to [Decide the shape of `config.json` and the M1 mod-menu section](issues/07-config-and-menu-shape.md) governs:

```json
{ "version": 1, "progression": true }
```

- **Missing file**: defaults in memory, and nothing is written until the user changes a setting.
- **Per-key resolution**: a key with the right type is used. A missing or wrongly typed key gets its default and a
  warning in the REFramework log (`log.warn`). An unparseable file or a non-object top level means all defaults plus a
  warning. A `version` higher than 1 is read for the keys known. An unparseable file is not overwritten until the user
  changes a setting. On rewrite, unknown keys are preserved and `version` is set to 1 unless the file holds a higher
  one.
- **Timing**: read once at script load (game start or *Reset scripts*). Written immediately on every change from the
  menu. `re.on_config_save` is not used.

### Menu

One `imgui.tree_node("Retinue")` in `re.on_draw_ui`. All text is in English.

- Checkbox `Hired pawns gain levels and vocation ranks`, bound to `progression`.
- A read-only status line with the targets currently in the party:
  `Applies to: <name> (Lv <level>, <vocation> R<rank>, Disc <discipline>), ...`, or `No hired pawns in party`, or `Load a save` when
  `PawnManager` is not available. Vocation names follow `CONTEXT.md`. Names come from `GUIBase.getName(app.Character)`
  as in the experiment.
- When hooks are missing: `Progression unavailable: <method> not found (game update?)`, listing each missing method.
  The checkbox stays usable, and its value is still saved.

## Code layout and tests

- `src/autorun/Retinue.lua`: entry point that wires config, hooks and menu.
- `src/autorun/Retinue/*.lua`: modules loaded with `require("Retinue.<name>")`. The pure-Lua logic lives in modules
  with no REFramework globals: config parsing and merging, the open-call stack and swap decision, and status-line
  formatting. The REFramework-facing glue stays thin.
- `deploy.sh` must link the `Retinue/` folder as well as the entry file. Check that the existing loop over
  `src/autorun/*` already does; `.gitkeep` is removed.
- Tests: plain `lua5.4` scripts in `tests/` with `assert`, no external framework. `tests/run.sh` runs them all and
  exits non-zero on failure. Cover:
  - config: missing, valid, wrong-typed key, garbage, higher version, unknown keys kept;
  - swap decision: rewritten call open versus not, nested calls, a stale entry after a missing post-hook, frame reset,
    and non-main IDs passing through;
  - status-line formatting.
- The experiment script stays in `tools/experiments/`. **Never deploy it alongside the mod**, because both would
  rewrite. The checklist step uses `./deploy.sh --remove` first.

## Compatibility (findings 0004)

No installed mod conflicts. Documented for users in the README:

- Exp may arrive already scaled by Bestiary (all recipients) or SimpleDifficultyTweaks (player and main pawn only).
  With an SDT EXP/DCP multiplier other than 1, adopted pawns progress at the vanilla rate. This is a known difference
  and is not mirrored in M1.
- Grants that other mods make through `addExpAndJobPoint` (for example UDD2P's Sphinx reward) level hired pawns too.
- Do not combine Retinue with another mod that lifts the hired-pawn exp gate, or that hooks `checkLevelUp` /
  `addJobPoint`.

## Done when

1. Every `tests/run.sh` check passes.
2. Every item of the in-game checklist in `docs/testing.md` § M1 passes with the user. The opportunistic items are
   recorded as passed, or as not reached.
3. README status, the roadmap and `CHANGELOG.md` (Unreleased → Added) are updated. No version bump: 0.1.0 is M1 + M2.

## Open assumptions the checklist verifies

- `sdk.hook` fires for calls made from Lua with `method:call` (UDD2P, SkillCreator). If it does not fire, mod-originated
  grants do not level hired pawns. That is a limitation, not a bug.
- The one-off freeze on save → title → load after a level-up (0003) is not caused by Retinue.
